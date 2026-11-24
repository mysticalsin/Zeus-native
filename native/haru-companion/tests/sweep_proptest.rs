//! Property tests for the v1 decoder. Random bytes must not panic, and any
//! Unicode prompt the encoder accepts must decode back to the same value.

use haru_companion::protocol::{decode_client, ClientMessage, FrameBuf};
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn random_bytes_do_not_panic(bytes in proptest::collection::vec(any::<u8>(), 0..1024)) {
        let _ = decode_client(&bytes);
        let mut buf = FrameBuf::default();
        let _ = buf.push(&bytes);
    }

    #[test]
    fn unicode_prompts_round_trip(prompt in "\\PC{0,32}") {
        let msg = ClientMessage::Start {
            language: "fr".into(),
            system_prompt: prompt,
            speak_first: false,
        };
        let encoded = msg.encode().unwrap();
        prop_assert_eq!(decode_client(&encoded).unwrap(), msg);
    }
}
