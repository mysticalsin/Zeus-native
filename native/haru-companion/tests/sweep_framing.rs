//! The frame buffer must survive a bad length and a split read.

use haru_companion::protocol::{self, ClientMessage, FrameBuf, ProtocolError, HELLO};

fn hello() -> Vec<u8> {
    ClientMessage::Hello { v: 1 }.encode().unwrap()
}

#[test]
fn oversized_frame_does_not_stick_or_drop_the_previous_frame() {
    let mut header = vec![0x99u8];
    header.extend_from_slice(&(8 * 1024 * 1024 + 1u32).to_le_bytes());

    let mut stuck = FrameBuf::default();
    assert_eq!(
        stuck.push(&header).unwrap_err(),
        ProtocolError::Oversized
    );
    let recovered = stuck
        .push(&hello())
        .expect("framer must accept a new frame after an oversized one");
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].kind, HELLO);

    let mut both = FrameBuf::default();
    let mut bytes = hello();
    bytes.extend_from_slice(&header);
    let frames = both
        .push(&bytes)
        .expect("a valid frame before an oversized one must be delivered");
    assert_eq!(frames.len(), 1);
    assert_eq!(frames[0].kind, HELLO);
    assert_eq!(
        protocol::decode_client_frame(&frames[0]).unwrap(),
        ClientMessage::Hello { v: 1 }
    );
}

#[test]
fn partial_reads_assemble_one_frame() {
    let bytes = hello();
    let mut buf = FrameBuf::default();
    assert!(buf.push(&bytes[..1]).unwrap().is_empty());
    assert!(buf.push(&bytes[1..4]).unwrap().is_empty());
    let frames = buf.push(&bytes[4..]).unwrap();
    assert_eq!(frames.len(), 1);
    assert_eq!(
        protocol::decode_client_frame(&frames[0]).unwrap(),
        ClientMessage::Hello { v: 1 }
    );
}
