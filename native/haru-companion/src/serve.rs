//! Unix socket for one local client. Mode 0600, peer uid checked, no TCP.
//!
//! `fchmodat` with `AT_SYMLINK_NOFOLLOW` uses Linux `/proc/self/fd`. If that
//! directory is missing, the call fails and `bind_socket` fails closed: it
//! unlinks only the inode it created and returns the error. A parent that is
//! group or world writable is refused, unless it is sticky and owned by the
//! effective uid, in which case it is tightened to 0700 before the bind.

use crate::backend::ModelBackend;
use crate::engine::Engine;
use crate::protocol::FrameBuf;
use crate::session::ChildControl;
use std::ffi::CString;
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct NodeId {
    dev: u64,
    ino: u64,
}

struct DirFd {
    fd: i32,
}

impl Drop for DirFd {
    fn drop(&mut self) {
        if self.fd >= 0 {
            unsafe { libc::close(self.fd) };
            self.fd = -1;
        }
    }
}

/// Dup of a bound listener. Wakes that inode through `/proc/self/fd` so a
/// replaced path is never connected.
pub struct BoundWatch {
    fd: i32,
    pub dev: u64,
    pub ino: u64,
}

impl Drop for BoundWatch {
    fn drop(&mut self) {
        if self.fd >= 0 {
            unsafe { libc::close(self.fd) };
            self.fd = -1;
        }
    }
}

impl BoundWatch {
    pub fn watch(listener: &UnixListener, path: &Path) -> std::io::Result<Self> {
        // The listening fd and the directory entry do not share dev/ino here.
        // Remember the entry observed while this listener is still bound to it.
        let node = path_node(path)?;
        let fd = unsafe { libc::dup(listener.as_raw_fd()) };
        if fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok(Self {
            fd,
            dev: node.dev,
            ino: node.ino,
        })
    }

    pub fn still_ours(&self, path: &Path) -> bool {
        match path_node(path) {
            Ok(node) => node.dev == self.dev && node.ino == self.ino,
            Err(_) => false,
        }
    }

    /// Unblocks `accept` on the original inode. The directory path is used
    /// only when `/proc/self/fd` cannot be connected and the inode still matches.
    pub fn wake(&self, path: &Path) {
        let via_proc = std::path::PathBuf::from(format!("/proc/self/fd/{}", self.fd));
        if UnixStream::connect(&via_proc).is_err() && self.still_ours(path) {
            let _ = UnixStream::connect(path);
        }
    }
}

/// True when `path` still names the inode `listener` is bound to.
pub fn listener_matches(listener: &UnixListener, path: &Path) -> std::io::Result<()> {
    listener.set_nonblocking(true)?;
    let probe = UnixStream::connect(path);
    let mut accepted = false;
    if probe.is_ok() {
        for _ in 0..50 {
            match listener.accept() {
                Ok(_) => {
                    accepted = true;
                    break;
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(2));
                }
                Err(error) => {
                    listener.set_nonblocking(false)?;
                    return Err(error);
                }
            }
        }
    }
    listener.set_nonblocking(false)?;
    drop(probe);
    if accepted {
        Ok(())
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "socket replaced",
        ))
    }
}

/// Unlinks the directory entry only when its dev/ino is the one we recorded.
pub fn unlink_if_ours(path: &Path, dev: u64, ino: u64) -> std::io::Result<()> {
    let dir = open_dir(parent_path(path))?;
    let name = file_name(path)?;
    let at = match fstatat_name(dir.fd, &name) {
        Ok(node) => node,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    if at.dev != dev || at.ino != ino {
        return Ok(());
    }
    if unsafe { libc::unlinkat(dir.fd, name.as_ptr(), 0) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

/// `euid` is accepted so tests can stand in for another uid. The current
/// implementation ignores it and uses the process euid.
pub fn bind_socket_as(path: &Path, euid: u32) -> std::io::Result<UnixListener> {
    let _ = euid;
    bind_socket(path)
}

pub fn bind_socket(path: &Path) -> std::io::Result<UnixListener> {
    let parent = parent_path(path);
    let created = !parent.exists();
    if created {
        std::fs::create_dir_all(parent)?;
    }
    let dir = open_dir(parent)?;
    if created && unsafe { libc::fchmod(dir.fd, 0o700) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    prepare_parent(&dir)?;
    let name = file_name(path)?;
    clear_stale(dir.fd, &name, path)?;
    let listener = UnixListener::bind(path)?;
    let ours = fstatat_name(dir.fd, &name)?;
    let chmod_rc =
        unsafe { libc::fchmodat(dir.fd, name.as_ptr(), 0o600, libc::AT_SYMLINK_NOFOLLOW) };
    if chmod_rc != 0 {
        let error = std::io::Error::last_os_error();
        let _ = unlink_name_if(dir.fd, &name, ours);
        return Err(error);
    }
    match fstatat_name(dir.fd, &name) {
        Ok(node) if node == ours => Ok(listener),
        Ok(_) => Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "socket replaced",
        )),
        Err(error) => Err(error),
    }
}

fn parent_path(path: &Path) -> &Path {
    match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    }
}

fn c_path(path: &Path) -> std::io::Result<CString> {
    CString::new(path.as_os_str().as_bytes())
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "path contains a nul"))
}

