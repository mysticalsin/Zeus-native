//! The v1 JSON decoder must round-trip real text and reject ambiguous input.

use haru_companion::protocol::{
    decode_client, decode_server, frame, ClientMessage, ProtocolError, ServerMessage, CLOSE, HELLO,
};

#[test]
fn french_prompt_round_trips() {
    let msg = ClientMessage::Start {
        language: "fr".into(),
        system_prompt: "café — «bonjour»\nligne".into(),
        speak_first: true,
    };
    let decoded = decode_client(&msg.encode().unwrap()).unwrap();
    assert_eq!(decoded, msg);
}

#[test]
fn fractional_version_is_not_an_integer() {
    let framed = frame(HELLO, br#"{"v":1.5}"#);
    assert_eq!(decode_client(&framed).unwrap_err(), ProtocolError::BadJson);
}

#[test]
fn deeply_nested_object_is_rejected() {
    let mut payload = String::from("{\"v\":1");
    for _ in 0..40 {
        payload.push_str(",\"p\":{\"x\":1");
    }
    for _ in 0..41 {
        payload.push('}');
    }
    let framed = frame(HELLO, payload.as_bytes());
    assert_eq!(decode_client(&framed).unwrap_err(), ProtocolError::BadJson);
}

#[test]
fn server_decoder_rejects_a_second_frame() {
    let one = ServerMessage::hello_ack().encode();
    let mut two = one.clone();
    two.extend_from_slice(&one);
    assert!(
        decode_server(&two).is_err(),
        "a second frame must not be silently dropped"
    );
    let mut junk = one;
    junk.push(0);
    assert!(decode_server(&junk).is_err());
}

#[test]
fn close_with_a_payload_is_rejected() {
    assert_eq!(
        decode_client(&frame(CLOSE, b"nope")).unwrap_err(),
        ProtocolError::BadJson
    );
}

#[test]
fn raw_control_character_in_a_string_is_rejected() {
    let framed = frame(
        0x22,
        b"{\"language\":\"en\",\"system_prompt\":\"a\nb\",\"speak_first\":false}",
    );
    assert_eq!(decode_client(&framed).unwrap_err(), ProtocolError::BadJson);
}
