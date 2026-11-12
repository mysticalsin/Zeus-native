"""Bounded, isolated process-group controls; no native app or capture acceptance."""
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

RUNNER_FILE = Path(__file__).resolve().parents[1] / "run.py"
sys.path.insert(0, str(RUNNER_FILE.parent))
spec = importlib.util.spec_from_file_location("execution_runner", RUNNER_FILE)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


# This supervisor has its own session, so even a broken group implementation
# cannot target unittest or another CI job. All helper lifetimes are finite.
SUPERVISOR = r'''
import importlib.util,json,os,select,signal,subprocess,sys,time
from pathlib import Path
root=Path(sys.argv[1]);mode=sys.argv[2];module_path=Path(sys.argv[3])
sys.path.insert(0,str(module_path.parent))
spec=importlib.util.spec_from_file_location("owned_runner",module_path)
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
fifo=root/"owned-output";os.mkfifo(fifo,0o600)
read_fd=os.open(fifo,os.O_RDONLY|os.O_NONBLOCK)
control=subprocess.Popen([sys.executable,"-c","import time; time.sleep(6)"])
grandchild=r"""
import json,os,signal,sys,time
from pathlib import Path
root=Path(sys.argv[1]);signal.signal(signal.SIGTERM,signal.SIG_IGN)
until=time.monotonic()+2.5
fd=os.open(root/"owned-output",os.O_WRONLY|os.O_NONBLOCK)
(root/"grandchild.json").write_text(json.dumps({"pid":os.getpid(),"pgid":os.getpgrp()}))
while time.monotonic()<until:
 os.write(fd,b"h");time.sleep(0.02)
os.close(fd)
"""
leader="import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',sys.argv[1],sys.argv[2]]); time.sleep(3)"
created=[]
original_popen=subprocess.Popen
def launch(*args,**kwargs):
 p=original_popen(*args,**kwargs);created.append(p)
 if mode!="timeout":
  poll=p.poll;interrupted=False
  def interrupt_once():
   nonlocal interrupted
   if not interrupted and (root/"grandchild.json").exists():
    interrupted=True
    if mode=="interrupt":raise KeyboardInterrupt()
    raise SystemExit(23)
   return poll()
  p.poll=interrupt_once
 return p
runner.subprocess.Popen=launch
began=time.monotonic();code=None;exception=None
original_mask=signal.pthread_sigmask(signal.SIG_BLOCK,set())
try:
 code,_=runner.execute([sys.executable,"-c",leader,grandchild,str(root)],root/"check.log",0.8)
except BaseException as error:exception=type(error).__name__
elapsed=time.monotonic()-began
ready=(root/"grandchild.json").exists()
info=json.loads((root/"grandchild.json").read_text()) if ready else {}
def drain_until_eof(seconds):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  try:
   chunk=os.read(read_fd,4096)
   if chunk==b"":return True
  except BlockingIOError:pass
  select.select([read_fd],[],[],0.01)
 return False
eof=drain_until_eof(0.2) if ready else False
control_alive=control.poll() is None
direct_reaped=bool(created) and created[0].returncode is not None
result={"code":code,"exception":exception,"elapsed":elapsed,"ready":ready,"eof":eof,
        "control_alive":control_alive,"direct_reaped":direct_reaped,
        "mask_restored":signal.pthread_sigmask(signal.SIG_BLOCK,set())==original_mask,
        "owned_group":bool(created) and info.get("pgid")==created[0].pid,
        "different_control_group":bool(created) and os.getpgid(control.pid)!=created[0].pid if control_alive else False,
        "log":(root/"check.log").read_text()}
# A negative control must not leak its finite grandchild after its assertion.
drain_until_eof(3)
for p in created:
 if p.returncode is None:
  try:p.wait(timeout=1)
  except subprocess.TimeoutExpired:pass
control.terminate();control.wait(timeout=1);os.close(read_fd)
print(json.dumps(result),flush=True)
sys.stdin.readline()  # Retain this leader's PID until the outer supervisor kills its own group.
'''


