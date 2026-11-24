//! The checked-in diagram is the one the state table generates.

#[test]
fn state_machine_svg_matches_the_generator() {
    let generated = haru_companion::session::state_machine_svg();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("docs/state-machine.svg");
    if std::env::var_os("HARU_WRITE_SVG").is_some() {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, &generated).unwrap();
    }
    let checked_in = std::fs::read_to_string(&path).unwrap_or_default();
    assert_eq!(checked_in, generated);
    assert!(generated.contains("idle"));
    assert!(generated.contains("animateMotion"));
    assert!(generated.contains("streaming"));
}
