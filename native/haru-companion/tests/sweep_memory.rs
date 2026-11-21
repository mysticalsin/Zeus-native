//! Untrusted lengths must not allocate the declared payload.

use haru_companion::backend::{BackendEvent, ModelBackend, UpstreamBackend};
use haru_companion::session::FRAME_SAMPLES;
use haru_companion::upstream::StartRequest;
use std::cell::Cell;
use std::io::{self, Read, Write};
use std::rc::Rc;

struct Flood {
    reads: Rc<Cell<u32>>,
    sent_header: bool,
}

impl Read for Flood {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.reads.get().saturating_add(1);
        self.reads.set(n);
        if n > 4 {
            return Err(io::Error::other("oversized frame kept the socket busy"));
        }
        if !self.sent_header {
            self.sent_header = true;
            buf[0] = 0x11;
            buf[1..5].copy_from_slice(&(9 * 1024 * 1024u32).to_le_bytes());
            return Ok(5);
        }
        buf.fill(0);
        Ok(buf.len().min(4096))
    }
}

impl Write for Flood {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        Ok(data.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[test]
fn upstream_frame_over_8_mib_is_rejected_without_buffering_it() {
    let reads = Rc::new(Cell::new(0));
    let mut backend = UpstreamBackend::new(
        Flood {
            reads: Rc::clone(&reads),
            sent_header: false,
        },
        StartRequest {
            language: "en".into(),
            system_prompt: String::new(),
            speak_first: false,
        },
    );
    let event = backend.exchange(&vec![0.0; FRAME_SAMPLES]);
    assert!(
        matches!(
            event,
            BackendEvent::Exited { .. } | BackendEvent::SocketClosed
        ),
        "got {event:?}"
    );
    assert!(
        reads.get() <= 2,
        "reader was pulled {} times for a 9 MiB declaration",
        reads.get()
    );
}