class ExecutionCleanupTests(unittest.TestCase):
    @staticmethod
    def stop_supervisor(process):
        # This fixture leader has never been polled/reaped and reserves its separate
        # group. One final signal avoids TERM making the group zombie-only before
        # another killpg call; Darwin can reject that second signal with EPERM.
        try:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        finally:
            try:
                process.wait(timeout=2)
            finally:
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close()

    def isolated_case(self, mode):
        with tempfile.TemporaryDirectory(prefix="zeus-owned-command-") as directory:
            process = subprocess.Popen([sys.executable, "-c", SUPERVISOR, directory, mode, str(RUNNER_FILE)],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       start_new_session=True)
            try:
                deadline = time.monotonic() + 8
                data = bytearray()
                while b"\n" not in data and time.monotonic() < deadline:
                    if select.select([process.stdout], [], [], 0.05)[0]:
                        chunk = os.read(process.stdout.fileno(), 16_384)
                        if not chunk:
                            break
                        data.extend(chunk)
                self.assertIn(b"\n", data, "Isolated supervisor failed to return its bounded result")
                result = json.loads(bytes(data).split(b"\n", 1)[0])
                self.assertTrue(result["ready"], "The actual grandchild must have opened its owned pipe")
                self.assertTrue(result["eof"], "The TERM-ignoring grandchild retained the owned output pipe")
                self.assertTrue(result["owned_group"])
                self.assertTrue(result["different_control_group"])
                self.assertTrue(result["control_alive"], "Cleanup must not signal another owned control process")
                self.assertTrue(result["direct_reaped"])
                self.assertTrue(result["mask_restored"])
                self.assertLess(result["elapsed"], 2.8)
                self.assertNotIn("CLEANUP UNCONFIRMED", result["log"])
                return result
            finally:
                self.stop_supervisor(process)

    def test_outer_supervisor_signals_once_before_reaping_and_closes_handles(self):
        process = Mock(pid=123)
        observed = []
        process.wait.side_effect = lambda **kwargs: observed.append("wait")
        with patch.object(os, "killpg", side_effect=lambda *args: observed.append("kill")) as kill:
            self.stop_supervisor(process)
        kill.assert_called_once_with(123, signal.SIGKILL)
        process.wait.assert_called_once_with(timeout=2)
        process.poll.assert_not_called()
        self.assertEqual(observed, ["kill", "wait"])
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close.assert_called_once_with()

    def test_outer_supervisor_signal_or_reap_error_stays_visible_after_handle_cleanup(self):
        for point in ("signal", "reap"):
            with self.subTest(point=point):
                process = Mock(pid=123)
                error = PermissionError(1, "synthetic signal denial") if point == "signal" else subprocess.TimeoutExpired("synthetic supervisor", 2)
                if point == "reap":
                    process.wait.side_effect = error
                with patch.object(os, "killpg", side_effect=error if point == "signal" else None) as kill:
                    with self.assertRaises(type(error)) as caught:
                        self.stop_supervisor(process)
                self.assertIs(caught.exception, error)
                kill.assert_called_once_with(123, signal.SIGKILL)
                process.wait.assert_called_once_with(timeout=2)
                process.poll.assert_not_called()
                for stream in (process.stdin, process.stdout, process.stderr):
                    stream.close.assert_called_once_with()

    def test_timeout_stops_owned_grandchild_and_preserves_other_process_group(self):
        result = self.isolated_case("timeout")
        self.assertEqual(result["code"], 124)
        self.assertIsNone(result["exception"])
        self.assertIn("CHECK TIMEOUT after 0.8 seconds", result["log"])

    def test_keyboard_interrupt_cleans_owned_group_before_rethrow(self):
        result = self.isolated_case("interrupt")
        self.assertIsNone(result["code"])
        self.assertEqual(result["exception"], "KeyboardInterrupt")

    def test_other_base_exception_cleans_owned_group_before_rethrow(self):
        result = self.isolated_case("system-exit")
        self.assertIsNone(result["code"])
        self.assertEqual(result["exception"], "SystemExit")

    def test_reaped_or_uncertain_child_cannot_signal_a_reused_group(self):
        original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
        for returncode, probe in ((0, None), (None, ChildProcessError()), (None, (123, 0))):
            with self.subTest(returncode=returncode, probe=probe):
                process = Mock(pid=123, returncode=returncode)
                log = io.StringIO()
                options = {"side_effect": probe} if isinstance(probe, Exception) else {"return_value": probe}
                with patch.object(runner.os, "waitpid", **options), patch.object(runner.os, "killpg") as kill:
                    self.assertFalse(runner.cleanup_owned_command(process, log))
                kill.assert_not_called()
                process.wait.assert_not_called()
                self.assertIn("CLEANUP UNCONFIRMED", log.getvalue())
                self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), original_mask)

    def test_external_child_reaper_policy_refuses_group_signal_and_restores_mask(self):
        original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
        for handler in (signal.SIG_IGN, lambda *_: None):
            with self.subTest(handler=handler):
                process = Mock(pid=123, returncode=None)
                log = io.StringIO()
                with patch.object(runner.signal, "getsignal", return_value=handler), \
                     patch.object(runner.os, "waitpid") as probe, patch.object(runner.os, "killpg") as kill:
                    self.assertFalse(runner.cleanup_owned_command(process, log))
                probe.assert_not_called()
                kill.assert_not_called()
                process.wait.assert_not_called()
                self.assertIn("CLEANUP UNCONFIRMED", log.getvalue())
                self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), original_mask)

    def test_nondefault_child_reaping_policy_cannot_launch_or_forge_success(self):
        with tempfile.TemporaryDirectory(prefix="zeus-command-reaper-") as directory:
            log = Path(directory) / "refused.log"
            for handler in (signal.SIG_IGN, lambda *_: None):
                with self.subTest(handler=handler), \
                     patch.object(runner.signal, "getsignal", return_value=handler), \
                     patch.object(runner.signal, "signal") as change_handler, \
                     patch.object(runner.subprocess, "Popen") as launch:
                    code, _ = runner.execute(["synthetic"], log, 1)
                self.assertEqual(code, 127)
                self.assertIn("Default SIGCHLD ownership is required", log.read_text())
                launch.assert_not_called()
                change_handler.assert_not_called()

    def test_bounded_reap_failure_is_reported_without_a_second_group_signal(self):
        process = Mock(pid=123, returncode=None)
        process.wait.side_effect = subprocess.TimeoutExpired("owned fixture", 1)
        log = io.StringIO()
        original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
        with patch.object(runner.os, "waitpid", return_value=(0, 0)) as probe, \
             patch.object(runner.os, "getpgid", return_value=123), \
             patch.object(runner.os, "killpg") as kill, patch.object(runner.time, "sleep"):
            self.assertFalse(runner.cleanup_owned_command(process, log))
        self.assertEqual([call.args for call in kill.call_args_list], [(123, signal.SIGTERM), (123, signal.SIGKILL)])
        process.wait.assert_called_once_with(timeout=1)
        process.poll.assert_not_called()
        probe.assert_called_once_with(123, os.WNOHANG)
        self.assertIn("CLEANUP UNCONFIRMED", log.getvalue())
        self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), original_mask)

    def test_exception_during_term_or_grace_still_kills_reaps_and_restores_mask(self):
        class InterruptedCleanup(BaseException):
            pass

        for point in ("term", "grace"):
            with self.subTest(point=point):
                original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
                error = InterruptedCleanup()
                process = Mock(pid=123, returncode=None)
                with patch.object(runner.os, "waitpid", return_value=(0, 0)) as probe, \
                     patch.object(runner.os, "getpgid", return_value=123), \
                     patch.object(runner.os, "killpg", side_effect=[error, None] if point == "term" else None) as kill, \
                     patch.object(runner.time, "sleep", side_effect=error if point == "grace" else None):
                    with self.assertRaises(InterruptedCleanup) as caught:
                        runner.cleanup_owned_command(process, io.StringIO())
                self.assertIs(caught.exception, error)
                self.assertEqual([call.args for call in kill.call_args_list], [(123, signal.SIGTERM), (123, signal.SIGKILL)])
                process.wait.assert_called_once_with(timeout=1)
                process.poll.assert_not_called()
                probe.assert_called_once_with(123, os.WNOHANG)
                self.assertEqual(signal.pthread_sigmask(signal.SIG_BLOCK, set()), original_mask)

    def test_exit_observed_after_deadline_cannot_pass_or_signal_a_reaped_group(self):
        with tempfile.TemporaryDirectory(prefix="zeus-command-deadline-") as directory:
            log = Path(directory) / "late.log"
            process = Mock(pid=123, returncode=0)
            process.poll.return_value = 0
            with patch.object(runner.subprocess, "Popen", return_value=process), \
                 patch.object(runner.time, "monotonic", side_effect=[0, 0, 3.1, 3.1]), \
                 patch.object(runner.os, "killpg") as kill:
                code, seconds = runner.execute(["synthetic"], log, 3)
            self.assertEqual((code, seconds), (124, 3.1))
            self.assertIn("CHECK TIMEOUT", log.read_text())
            self.assertIn("CLEANUP UNCONFIRMED", log.read_text())
            kill.assert_not_called()
            process.wait.assert_not_called()

    def test_success_failure_environment_and_missing_command_keep_their_contract(self):
        with tempfile.TemporaryDirectory(prefix="zeus-command-result-") as directory:
            log = Path(directory) / "command.log"
            for expected in (0, 7):
                code, _ = runner.execute([sys.executable, "-c",
                    "import os,sys; print(os.environ['ZEUS_SYNTHETIC_VALUE']); sys.exit(int(sys.argv[1]))", str(expected)],
                    log, 2, {"ZEUS_SYNTHETIC_VALUE": "synthetic only"})
                self.assertEqual(code, expected)
                self.assertEqual(log.read_text(), "synthetic only\n")
            code, _ = runner.execute([str(Path(directory) / "missing")], log, 1)
            self.assertEqual(code, 127)
            self.assertIn("CHECK COULD NOT START", log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
