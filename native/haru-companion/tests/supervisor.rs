use haru_companion::session::ChildControl;
use haru_companion::supervisor::{
    apply, child_argv, decide, ChildState, LaunchDecision, LaunchRequest, NetGate, NoLaunchReason,
    SocketBind, SpyBinder, SpyLauncher, SpyNet, Supervisor,
};
use std::path::PathBuf;

fn effects() -> (SpyLauncher, SpyBinder, SpyNet) {
    (
        SpyLauncher::default(),
        SpyBinder::default(),
        SpyNet::default(),
    )
}

fn touch(effects: &mut (SpyLauncher, SpyBinder, SpyNet), decision: &LaunchDecision) {
    let _ = apply(decision, &mut effects.0, &mut effects.1, &mut effects.2);
}

#[test]
fn no_python_or_model_means_no_spawn() {
    let mut world = effects();
    let missing_python = LaunchRequest {
        conversation_mode: true,
        python: None,
        model: Some(PathBuf::from("/model")),
        socket: Some(PathBuf::from("/tmp/zeus.sock")),
        quantize: 8,
    };
    let decision = decide(&missing_python);
    assert_eq!(
        decision,
        LaunchDecision::NoLaunch {
            reason: NoLaunchReason::MissingPython
        }
    );
    touch(&mut world, &decision);
    let missing_model = LaunchRequest {
        conversation_mode: true,
        python: Some(PathBuf::from("python3")),
        model: None,
        socket: Some(PathBuf::from("/tmp/zeus.sock")),
        quantize: 8,
    };
    let decision = decide(&missing_model);
    assert_eq!(
        decision,
        LaunchDecision::NoLaunch {
            reason: NoLaunchReason::MissingModel
        }
    );
    touch(&mut world, &decision);
    assert_eq!(world.0.spawn_count(), 0);
    assert_eq!(world.1.binds(), 0);
    assert_eq!(world.2.attempts(), 0);
}

#[test]
fn flags_off_spawns_nothing_binds_nothing_and_uses_no_network() {
    let mut world = effects();
    let request = LaunchRequest {
        conversation_mode: false,
        python: Some(PathBuf::from("python3")),
        model: Some(PathBuf::from("/model")),
        socket: Some(PathBuf::from("/tmp/zeus-haru.sock")),
        quantize: 8,
    };
    let decision = decide(&request);
    assert_eq!(
        decision,
        LaunchDecision::NoLaunch {
            reason: NoLaunchReason::FlagOff
        }
    );
    touch(&mut world, &decision);
    let quiet = decide(&LaunchRequest::default());
    touch(&mut world, &quiet);
    assert_eq!(world.0.spawn_count(), 0);
    assert_eq!(world.1.binds(), 0);
    assert_eq!(world.2.attempts(), 0);
    let manifest = include_str!("../Cargo.toml");
    assert!(manifest.contains("haru-pipe"));
    for banned in ["reqwest", "hyper", "tokio", "ureq", "tungstenite"] {
        assert!(!manifest.contains(banned), "{banned}");
    }
}

#[test]
fn an_explicit_request_binds_and_spawns_without_a_reference() {
    let mut world = effects();
    let model = std::env::temp_dir().join(format!("zeus-haru-model-{}", std::process::id()));
    std::fs::create_dir_all(&model).unwrap();
    let request = LaunchRequest {
        conversation_mode: true,
        python: Some(PathBuf::from("python3")),
        model: Some(model.clone()),
        socket: Some(PathBuf::from("/tmp/zeus-haru.sock")),
        quantize: 8,
    };
    let decision = decide(&request);
    let pid = apply(&decision, &mut world.0, &mut world.1, &mut world.2).unwrap();
    assert!(pid > 0);
    assert_eq!(world.0.spawn_count(), 1);
    assert_eq!(world.1.binds(), 1);
    assert_eq!(world.2.attempts(), 0);
    let command = world.0.commands[0].join(" ");
    assert!(command.contains("haru_mlx.native"));
    assert!(command.contains("--quantize 8"));
    assert!(!command.contains("reference"));
    let argv = child_argv(
        std::path::Path::new("python3"),
        std::path::Path::new("/model"),
        std::path::Path::new("/tmp/child.sock"),
        8,
    );
    assert!(!argv.iter().any(|part| part.contains("reference")));
    let _ = std::fs::remove_dir_all(&model);
}

#[test]
fn crash_restarts_within_budget_then_stops() {
    let mut supervisor =
        Supervisor::new(SpyLauncher::default(), vec!["python3".into(), "-m".into()]);
    supervisor.start().unwrap();
    assert_eq!(supervisor.state(), &ChildState::Ready);
    assert_eq!(supervisor.spawn_count(), 1);
    for _ in 0..3 {
        supervisor.on_exit(1);
        assert_eq!(supervisor.state(), &ChildState::Ready);
        assert_eq!(supervisor.alive().len(), 1);
    }
    assert_eq!(supervisor.spawn_count(), 4);
    supervisor.on_exit(1);
    assert_eq!(supervisor.state(), &ChildState::Stopped { failed: true });
    assert!(supervisor.alive().is_empty());
    assert_eq!(supervisor.spawn_count(), 4);
}

#[test]
fn restart_leaves_no_orphan_child() {
    let mut supervisor = Supervisor::new(SpyLauncher::default(), vec!["python3".into()]);
    supervisor.start().unwrap();
    let first = supervisor.alive()[0];
    supervisor.on_exit(9);
    assert!(!supervisor.alive().contains(&first));
    assert_eq!(supervisor.alive().len(), 1);
}

#[test]
fn synthetic_advance_does_not_refresh_the_restart_budget() {
    let mut supervisor = Supervisor::new(SpyLauncher::default(), vec!["python3".into()]);
    supervisor.start().unwrap();
    supervisor.on_exit(1);
    supervisor.on_exit(1);
    supervisor.on_exit(1);
    supervisor.advance(10 * 60 * 1000);
    supervisor.on_exit(1);
    assert_eq!(supervisor.state(), &ChildState::Stopped { failed: true });
    assert!(supervisor.alive().is_empty());
}
