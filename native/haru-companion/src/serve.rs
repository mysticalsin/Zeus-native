//! Unix socket for one local client. Mode 0600, peer uid checked, no TCP.

use crate::backend::ModelBackend;
use crate::engine::Engine;
use crate::protocol::FrameBuf;
use crate::session::ChildControl;
use std::io::{Read, Write};
use std::os::unix::fs::FileTypeExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::Mutex;
use std::time::Duration;

static BIND_UMASK: Mutex<()> = Mutex::new(());

pub fn bind_socket(path: &Path) -> std::io::Result<UnixListener> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    if let Ok(meta) = std::fs::symlink_metadata(path) {
        let kind = meta.file_type();
        if kind.is_socket() {
            match UnixStream::connect(path) {
                Ok(live) => {
                    drop(live);
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::AddrInUse,
                        "socket is live",
                    ));
                }
                Err(error) if error.kind() == std::io::ErrorKind::ConnectionRefused => {
                    std::fs::remove_file(path)?;
                }
                Err(error) => return Err(error),
            }
        } else if kind.is_symlink() {
            std::fs::remove_file(path)?;
        } else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::AlreadyExists,
                "refusing to replace a non-socket",
            ));
        }
    }
    let listener = {
        let _guard = BIND_UMASK
            .lock()
            .unwrap_or_else(|poison| poison.into_inner());
        // 0777 & ~0177 = 0600, so the directory entry is created private
        // and a later chmod of the path cannot follow a swapped symlink.
        let old = unsafe { umask(0o177) };
        let bound = UnixListener::bind(path);
        unsafe { umask(old) };
        bound?
    };
    if unsafe { fchmod(listener.as_raw_fd(), 0o600) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(listener)
}

pub fn current_uid() -> u32 {
    unsafe { geteuid() }
}

pub fn peer_uid(stream: &UnixStream) -> std::io::Result<u32> {
    peer_uid_fd(stream.as_raw_fd())
}

pub fn serve_one<B, C>(listener: UnixListener, engine: &mut Engine<B, C>) -> std::io::Result<()>
where
    B: ModelBackend,
    C: ChildControl,
{
    let (stream, _) = listener.accept()?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    let peer = peer_uid(&stream)?;
    if peer != current_uid() {
        finish_session(engine);
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "peer uid",
        ));
    }
    let mut stream = stream;
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
    let mut len = u32::try_from(std::mem::size_of::<Ucred>()).unwrap_or(0);
    // Safety: `cred` and `len` are valid writable objects, and SO_PEERCRED writes exactly
    // `struct ucred` on Linux when the socket is a connected unix stream.
    let rc = unsafe {
        getsockopt(
            fd,
            SOL_SOCKET,
            SO_PEERCRED,
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
    let rc = unsafe { getpeereid(fd, &mut uid, &mut gid) };
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

#[cfg(target_os = "linux")]
const SOL_SOCKET: i32 = 1;
#[cfg(target_os = "linux")]
const SO_PEERCRED: i32 = 17;

extern "C" {
    fn geteuid() -> u32;
    fn umask(mask: u32) -> u32;
    fn fchmod(fd: i32, mode: u32) -> i32;
    #[cfg(target_os = "linux")]
    fn getsockopt(
        sockfd: i32,
        level: i32,
        optname: i32,
        optval: *mut core::ffi::c_void,
        optlen: *mut u32,
    ) -> i32;
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
    fn getpeereid(fd: i32, uid: *mut u32, gid: *mut u32) -> i32;
}
