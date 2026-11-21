use haru_companion::upstream::{
    downsample_48k, model_frame_from_upstream, upsample_24k, UpstreamMessage,
};

fn load(name: &str) -> Vec<f32> {
    let bytes = std::fs::read(format!("tests/fixtures/{name}")).unwrap();
    bytes
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect()
}

#[test]
fn upstream_48k_round_trip_matches_native_py_fixture() {
    let input = load("in_48k.f32");
    let expect_down = load("down_24k.f32");
    let expect_up = load("up_48k.f32");
    let down = downsample_48k(&input);
    assert_eq!(down, expect_down);
    let up = upsample_24k(&down);
    assert_eq!(up, expect_up);
    assert_eq!(down.len(), 6_400);
    // upsample_2x is linear interpolation, so downsampling the playback is not
    // an identity. The fixture is the native.py pair: 48 kHz -> 24 kHz and back.
    let message = UpstreamMessage::Frame {
        index: 1,
        step_ms: 0.0,
        pcm48: expect_up.clone(),
    };
    assert_eq!(
        model_frame_from_upstream(&message).unwrap(),
        downsample_48k(&expect_up)
    );
    let start = haru_companion::upstream::encode_start(&haru_companion::upstream::StartRequest {
        language: "en".into(),
        system_prompt: "haru".into(),
        speak_first: false,
    });
    let text = String::from_utf8(start).unwrap();
    assert!(!text.contains("reference"));
}
