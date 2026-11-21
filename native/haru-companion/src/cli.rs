//! `haru-companion serve ...` and `haru-companion selftest`.
//! Missing python, model, or the conversation flag never spawns or binds.

use crate::backend::FakeBackend;
use crate::engine::{selftest_report, Engine};
use crate::serve::{accept_authorized, bind_socket, serve_one, unlink_if_ours, BoundWatch, OsPeer};
use crate::session::ChildControl;
use crate::supervisor::{
    apply, decide, serve_child_argv, LaunchDecision, LaunchRequest, NetGate, SocketBind, SpyBinder,
    SpyLauncher, SpyNet, StdLauncher,
};
use std::path::PathBuf;

pub fn run(args: impl IntoIterator<Item = String>) -> i32 {
    let args: Vec<String> = args.into_iter().collect();
    match parse(&args) {
        Ok(Command::SelfTest { frames }) => {
            println!("{}", selftest_report(frames).to_json());
            0
        }
        Ok(Command::Serve(config)) => serve_command(&config),
        Err(message) => {
            eprintln!("{message}");
            refuse_quietly();
            2
        }
    }
}

fn refuse_quietly() {
    let mut processes = SpyLauncher::default();
    let mut sockets = SpyBinder::default();
    let mut net = SpyNet::default();
    let decision = decide(&LaunchRequest::default());
    let _ = apply(&decision, &mut processes, &mut sockets, &mut net);
    debug_assert_eq!(processes.spawn_count(), 0);
    debug_assert_eq!(sockets.binds(), 0);
    debug_assert_eq!(net.attempts(), 0);
}

fn serve_command(config: &ServeConfig) -> i32 {
    match decide(&config.request()) {
        LaunchDecision::NoLaunch { reason } => {
            eprintln!("haru-companion: refused to start ({reason})");
            2
        }
        LaunchDecision::Launch {
            python,
            model,
            socket,
            private_socket,
            quantize,
        } => {
            eprintln!(
                "haru-companion: watchdog={} kv_window={:?} reanchor_minutes={:?} (held, not passed to haru-speech-mlx 0.1.0)",
                config.watchdog, config.kv_window, config.reanchor_minutes
            );
            let argv = serve_child_argv(&python, &model, &private_socket, quantize);
            match run_serve(&socket, &private_socket, &argv, config.watchdog) {
                Ok(()) => 0,
                Err(error) => {
                    eprintln!("haru-companion: {error}");
                    1
                }
            }
        }
    }
}

fn run_serve(
    socket: &std::path::Path,
    private_socket: &std::path::Path,
    argv: &[String],
    watchdog: bool,
) -> std::io::Result<()> {
    let listener = bind_socket(socket)?;
    let public_watch = match BoundWatch::watch(&listener, socket) {
        Ok(watch) => watch,
        Err(error) => {
            drop(listener);
            let _ = std::fs::remove_file(socket);
            return Err(error);
        }
    };
    let child_listener = match bind_socket(private_socket) {
        Ok(listener) => listener,
        Err(error) => {
            drop(listener);
            let _ = unlink_if_ours(socket, public_watch.dev, public_watch.ino);
            return Err(error);
        }
    };
    let child_watch = match BoundWatch::watch(&child_listener, private_socket) {
        Ok(watch) => watch,
        Err(error) => {
            drop(listener);
            drop(child_listener);
            let _ = unlink_if_ours(socket, public_watch.dev, public_watch.ino);
            let _ = std::fs::remove_file(private_socket);
            return Err(error);
        }
    };
    let mut probe = StdLauncher::new();
    if let Err(error) = probe.spawn(argv) {
        drop(listener);
        drop(child_listener);
        let _ = unlink_if_ours(socket, public_watch.dev, public_watch.ino);
        let _ = unlink_if_ours(private_socket, child_watch.dev, child_watch.ino);
        return Err(error);
    }
    // The probe proves the interpreter can be spawned. Dropping it kills that
    // process (`StdLauncher::drop`). The engine owns a later child. `serve`
    // still answers Zeus from `FakeBackend::quiet`, so frames are silence
    // rather than model audio. That scaffold is unchanged in this socket fix.
    drop(probe);
    let child_gate = std::thread::spawn(move || {
        let _ = accept_authorized(child_listener, &OsPeer);
    });
    let mut engine = Engine::new(
        FakeBackend::quiet(),
        StdLauncher::new(),
        argv.to_vec(),
        watchdog,
    );
    let served = serve_one(listener, &mut engine);
    let child_same = child_watch.still_ours(private_socket);
    child_watch.wake(private_socket);
    let _ = child_gate.join();
    let _ = unlink_if_ours(socket, public_watch.dev, public_watch.ino);
    let _ = unlink_if_ours(private_socket, child_watch.dev, child_watch.ino);
    if !child_same {
        return Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "child socket replaced",
        ));
    }
    served
}

