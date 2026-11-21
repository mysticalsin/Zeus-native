//! Child process supervisor. Nothing is spawned unless [`decide`] returns [`LaunchDecision::Launch`].

use crate::session::ChildControl;
use std::collections::BTreeSet;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Child;

pub const RESTART_LIMIT: u32 = 3;
pub const RESTART_WINDOW_MS: u64 = 10 * 60 * 1000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NoLaunchReason {
    FlagOff,
    NotRequested,
    MissingPython,
    MissingModel,
}

impl std::fmt::Display for NoLaunchReason {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = match self {
            NoLaunchReason::FlagOff => "conversation flag is off",
            NoLaunchReason::NotRequested => "no serve request",
            NoLaunchReason::MissingPython => "python path is missing",
            NoLaunchReason::MissingModel => "model directory is missing",
        };
        formatter.write_str(text)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LaunchRequest {
    pub conversation_mode: bool,
    pub python: Option<PathBuf>,
    pub model: Option<PathBuf>,
    pub socket: Option<PathBuf>,
    pub quantize: u8,
}

impl Default for LaunchRequest {
    fn default() -> Self {
        Self {
            conversation_mode: false,
            python: None,
            model: None,
            socket: None,
            quantize: 8,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LaunchDecision {
    NoLaunch {
        reason: NoLaunchReason,
    },
    Launch {
        python: PathBuf,
        model: PathBuf,
        socket: PathBuf,
        private_socket: PathBuf,
        quantize: u8,
    },
}

pub fn decide(request: &LaunchRequest) -> LaunchDecision {
    if !request.conversation_mode {
        return LaunchDecision::NoLaunch {
            reason: NoLaunchReason::FlagOff,
        };
    }
    let Some(python) = present(&request.python) else {
        return LaunchDecision::NoLaunch {
            reason: NoLaunchReason::MissingPython,
        };
    };
    let Some(model) = present(&request.model) else {
        return LaunchDecision::NoLaunch {
            reason: NoLaunchReason::MissingModel,
        };
    };
    let Some(socket) = present(&request.socket) else {
        return LaunchDecision::NoLaunch {
            reason: NoLaunchReason::NotRequested,
        };
    };
    LaunchDecision::Launch {
        python,
        model,
        private_socket: private_socket(&socket),
        socket,
        quantize: request.quantize,
    }
}

fn present(path: &Option<PathBuf>) -> Option<PathBuf> {
    path.as_ref().and_then(|value| {
        if value.as_os_str().is_empty() {
            None
        } else {
            Some(value.clone())
        }
    })
}

pub fn private_socket(public: &Path) -> PathBuf {
    let mut name = public.file_name().unwrap_or_default().to_os_string();
    name.push(".child");
    public.with_file_name(name)
}

pub fn child_argv(python: &Path, model: &Path, socket: &Path, quantize: u8) -> Vec<String> {
    vec![
        python.display().to_string(),
        "-m".to_string(),
        "haru_mlx.native".to_string(),
        "--socket".to_string(),
        socket.display().to_string(),
        "--model".to_string(),
        model.display().to_string(),
        "--quantize".to_string(),
        quantize.to_string(),
    ]
}

pub trait SocketBind {
    fn bind_unix(&mut self, path: &Path) -> std::io::Result<()>;
    fn binds(&self) -> u32;
}

pub trait NetGate {
    fn connect(&mut self, host: &str) -> std::io::Result<()>;
    fn attempts(&self) -> u32;
}

/// Apply a decision. `NoLaunch` does not spawn, bind, or open a network connection.
pub fn apply<C, B, N>(
    decision: &LaunchDecision,
    processes: &mut C,
    sockets: &mut B,
    net: &mut N,
) -> Result<u32, NoLaunchReason>
where
    C: ChildControl,
    B: SocketBind,
    N: NetGate,
{
    let _observed = net.attempts();
    match decision {
        LaunchDecision::NoLaunch { reason } => Err(reason.clone()),
        LaunchDecision::Launch {
            python,
            model,
            socket,
            private_socket,
            quantize,
        } => {
            sockets
                .bind_unix(socket)
                .map_err(|_| NoLaunchReason::NotRequested)?;
            let argv = child_argv(python, model, private_socket, *quantize);
            processes
                .spawn(&argv)
                .map_err(|_| NoLaunchReason::NotRequested)
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChildState {
    NotStarted,
    Spawning,
    Loading,
    Ready,
    Unhealthy,
    Restarting,
    Stopped { failed: bool },
}

impl ChildState {
    pub fn wire_name(&self) -> &'static str {
        match self {
            ChildState::NotStarted => "not_started",
            ChildState::Spawning => "spawning",
            ChildState::Loading => "loading",
            ChildState::Ready => "ready",
            ChildState::Unhealthy => "unhealthy",
            ChildState::Restarting => "restarting",
            ChildState::Stopped { failed: true } => "stopped_failed",
            ChildState::Stopped { failed: false } => "stopped",
        }
    }

    pub fn step(&self, event: &ChildEvent) -> Result<ChildState, ChildState> {
        match self {
            ChildState::NotStarted => match event {
                ChildEvent::Launch => Ok(ChildState::Spawning),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Spawned
                | ChildEvent::Loaded
                | ChildEvent::HealthFail
                | ChildEvent::Exited { .. }
                | ChildEvent::Restart => Err(self.clone()),
            },
            ChildState::Spawning => match event {
                ChildEvent::Spawned => Ok(ChildState::Loading),
                ChildEvent::Exited { .. } => Ok(ChildState::Unhealthy),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch
                | ChildEvent::Loaded
                | ChildEvent::HealthFail
                | ChildEvent::Restart => Err(self.clone()),
            },
            ChildState::Loading => match event {
                ChildEvent::Loaded => Ok(ChildState::Ready),
                ChildEvent::Exited { .. } => Ok(ChildState::Unhealthy),
                ChildEvent::HealthFail => Ok(ChildState::Unhealthy),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch | ChildEvent::Spawned | ChildEvent::Restart => Err(self.clone()),
            },
            ChildState::Ready => match event {
                ChildEvent::HealthFail | ChildEvent::Exited { .. } => Ok(ChildState::Unhealthy),
                ChildEvent::Restart => Ok(ChildState::Restarting),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch | ChildEvent::Spawned | ChildEvent::Loaded => Err(self.clone()),
            },
            ChildState::Unhealthy => match event {
                ChildEvent::Restart => Ok(ChildState::Restarting),
                ChildEvent::Exited { .. } => Ok(ChildState::Unhealthy),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch
                | ChildEvent::Spawned
                | ChildEvent::Loaded
                | ChildEvent::HealthFail => Err(self.clone()),
            },
            ChildState::Restarting => match event {
                ChildEvent::Spawned => Ok(ChildState::Loading),
                ChildEvent::Exited { .. } => Ok(ChildState::Unhealthy),
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: false }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch
                | ChildEvent::Loaded
                | ChildEvent::HealthFail
                | ChildEvent::Restart => Err(self.clone()),
            },
            ChildState::Stopped { failed } => match event {
                ChildEvent::Stop => Ok(ChildState::Stopped { failed: *failed }),
                ChildEvent::BudgetExhausted => Ok(ChildState::Stopped { failed: true }),
                ChildEvent::Launch
                | ChildEvent::Spawned
                | ChildEvent::Loaded
                | ChildEvent::HealthFail
                | ChildEvent::Exited { .. }
                | ChildEvent::Restart => Err(self.clone()),
            },
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChildEvent {
    Launch,
    Spawned,
    Loaded,
    HealthFail,
    Exited { code: i32 },
    Restart,
    Stop,
    BudgetExhausted,
}

#[derive(Debug)]
pub struct RestartBudget {
    max: u32,
    window_ms: u64,
    stamps: Vec<u64>,
}

impl RestartBudget {
    pub fn standard() -> Self {
        Self {
            max: RESTART_LIMIT,
            window_ms: RESTART_WINDOW_MS,
            stamps: Vec::new(),
        }
    }

    pub fn allow(&mut self, now_ms: u64) -> bool {
        let window = self.window_ms;
        self.stamps
            .retain(|stamp| now_ms.saturating_sub(*stamp) < window);
        if self.stamps.len() as u32 >= self.max {
            return false;
        }
        self.stamps.push(now_ms);
        true
    }
}

#[derive(Debug, Default)]
pub struct SpyLauncher {
    next: u32,
    alive_set: BTreeSet<u32>,
    pub killed: Vec<u32>,
    pub commands: Vec<Vec<String>>,
    spawns: u32,
}

impl ChildControl for SpyLauncher {
    fn spawn(&mut self, argv: &[String]) -> std::io::Result<u32> {
        self.spawns = self.spawns.saturating_add(1);
        self.next = self.next.saturating_add(1);
        self.alive_set.insert(self.next);
        self.commands.push(argv.to_vec());
        Ok(self.next)
    }

    fn kill(&mut self, pid: u32) {
        self.alive_set.remove(&pid);
        self.killed.push(pid);
    }

    fn alive(&self) -> Vec<u32> {
        let mut ids: Vec<u32> = self.alive_set.iter().copied().collect();
        ids.sort_unstable();
        ids
    }

    fn spawn_count(&self) -> u32 {
        self.spawns
    }
}

#[derive(Debug, Default)]
pub struct SpyBinder {
    pub paths: Vec<PathBuf>,
}

impl SocketBind for SpyBinder {
    fn bind_unix(&mut self, path: &Path) -> std::io::Result<()> {
        self.paths.push(path.to_path_buf());
        Ok(())
    }

    fn binds(&self) -> u32 {
        u32::try_from(self.paths.len()).unwrap_or(u32::MAX)
    }
}

#[derive(Debug, Default)]
pub struct SpyNet {
    pub hosts: Vec<String>,
}

impl NetGate for SpyNet {
    fn connect(&mut self, host: &str) -> std::io::Result<()> {
        self.hosts.push(host.to_string());
        Ok(())
    }

    fn attempts(&self) -> u32 {
        u32::try_from(self.hosts.len()).unwrap_or(u32::MAX)
    }
}

pub struct Supervisor<C: ChildControl> {
    child: C,
    argv: Vec<String>,
    state: ChildState,
    budget: RestartBudget,
    now_ms: u64,
    pid: Option<u32>,
}

impl<C: ChildControl> Supervisor<C> {
    pub fn new(child: C, argv: Vec<String>) -> Self {
        Self {
            child,
            argv,
            state: ChildState::NotStarted,
            budget: RestartBudget::standard(),
            now_ms: 0,
            pid: None,
        }
    }

    pub fn state(&self) -> &ChildState {
        &self.state
    }

    pub fn alive(&self) -> Vec<u32> {
        self.child.alive()
    }

    pub fn spawn_count(&self) -> u32 {
        self.child.spawn_count()
    }

    pub fn advance(&mut self, ms: u64) {
        self.now_ms = self.now_ms.saturating_add(ms);
    }

    pub fn start(&mut self) -> Result<(), ChildState> {
        self.state = self.state.step(&ChildEvent::Launch)?;
        let pid = self
            .child
            .spawn(&self.argv)
            .map_err(|_| self.state.clone())?;
        self.pid = Some(pid);
        self.state = self.state.step(&ChildEvent::Spawned)?;
        self.state = self.state.step(&ChildEvent::Loaded)?;
        Ok(())
    }

    pub fn on_exit(&mut self, code: i32) -> &ChildState {
        if let Some(pid) = self.pid.take() {
            self.child.kill(pid);
        }
        self.state = self
            .state
            .step(&ChildEvent::Exited { code })
            .unwrap_or(ChildState::Unhealthy);
        if self.budget.allow(self.now_ms) {
            if let Ok(next) = self.state.step(&ChildEvent::Restart) {
                self.state = next;
                if let Ok(pid) = self.child.spawn(&self.argv) {
                    self.pid = Some(pid);
                    if let Ok(spawned) = self.state.step(&ChildEvent::Spawned) {
                        self.state = spawned;
                    }
                    if let Ok(loaded) = self.state.step(&ChildEvent::Loaded) {
                        self.state = loaded;
                    }
                }
            }
        } else {
            self.state = self
                .state
                .step(&ChildEvent::BudgetExhausted)
                .unwrap_or(ChildState::Stopped { failed: true });
        }
        &self.state
    }
}

/// Real process table. Used only after [`decide`] allows a launch.
///
/// Children are in their own shutdown path: SIGTERM, a short grace, then
/// SIGKILL. On Linux each child is armed with `PR_SET_PDEATHSIG` so a
/// crashed supervisor does not leave `python -m haru_mlx.native` running.
pub struct StdLauncher {
    children: std::cell::RefCell<Vec<Child>>,
    spawns: u32,
}

impl StdLauncher {
    pub fn new() -> Self {
        Self {
            children: std::cell::RefCell::new(Vec::new()),
            spawns: 0,
        }
    }
}

impl Default for StdLauncher {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for StdLauncher {
    fn drop(&mut self) {
        let children: Vec<Child> = self.children.borrow_mut().drain(..).collect();
        for mut child in children {
            terminate_child(&mut child);
        }
    }
}

impl ChildControl for StdLauncher {
    fn spawn(&mut self, argv: &[String]) -> std::io::Result<u32> {
        let mut command =
            std::process::Command::new(argv.first().map(String::as_str).unwrap_or("python3"));
        if argv.len() > 1 {
            command.args(&argv[1..]);
        }
        // Safety: the hook runs after fork and only calls the async-signal-safe
        // prctl/getppid/raise sequence. It does not allocate or touch locks.
        unsafe {
            command.pre_exec(|| {
                arm_parent_death();
                Ok(())
            });
        }
        let child = command.spawn()?;
        let pid = child.id();
        self.children.borrow_mut().push(child);
        self.spawns = self.spawns.saturating_add(1);
        Ok(pid)
    }

    fn kill(&mut self, pid: u32) {
        let index = self
            .children
            .borrow()
            .iter()
            .position(|child| child.id() == pid);
        if let Some(index) = index {
            let mut child = self.children.borrow_mut().swap_remove(index);
            terminate_child(&mut child);
        }
    }

    fn alive(&self) -> Vec<u32> {
        let mut children = self.children.borrow_mut();
        children.retain_mut(|child| match child.try_wait() {
            Ok(Some(_)) => false,
            Ok(None) => true,
            Err(_) => false,
        });
        children.iter().map(Child::id).collect()
    }

    fn spawn_count(&self) -> u32 {
        self.spawns
    }
}

const SHUTDOWN_GRACE: std::time::Duration = std::time::Duration::from_millis(200);
const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;

fn terminate_child(child: &mut Child) {
    let pid = child.id() as i32;
    unsafe { kill(pid, SIGTERM) };
    let deadline = std::time::Instant::now() + SHUTDOWN_GRACE;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return,
            Ok(None) if std::time::Instant::now() >= deadline => break,
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(10)),
            Err(_) => break,
        }
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn arm_parent_death() {
    #[cfg(target_os = "linux")]
    unsafe {
        let parent = getppid();
        let _ = prctl(1, SIGKILL as usize, 0, 0, 0);
        if getppid() != parent {
            raise(SIGKILL);
        }
    }
}

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
    #[cfg(target_os = "linux")]
    fn prctl(option: i32, arg2: usize, arg3: usize, arg4: usize, arg5: usize) -> i32;
    #[cfg(target_os = "linux")]
    fn getppid() -> i32;
    #[cfg(target_os = "linux")]
    fn raise(sig: i32) -> i32;
}

pub struct StdBinder;

impl SocketBind for StdBinder {
    fn bind_unix(&mut self, path: &Path) -> std::io::Result<()> {
        crate::serve::bind_socket(path).map(|_| ())
    }

    fn binds(&self) -> u32 {
        0
    }
}
