use haru_companion::protocol::{decode_client, decode_server, ClientMessage, ServerMessage};
use haru_companion::session::FRAME_SAMPLES;

fn tone() -> Vec<f32> {
    (0..FRAME_SAMPLES)
        .map(|index| index as f32 * 0.0001 - 0.16)
        .collect()
}

#[test]
fn push_round_trips_3200_samples() {
    let samples = tone();
    let bytes = ClientMessage::Push {
        seq: 7,
        samples: samples.clone(),
    }
    .encode()
    .unwrap();
    match decode_client(&bytes).unwrap() {
        ClientMessage::Push { seq, samples: got } => {
            assert_eq!(seq, 7);
            assert_eq!(got, samples);
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn push_with_3199_or_3201_samples_is_rejected() {
    for count in [3199usize, 3201] {
        let error = ClientMessage::Push {
            seq: 1,
            samples: vec![0.0; count],
        }
        .encode()
        .unwrap_err();
        assert_eq!(
            error,
            haru_companion::protocol::ProtocolError::BadFrameSize {
                expected: FRAME_SAMPLES,
                got: count
            }
        );
        let mut payload = Vec::new();
        payload.extend_from_slice(&1u32.to_le_bytes());
        payload.extend(std::iter::repeat(0u8).take(count * 4));
        let framed = haru_companion::protocol::frame(0x23, &payload);
        let decoded = decode_client(&framed).unwrap_err();
        assert_eq!(
            decoded,
            haru_companion::protocol::ProtocolError::BadFrameSize {
                expected: FRAME_SAMPLES,
                got: count
            }
        );
    }
}

#[test]
fn start_with_reference_path_is_rejected() {
    let payload = br#"{"language":"en","system_prompt":"hi","speak_first":false,"reference_path":"/tmp/voice.wav"}"#;
    let framed = haru_companion::protocol::frame(0x22, payload);
    let error = decode_client(&framed).unwrap_err();
    assert_eq!(
        error,
        haru_companion::protocol::ProtocolError::ReferenceNotAllowed
    );
}

#[test]
fn hello_ack_reports_24k_and_3200() {
    let bytes = ServerMessage::hello_ack().encode();
    match decode_server(&bytes).unwrap() {
        ServerMessage::HelloAck {
            v,
            sample_rate,
            frame_samples,
        } => assert_eq!((v, sample_rate, frame_samples), (1, 24_000, 3200)),
        other => panic!("{other:?}"),
    }
}
