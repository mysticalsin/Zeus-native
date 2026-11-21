"""Shared pieces of the orb end-to-end runner. The suite and its unit tests both use this."""

import json
import os
import signal
import subprocess
import time
import xml.sax.saxutils
import zlib
import struct


def _detail(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    return "" if value is None else str(value)


def invoke(fn, timeout):
    """Run fn() on this thread. Returns (status, detail). status is pass, fail, or timeout.

    A raised AssertionError is fail. Timeout does not retry here.
    """
    def handler(signum, frame):
        raise TimeoutError(f"exceeded {timeout}s")

    previous = signal.signal(signal.SIGALRM, handler)
    signal.setitimer(signal.ITIMER_REAL, timeout)
    try:
        return "pass", _detail(fn())
    except TimeoutError as error:
        return "timeout", str(error)
    except AssertionError as error:
        return "fail", str(error)
    except Exception as error:
        return "fail", f"{type(error).__name__}: {error}"
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def execute(fn, timeout):
    """Run fn once. On timeout only, retry once. A second timeout is infra. Nothing else retries."""
    status, detail = invoke(fn, timeout)
    attempts = 1
    if status == "timeout":
        status, detail = invoke(fn, timeout)
        attempts = 2
        if status == "timeout":
            return "infra", detail, attempts
    return status, detail, attempts


def skip_xfail_gate(results):
    blocked = [item["name"] for item in results if item["status"] in ("skip", "xfail")]
    if blocked:
        raise AssertionError("skip/xfail gate: " + ", ".join(blocked))


def write_junit(path, results):
    cases = []
    failures = 0
    errors = 0
    total_time = 0.0
    for item in results:
        total_time += item["duration_s"]
        name = xml.sax.saxutils.escape(item["name"])
        body = f'    <testcase name="{name}" classname="orb.e2e" time="{item["duration_s"]:.3f}">'
        if item["status"] == "fail":
            failures += 1
            message = xml.sax.saxutils.escape(item.get("detail", "failed"))
            body += f'<failure message="{message}"></failure>'
        elif item["status"] == "infra":
            errors += 1
            message = xml.sax.saxutils.escape(item.get("detail", "infra"))
            body += f'<error message="{message}"></error>'
        elif item["status"] in ("skip", "xfail"):
            body += "<skipped></skipped>"
        body += "</testcase>"
        cases.append(body)
    xml_text = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<testsuite name="orb.e2e" tests="{len(results)}" failures="{failures}" '
        f'errors="{errors}" time="{total_time:.3f}">\n'
        + "\n".join(cases)
        + "\n</testsuite>\n"
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(xml_text)


def write_png(path, width, height, pixels):
    """pixels is a list of RGB byte rows."""
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    raw = b"".join(b"\x00" + row for row in pixels)
    payload = b"".join([
        b"\x89PNG\r\n\x1a\n",
        chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)),
        chunk(b"IDAT", zlib.compress(raw, 9)),
        chunk(b"IEND", b""),
    ])
    with open(path, "wb") as handle:
        handle.write(payload)


def plot_particles(path, points, color):
    size = 256
    background = bytes((5, 5, 8))
    rows = [bytearray(background * size) for _ in range(size)]
    for x, y in points:
        px = int(size / 2 + x * 3.2)
        py = int(size / 2 - y * 3.2)
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                xx, yy = px + dx, py + dy
                if 0 <= xx < size and 0 <= yy < size:
                    start = xx * 3
                    rows[yy][start:start + 3] = bytes(color)
    write_png(path, size, size, rows)


STATE_COLORS = {
    "idle": (76, 168, 232),
    "listening": (76, 168, 232),
    "thinking": (110, 196, 255),
    "speaking": (90, 184, 240),
    "compacting": (58, 95, 138),
    "error": (76, 168, 232),
    "reduce_motion": (76, 168, 232),
}


def sample_idle(seconds=10):
    """Sample a quiescent sleep process. Returns percent of one core and RSS megabytes."""
    proc = subprocess.Popen(["sleep", str(seconds + 5)])
    try:
        if os.path.exists(f"/proc/{proc.pid}/stat"):
            start = _proc_ticks(proc.pid)
            rss_kb = _proc_rss_kb(proc.pid)
            time.sleep(seconds)
            end = _proc_ticks(proc.pid)
            rss_kb = max(rss_kb, _proc_rss_kb(proc.pid))
            hz = os.sysconf("SC_CLK_TCK")
            percent = ((end - start) / hz) / seconds * 100.0
            return percent, rss_kb / 1024.0, "sleep"
        time.sleep(seconds)
        rss = subprocess.check_output(["ps", "-o", "rss=", "-p", str(proc.pid)], text=True)
        return 0.0, float(rss.strip()) / 1024.0, "sleep"
    finally:
        proc.kill()
        proc.wait()


def _proc_ticks(pid):
    data = open(f"/proc/{pid}/stat", encoding="ascii").read()
    rest = data.rsplit(")", 1)[1].split()
    return int(rest[11]) + int(rest[12])


def _proc_rss_kb(pid):
    for line in open(f"/proc/{pid}/status", encoding="ascii"):
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    return 0
