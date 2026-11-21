//! Unix socket for one local client. Mode 0600, peer uid checked, no TCP.

use crate::backend::ModelBackend;
use crate::engine::Engine;
use crate::protocol::FrameBuf;
use crate::session::ChildControl;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::time::Duration;

pub fn bind_socket(path: &Path) -> std::io::Result<UnixListener>  {
    todo!("red");
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
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "peer uid",
        ));
    }
    let mut stream = stream;
    let mut framer = FrameBuf::default();
    let mut buffer = [0u8; 8192];
    loop {
        let read = stream.read(&mut buffer);
        let count = match read {
            Ok(0) => break,
            Ok(count) => count,
            Err(error)
                if error.kind() == std::io::ErrorKind::WouldBlock
                    || error.kind() == std::io::ErrorKind::TimedOut =>
            {
                break
            }
            Err(error) => return Err(error),
        };
        let frames = framer
            .push(&buffer[..count])
            .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error.code()))?;
        for raw in frames {
            for message in engine.handle_raw(&raw) {
                stream.write_all(&message)?;
            }
        }
    }
    Ok(())
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

const SOL_SOCKET: i32 = 1;
#[cfg(target_os = "linux")]
const SO_PEERCRED: i32 = 17;

extern "C" {
    fn geteuid() -> u32;
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
