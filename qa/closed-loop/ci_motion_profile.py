#!/usr/bin/env python3
"""Temporarily enable normal motion only in a disposable GitHub-hosted Mac profile."""
import os
import platform
import signal
import subprocess
import sys

DOMAIN = "com.apple.universalaccess"
KEY = "reduceMotion"
MARKER = "ZEUS_CI_REQUIRE_NORMAL_MOTION"


def defaults(*arguments):
    result = subprocess.run(["/usr/bin/defaults", *arguments], capture_output=True, text=True,
                            timeout=5, check=False, env={**os.environ, "LC_ALL": "C"})
    if result.returncode != 0:
        raise RuntimeError("defaults command failed")
    return result.stdout.strip()


def read_preference():
    if defaults("read-type", DOMAIN, KEY) != "Type is boolean":
        raise RuntimeError("reduceMotion is not an existing boolean")
    value = defaults("read", DOMAIN, KEY)
    if value not in {"0", "1"}:
        raise RuntimeError("reduceMotion boolean could not be read")
    return value == "1"


def write_preference(value):
    defaults("write", DOMAIN, KEY, "-bool", "true" if value else "false")
    if read_preference() != value:
        raise RuntimeError("reduceMotion write did not persist")


def run_native(arguments):
    import native
    return native.main(arguments)


def interrupted(_signal, _frame):
    raise KeyboardInterrupt


def main(arguments=None):
    if not (platform.system() == "Darwin" and os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"):
        print("CI motion profile unavailable: requires a GitHub-hosted Mac runner")
        return 1
    try:
        original = read_preference()
    except (OSError, RuntimeError, subprocess.SubprocessError):
        print("CI motion profile unavailable: existing boolean preference could not be read")
        return 1
    previous_marker = os.environ.get(MARKER)
    previous_term = signal.signal(signal.SIGTERM, interrupted)
    code = 1
    restored = False
    try:
        write_preference(False)
        os.environ[MARKER] = "1"
        code = run_native(sys.argv[1:] if arguments is None else arguments)
        if type(code) is not int or not 0 <= code <= 255:
            code = 1
    except KeyboardInterrupt:
        code = 130
    except SystemExit as error:
        code = error.code if type(error.code) is int and 1 <= error.code <= 255 else 1
    except Exception:
        print("CI motion profile or native checks failed")
        code = 1
    finally:
        if previous_marker is None:
            os.environ.pop(MARKER, None)
        else:
            os.environ[MARKER] = previous_marker
        try:
            write_preference(original)
            restored = True
        except (OSError, RuntimeError, subprocess.SubprocessError):
            print("CI motion profile restoration failed")
            code = code or 1
        finally:
            signal.signal(signal.SIGTERM, previous_term)
    print(f"CI motion profile: wrapper_exit={code}; original_reduce_motion={str(original).lower()}; restored={str(restored).lower()}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
