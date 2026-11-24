use haru_companion::session::{
    apply_push, SessionError, SessionEvent, SessionHost, SessionState, FRAME_SAMPLES,
};
use haru_companion::supervisor::SpyLauncher;
use haru_companion::watchdog::WatchdogReason;

fn contract(state: &SessionState, event: &SessionEvent) -> Result<SessionState, SessionError> {
    let illegal = SessionError::IllegalTransition {
        from: Box::new(state.clone()),
        event: Box::new(event.clone()),
    };
    match state {
        SessionState::Idle => match event {
            SessionEvent::Start => Ok(SessionState::Starting),
            SessionEvent::Close => Ok(SessionState::Closed),
            SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
            SessionEvent::Started | SessionEvent::Push | SessionEvent::Closed => Err(illegal),
        },
        SessionState::Starting => match event {
            SessionEvent::Started => Ok(SessionState::Streaming),
            SessionEvent::Close => Ok(SessionState::Closing),
            SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
            SessionEvent::Start | SessionEvent::Push | SessionEvent::Closed => Err(illegal),
        },
        SessionState::Streaming => match event {
            SessionEvent::Push => Ok(SessionState::Streaming),
            SessionEvent::Close => Ok(SessionState::Closing),
            SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
            SessionEvent::Start | SessionEvent::Started | SessionEvent::Closed => Err(illegal),
        },
        SessionState::Closing => match event {
            SessionEvent::Closed => Ok(SessionState::Closed),
            SessionEvent::Fail(error) => Ok(SessionState::Failed(error.clone())),
            SessionEvent::Start
            | SessionEvent::Started
            | SessionEvent::Push
            | SessionEvent::Close => Err(illegal),
        },
        SessionState::Closed => match event {
            SessionEvent::Start
            | SessionEvent::Started
            | SessionEvent::Push
            | SessionEvent::Close
            | SessionEvent::Closed => Err(illegal.clone()),
            SessionEvent::Fail(error) => {
                let _kept = error.code();
                Err(illegal)
            }
        },
        SessionState::Failed(existing) => {
            let _kept = existing.code();
            Err(illegal)
        }
    }
}

#[test]
fn every_state_and_event_has_one_outcome() {
    let states = SessionState::representatives();
    let events = SessionEvent::representatives();
    assert!(
        states.len() > 6,
        "states are generated from the enum, got {}",
        states.len()
    );
    assert!(
        events.len() > 6,
        "events are generated from the enum, got {}",
        events.len()
    );
    let mut pairs = 0usize;
    for state in &states {
        for event in &events {
            pairs += 1;
            let got = state.next(event);
            let want = contract(state, event);
            assert_eq!(got, want, "{state:?} x {event:?}");
        }
    }
    assert_eq!(pairs, states.len() * events.len());
    assert_eq!(
        SessionState::Starting.next(&SessionEvent::Close).unwrap(),
        SessionState::Closing
    );
    assert_eq!(
        SessionState::Idle.next(&SessionEvent::Close).unwrap(),
        SessionState::Closed
    );
    assert!(SessionState::Closed.next(&SessionEvent::Start).is_err());
}

#[test]
fn bad_frame_size_keeps_state() {
    let streaming = SessionState::Streaming;
    for got in [0usize, 3199, 3201] {
        let error = apply_push(&streaming, &vec![0.0; got]).unwrap_err();
        assert_eq!(
            error,
            SessionError::BadFrameSize {
                expected: FRAME_SAMPLES,
                got
            }
        );
        assert_eq!(streaming, SessionState::Streaming);
    }
    assert_eq!(
        apply_push(&streaming, &vec![0.2; FRAME_SAMPLES]).unwrap(),
        SessionState::Streaming
    );
    let idle = SessionState::Idle;
    let error = apply_push(&idle, &[0.0; 3]).unwrap_err();
    assert!(matches!(error, SessionError::IllegalTransition { .. }));
    assert_ne!(
        std::mem::discriminant(&SessionError::BadFrameSize {
            expected: FRAME_SAMPLES,
            got: 1
        }),
        std::mem::discriminant(&SessionError::IllegalTransition {
            from: Box::new(SessionState::Idle),
            event: Box::new(SessionEvent::Start),
        })
    );
    let _ = WatchdogReason::Stall;
}

#[test]
fn closed_and_failed_accept_nothing() {
    let terminal: Vec<SessionState> = SessionState::representatives()
        .into_iter()
        .filter(SessionState::is_terminal)
        .collect();
    assert!(terminal.len() > 2);
    for state in &terminal {
        for event in SessionEvent::representatives() {
            let error = state.next(&event).unwrap_err();
            match error {
                SessionError::IllegalTransition { from, event: got } => {
                    assert_eq!(*from, *state);
                    assert_eq!(*got, event);
                }
                SessionError::BadFrameSize { .. }
                | SessionError::ProcessExited { .. }
                | SessionError::SocketClosed
                | SessionError::StartTimeout
                | SessionError::WatchdogRestart { .. } => {
                    panic!("terminal event produced {error:?}")
                }
            }
        }
    }
}

#[test]
fn close_during_model_load_kills_the_child_and_never_streams() {
    let mut host = SessionHost::new(SpyLauncher::default(), vec!["fake-haru".into()]);
    host.begin_model_load().unwrap();
    assert_eq!(host.state(), &SessionState::Starting);
    let pid = host.alive()[0];
    host.close().unwrap();
    assert_eq!(
        host.trace(),
        &[
            SessionState::Starting,
            SessionState::Closing,
            SessionState::Closed
        ]
    );
    assert_eq!(host.state(), &SessionState::Closed);
    assert!(!host.alive().contains(&pid));
    assert!(host.alive().is_empty());
    assert!(!host.ever_streaming());
    let late = host.finish_model_load().unwrap_err();
    assert!(matches!(late, SessionError::IllegalTransition { .. }));
    assert_eq!(host.state(), &SessionState::Closed);
    assert!(!host.ever_streaming());
}

#[test]
fn idle_close_refuses_a_later_start() {
    let mut host = SessionHost::new(SpyLauncher::default(), vec!["fake-haru".into()]);
    host.close().unwrap();
    assert_eq!(host.state(), &SessionState::Closed);
    assert_eq!(host.spawn_count(), 0);
    let error = host.begin_model_load().unwrap_err();
    assert!(matches!(error, SessionError::IllegalTransition { .. }));
    assert_eq!(host.spawn_count(), 0);
    assert!(host.alive().is_empty());
}

#[test]
fn session_transition_match_has_no_wildcard() {
    let source = include_str!("../src/session.rs");
    assert!(
        !source.contains("_ =>"),
        "a wildcard arm would hide a new state or event"
    );
}