fn file_name(path: &Path) -> std::io::Result<CString> {
    let name = path.file_name().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "socket path has no file name",
        )
    })?;
    CString::new(name.as_bytes())
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "path contains a nul"))
}

fn open_dir(path: &Path) -> std::io::Result<DirFd> {
    let path = c_path(path)?;
    let fd = unsafe {
        libc::open(
            path.as_ptr(),
            libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW,
        )
    };
    if fd < 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(DirFd { fd })
    }
}

fn prepare_parent(dir: &DirFd) -> std::io::Result<()> {
    let st = fstat_raw(dir.fd)?;
    let uid = st.st_uid;
    if uid != unsafe { libc::geteuid() } {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "parent not owned by euid",
        ));
    }
    let mode = st.st_mode;
    let group_or_world_writable = mode & 0o022 != 0;
    let sticky = mode & libc::S_ISVTX != 0;
    if group_or_world_writable && !sticky {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "parent is group or world writable",
        ));
    }
    if mode & 0o077 != 0 && unsafe { libc::fchmod(dir.fd, 0o700) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let again = fstat_raw(dir.fd)?;
    if again.st_uid != uid || again.st_mode & 0o077 != 0 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "parent is not mode 0700",
        ));
    }
    Ok(())
}

fn clear_stale(dirfd: i32, name: &CString, full: &Path) -> std::io::Result<()> {
    let before = match fstatat_raw(dirfd, name) {
        Ok(st) => st,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    let kind = before.st_mode & libc::S_IFMT;
    if kind == libc::S_IFSOCK {
        match UnixStream::connect(full) {
            Ok(live) => {
                drop(live);
                return Err(std::io::Error::new(
                    std::io::ErrorKind::AddrInUse,
                    "socket is live",
                ));
            }
            Err(error) if error.kind() == std::io::ErrorKind::ConnectionRefused => {}
            Err(error) => return Err(error),
        }
        let after = fstatat_raw(dirfd, name)?;
        if node_of(&before) == node_of(&after) && after.st_mode & libc::S_IFMT == libc::S_IFSOCK {
            unlink_name_if(dirfd, name, node_of(&before))?;
        }
        Ok(())
    } else if kind == libc::S_IFLNK {
        unlink_name_if(dirfd, name, node_of(&before))
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::AlreadyExists,
            "refusing to replace a non-socket",
        ))
    }
}

fn unlink_name_if(dirfd: i32, name: &CString, expected: NodeId) -> std::io::Result<()> {
    let now = match fstatat_name(dirfd, name) {
        Ok(node) => node,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    if now != expected {
        return Ok(());
    }
    if unsafe { libc::unlinkat(dirfd, name.as_ptr(), 0) } != 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn path_node(path: &Path) -> std::io::Result<NodeId> {
    let dir = open_dir(parent_path(path))?;
    let name = file_name(path)?;
    fstatat_name(dir.fd, &name)
}

fn fstat_raw(fd: i32) -> std::io::Result<libc::stat> {
    let mut st: libc::stat = unsafe { std::mem::zeroed() };
    if unsafe { libc::fstat(fd, &mut st) } != 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(st)
    }
}

fn fstatat_name(dirfd: i32, name: &CString) -> std::io::Result<NodeId> {
    Ok(node_of(&fstatat_raw(dirfd, name)?))
}

fn fstatat_raw(dirfd: i32, name: &CString) -> std::io::Result<libc::stat> {
    let mut st: libc::stat = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::fstatat(dirfd, name.as_ptr(), &mut st, libc::AT_SYMLINK_NOFOLLOW) };
    if rc != 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(st)
    }
}

#[cfg(target_os = "linux")]
fn node_of(st: &libc::stat) -> NodeId {
    NodeId {
        dev: st.st_dev,
        ino: st.st_ino,
    }
}

#[cfg(not(target_os = "linux"))]
fn node_of(st: &libc::stat) -> NodeId {
    NodeId {
        dev: st.st_dev as u64,
        ino: st.st_ino as u64,
    }
}

pub fn current_uid() -> u32 {
    unsafe { libc::geteuid() }
}

pub fn peer_uid(stream: &UnixStream) -> std::io::Result<u32> {
    peer_uid_fd(stream.as_raw_fd())
}