enum Command {
    Serve(ServeConfig),
    SelfTest { frames: usize },
}

struct ServeConfig {
    socket: Option<PathBuf>,
    python: Option<PathBuf>,
    model: Option<PathBuf>,
    quantize: u8,
    kv_window: Option<u32>,
    reanchor_minutes: Option<u32>,
    watchdog: bool,
}

impl ServeConfig {
    fn request(&self) -> LaunchRequest {
        LaunchRequest {
            conversation_mode: true,
            python: self.python.clone(),
            model: self.model.clone(),
            socket: self.socket.clone(),
            quantize: self.quantize,
        }
    }
}

fn parse(args: &[String]) -> Result<Command, String> {
    match args.first().map(String::as_str) {
        Some("selftest") => {
            let mut frames = 10_000usize;
            let mut index = 1;
            while index < args.len() {
                if args[index] == "--frames" {
                    let value = args
                        .get(index + 1)
                        .ok_or_else(|| usage("missing --frames"))?;
                    frames = value.parse().map_err(|_| usage("bad --frames"))?;
                    if frames > 20_000 {
                        return Err(usage("--frames is capped at 20000"));
                    }
                    index += 2;
                } else {
                    return Err(usage(&format!("unknown {}", args[index])));
                }
            }
            Ok(Command::SelfTest { frames })
        }
        Some("serve") => {
            let mut config = ServeConfig {
                socket: None,
                python: None,
                model: None,
                quantize: 8,
                kv_window: None,
                reanchor_minutes: None,
                watchdog: false,
            };
            let mut index = 1;
            while index < args.len() {
                let flag = args[index].as_str();
                if flag == "--watchdog" {
                    config.watchdog = true;
                    index += 1;
                    continue;
                }
                let value = args
                    .get(index + 1)
                    .cloned()
                    .ok_or_else(|| usage(&format!("missing value for {flag}")))?;
                match flag {
                    "--socket" => config.socket = Some(PathBuf::from(value)),
                    "--python" => config.python = Some(PathBuf::from(value)),
                    "--model" => config.model = Some(PathBuf::from(value)),
                    "--quantize" => {
                        config.quantize = value.parse().map_err(|_| usage("bad --quantize"))?;
                    }
                    "--kv-window" => {
                        config.kv_window =
                            Some(value.parse().map_err(|_| usage("bad --kv-window"))?);
                    }
                    "--reanchor-minutes" => {
                        config.reanchor_minutes =
                            Some(value.parse().map_err(|_| usage("bad --reanchor-minutes"))?);
                    }
                    other => return Err(usage(&format!("unknown {other}"))),
                }
                index += 2;
            }
            Ok(Command::Serve(config))
        }
        Some(other) => Err(usage(&format!("unknown command {other}"))),
        None => Err(usage("no command")),
    }
}

fn usage(detail: &str) -> String {
    format!(
        "haru-companion: {detail}\nusage: haru-companion serve --socket PATH --python PATH --model DIR [--quantize 8] [--watchdog] [--kv-window N] [--reanchor-minutes M]\n       haru-companion selftest [--frames N]"
    )
}

#[cfg(test)]
mod flag_tests {
    use super::{parse, Command};

    #[test]
    fn watchdog_flag_is_recorded() {
        let command = parse(&[
            "serve".into(),
            "--socket".into(),
            "s".into(),
            "--watchdog".into(),
        ])
        .unwrap();
        match command {
            Command::Serve(config) => assert!(config.watchdog),
            Command::SelfTest { .. } => panic!("expected serve"),
        }
    }
}
