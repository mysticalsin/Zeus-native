//! selftest must not accept an unbounded frame count.

#[test]
fn selftest_rejects_a_frame_count_past_20000() {
    let code = haru_companion::run(["selftest".into(), "--frames".into(), "20001".into()]);
    assert_eq!(code, 2);
}
