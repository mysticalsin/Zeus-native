"""Use haru-pipe when it is installed, otherwise the upstream Python path (the default).

    from python_fallback import load_audio_24k
    pcm = load_audio_24k("user.wav")   # mono float32 at 24 kHz, like haru_mlx.audio.load_audio

Nothing changes for haru-mlx-inference itself: it keeps its own Python I/O.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np


def _binary() -> str | None:
    return os.environ.get("HARU_PIPE_BIN") or shutil.which("haru-pipe")


def _frames_len(path) -> int:
    import soundfile as sf
    from math import ceil

    info = sf.info(str(path))
    return ceil(info.frames * 24_000 / info.samplerate) if info.samplerate != 24_000 else info.frames


def load_audio_24k(path: str | Path) -> np.ndarray:
    exe = _binary()
    if exe:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "24k.wav"
            r = subprocess.run([exe, "convert", str(path), str(out), "--float"], capture_output=True, text=True)
            if r.returncode == 0:
                data = out.read_bytes()
                # haru-pipe pads to whole frames; upstream does not (run_inference pads later)
                n = -(-_frames_len(path))
                return np.frombuffer(data[44:], dtype="<f4")[:n].copy()
    from haru_mlx.audio import load_audio  # fallback: upstream, unchanged

    return load_audio(path)
