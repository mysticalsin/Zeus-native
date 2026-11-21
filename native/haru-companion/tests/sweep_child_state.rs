//! An illegal child event must not be rewritten into a restart.

use haru_companion::supervisor::{ChildState, Supervisor, SpyLauncher};

#[test]
fn a_stopped_supervisor_stays_stopped_after_the_budget_window() {
    let mut supervisor = Supervisor::new(SpyLauncher::default(), vec!["python3".into()]);
    supervisor.start().unwrap();
    for _ in 0..4 {
        supervisor.on_exit(1);
    }
    assert_eq!(supervisor.state(), &ChildState::Stopped { failed: true });
    supervisor.advance(10 * 60 * 1000);
    let spawns = supervisor.spawn_count();
    supervisor.on_exit(1);
    assert_eq!(
        supervisor.state(),
        &ChildState::Stopped { failed: true },
        "an exit after the window resurrected a stopped supervisor"
    );
    assert_eq!(supervisor.spawn_count(), spawns);
    assert!(supervisor.alive().is_empty());
}

#[test]
fn exit_before_launch_does_not_spawn() {
    let mut supervisor = Supervisor::new(SpyLauncher::default(), vec!["python3".into()]);
    supervisor.on_exit(1);
    assert_eq!(supervisor.spawn_count(), 0);
    assert!(supervisor.alive().is_empty());
    assert_eq!(supervisor.state(), &ChildState::NotStarted);
}
