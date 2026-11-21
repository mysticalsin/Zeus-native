//! Child processes must not become zombies, survive the supervisor, or ignore shutdown.

use haru_companion::session::ChildControl;
use haru_companion::supervisor::StdLauncher;
use std::path::Path;
use std::time::{Duration, Instant};

fn proc_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

struct KillOnDrop(u32);

impl Drop for KillOnDrop {
    fn drop(&mut self) {
        if proc_alive(self.0) {
            unsafe { kill(self.0 as i32, 9) };
        }
    }
}

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

fn wait_until(timeout: Duration, mut ready: impl FnMut() -> bool) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if ready() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    ready()
}

#[test]
fn exited_child_is_reaped_instead_of_staying_a_zombie() {
    let mut launcher = StdLauncher::new();
    let pid = launcher
        .spawn(&["/bin/true".into()])
        .expect("spawn /bin/true");
    assert!(
        wait_until(Duration::from_secs(2), || {
            let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).unwrap_or_default();
            stat.contains(" Z ") || !proc_alive(pid)
        }),
        "child did not exit"
    );
    assert!(
        launcher.alive().is_empty(),
        "pid {pid} was not reaped; alive={:?}",
        launcher.alive()
    );
}

#[test]
fn dropping_the_launcher_kills_the_child() {
    let pid = {
        let mut launcher = StdLauncher::new();
        launcher
            .spawn(&["/bin/sleep".into(), "30".into()])
            .expect("spawn sleep")
    };
    let _guard = KillOnDrop(pid);
    assert!(
        wait_until(Duration::from_secs(2), || !proc_alive(pid)),
        "child {pid} survived the supervisor"
    );
}

#[test]
fn kill_sends_sigterm_before_sigkill() {
    let dir = std::env::temp_dir().join(format!("zeus-haru-term-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("term.py");
    let flag = dir.join("caught");
    let ready = dir.join("ready");
    std::fs::write(
        &script,
        format!(
            "import signal, sys, time\n\
             def stop(*_):\n\
             \topen({flag:?}, 'w').write('term')\n\
             \tsys.exit(0)\n\
             signal.signal(signal.SIGTERM, stop)\n\
             open({ready:?}, 'w').write('up')\n\
             time.sleep(30)\n"
        ),
    )
    .unwrap();

    let mut launcher = StdLauncher::new();
    let pid = launcher
        .spawn(&["python3".into(), script.display().to_string()])
        .expect("spawn script");
    let _guard = KillOnDrop(pid);
    assert!(
        wait_until(Duration::from_secs(2), || ready.exists()),
        "helper did not install its SIGTERM handler"
    );
    launcher.kill(pid);
    assert!(
        wait_until(Duration::from_secs(2), || flag.exists()),
        "SIGTERM was not delivered before the process died"
    );
    assert!(wait_until(Duration::from_secs(2), || !proc_alive(pid)));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn kill_escalates_to_sigkill_when_sigterm_is_ignored() {
    let dir = std::env::temp_dir().join(format!("zeus-haru-kill-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("ignore.py");
    std::fs::write(
        &script,
        "import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(30)\n",
    )
    .unwrap();

    let mut launcher = StdLauncher::new();
    let pid = launcher
        .spawn(&["python3".into(), script.display().to_string()])
        .expect("spawn script");
    let _guard = KillOnDrop(pid);
    assert!(wait_until(Duration::from_secs(2), || proc_alive(pid)));
    let started = Instant::now();
    launcher.kill(pid);
    assert!(
        wait_until(Duration::from_secs(2), || !proc_alive(pid)),
        "process that ignored SIGTERM was not killed"
    );
    assert!(
        started.elapsed() < Duration::from_secs(2),
        "escalation took too long"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn child_is_armed_to_die_with_its_parent() {
    let dir = std::env::temp_dir().join(format!("zeus-haru-pdeath-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let script = dir.join("pdeath.py");
    let flag = dir.join("sig");
    std::fs::write(
        &script,
        "import ctypes, sys\nlibc = ctypes.CDLL('libc.so.6')\nsig = ctypes.c_int(0)\nlibc.prctl(2, ctypes.byref(sig))\nopen(sys.argv[1], 'w').write(str(sig.value))\n",
    )
    .unwrap();
    let mut launcher = StdLauncher::new();
    let pid = launcher
        .spawn(&[
            "python3".into(),
            script.display().to_string(),
            flag.display().to_string(),
        ])
        .expect("spawn python");
    let _guard = KillOnDrop(pid);
    assert!(
        wait_until(Duration::from_secs(3), || flag.exists()),
        "helper did not report PR_GET_PDEATHSIG"
    );
    let text = std::fs::read_to_string(&flag).unwrap();
    assert_eq!(text.trim(), "9", "parent-death signal was {text}");
    let _ = std::fs::remove_dir_all(&dir);
}