/// Injected credentials for tests. Production accept uses [`OsPeer`].
pub trait PeerCheck {
    fn allow(&self, stream: &UnixStream) -> std::io::Result<()>;
}

/// Real `SO_PEERCRED` / `getpeereid` compared with `geteuid`.
pub struct OsPeer;

impl PeerCheck for OsPeer {
    fn allow(&self, stream: &UnixStream) -> std::io::Result<()> {
        let peer = peer_uid(stream)?;
        if peer != current_uid() {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "peer uid",
            ))
        } else {
            Ok(())
        }
    }
}

/// Test double. `peer` is the connecting uid and `owner` is the process uid.
pub struct FixedPeer {
    pub peer: u32,
    pub owner: u32,
}

impl PeerCheck for FixedPeer {
    fn allow(&self, _stream: &UnixStream) -> std::io::Result<()> {
        if self.peer != self.owner {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "peer uid",
            ))
        } else {
            Ok(())
        }
    }
}

pub fn serve_one<B, C>(listener: UnixListener, engine: &mut Engine<B, C>) -> std::io::Result<()>
where
    B: ModelBackend,
    C: ChildControl,
{
    serve_one_with(listener, engine, &OsPeer)
}

pub fn serve_one_with<B, C, P>(
    listener: UnixListener,
    engine: &mut Engine<B, C>,
    peer: &P,
) -> std::io::Result<()>
where
    B: ModelBackend,
    C: ChildControl,
    P: PeerCheck,
{
    let (mut stream, _) = listener.accept()?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    if let Err(error) = peer.allow(&stream) {
        let _ = stream.write_all(&crate::protocol::peer_error_frame());
        finish_session(engine);
        return Err(error);
    }
    let mut framer = FrameBuf::default();
    let mut buffer = [0u8; 8192];
    let mut outcome = Ok(());
    'read: loop {
        let read = stream.read(&mut buffer);
        let count = match read {
            Ok(0) => break,
            Ok(count) => count,
            Err(error)
                if error.kind() == std::io::ErrorKind::WouldBlock
                    || error.kind() == std::io::ErrorKind::TimedOut =>
            {
                continue
            }
            Err(error) => {
                outcome = Err(error);
                break;
            }
        };
        let frames = match framer.push(&buffer[..count]) {
            Ok(frames) => frames,
            Err(error) => {
                let _ = stream.write_all(&crate::protocol::protocol_error_frame(&error));
                outcome = Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    error.code(),
                ));
                break;
            }
        };
        if let Some(error) = framer.take_error() {
            for raw in frames {
                for message in engine.handle_raw(&raw) {
                    if let Err(error) = stream.write_all(&message) {
                        outcome = Err(error);
                        break 'read;
                    }
                }
            }
            let _ = stream.write_all(&crate::protocol::protocol_error_frame(&error));
            outcome = Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                error.code(),
            ));
            break;
        }
        for raw in frames {
            for message in engine.handle_raw(&raw) {
                if let Err(error) = stream.write_all(&message) {
                    outcome = Err(error);
                    break 'read;
                }
            }
        }
    }
    finish_session(engine);
    outcome
}

pub(crate) fn accept_authorized<P: PeerCheck>(
    listener: UnixListener,
    peer: &P,
) -> std::io::Result<()> {
    let (stream, _) = listener.accept()?;
    peer.allow(&stream)?;
    drop(stream);
    Ok(())
}

fn finish_session<B, C>(engine: &mut Engine<B, C>)
where
    B: ModelBackend,
    C: ChildControl,
{
    if !engine.session().is_terminal() {
        let _ = engine.close();
    }
}

#[cfg(target_os = "linux")]
fn peer_uid_fd(fd: i32) -> std::io::Result<u32> {
    #[repr(C)]
    struct Ucred {
        pid: i32,
        uid: u32,
        gid: u32,
    }
    let mut cred = Ucred {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut len = libc::socklen_t::try_from(std::mem::size_of::<Ucred>()).unwrap_or(0);
    // Safety: `cred` and `len` are valid writable objects, and SO_PEERCRED writes exactly
    // `struct ucred` on Linux when the socket is a connected unix stream.
    let rc = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&mut cred as *mut Ucred).cast(),
            &mut len,
        )
    };
    if rc != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(cred.uid)
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
fn peer_uid_fd(fd: i32) -> std::io::Result<u32> {
    let mut uid = 0u32;
    let mut gid = 0u32;
    // Safety: `uid` and `gid` are valid writable u32s. `getpeereid` writes both.
    let rc = unsafe { libc::getpeereid(fd, &mut uid, &mut gid) };
    if rc != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(uid)
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "macos",
    target_os = "ios",
    target_os = "freebsd"
)))]
fn peer_uid_fd(_fd: i32) -> std::io::Result<u32> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "peer uid",
    ))
}
