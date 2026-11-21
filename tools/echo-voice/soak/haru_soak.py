#!/usr/bin/env python3
"""Long-session stability soak for Haru-4B (haru-speech-mlx 0.1.0, MLX, Apple silicon).

Drives the upstream Python API (haru_mlx.session.DuplexSession, the same object
`haru-mlx-inference` and `haru-mlx-native` use) in continuous full duplex over a
scripted, synthetic conversation (user side = built-in macOS `say` voices, no
real person's voice, no voice reference), for 10 / 30 / 60 minutes of audio,
and measures whether the session degrades: latency drift, memory growth,
repetition loops, off-topic replies, non-responses, garbage audio.

Subcommands
  make-script  build the user-side audio + script.json (macOS only: `say`)
  run          one soak run (backend `haru` on the Mac, or `fake` anywhere)
  analyze      metrics.json + report.md for a run directory (pure Python + numpy)
  selftest     unit tests + fake-backend integration tests (no MLX, no model)
  plan         print the Mac run matrix (exact commands)
  faults       explicit error/recovery cases, each run ONCE (retries 0): expected vs observed + recovery time
  summarize    (box) results/<run-id>/ dirs -> summary.json (+ SCHEMA.md), report.md, blind listening pack, MANIFEST.sha256

Measured per run (analyze): per-frame latency p50/p95/p99/max, RTF and first-audio latency per turn, per 5-min
window; memory/stability; naturalness PROXIES from the reply audio with numpy only (pause lengths, speaking rate,
F0 range/variance by autocorrelation, energy dynamics, clipping, silence/garbage, reply gap, barge-in yield).
These are proxies, NOT MOS. Sample WAVs (user L / Haru R) at start, middle, end of each run for blind listening.

Mitigation switches (see MITIGATIONS below for which knobs upstream exposes):
  --temperature --top-k --top-p --guidance-scale --eop-bias   upstream DuplexConfig fields
  --dry on|off --dry-multiplier --dry-lookback                 upstream DRY repetition penalty
  --kv-window N        rolling KV truncation: keep prompt + last N positions (ours, experimental)
  --reanchor-minutes M fresh session (system prompt re-run) at the next idle turn boundary (ours)
  --watchdog           restart the session cleanly on loop / latency / memory / silence (ours)
Everything that is ours is VAD-gated: it only acts when both sides are silent,
unless a hard limit (latency or memory) is crossed.

Never downloads anything: --model must be a local directory.
"""
from __future__ import annotations

import argparse
import dataclasses
import enum
import gc
import json
import math
import os
import random
import re
import resource
import subprocess
import sys
import time
import unicodedata
from collections import Counter, deque
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

SR, FRAME = 24_000, 3200
FRAME_S = FRAME / SR
VOICED_DBFS = -45.0  # upstream's own silence threshold (haru_mlx/audio.py L14)

# ----------------------------------------------------------------------------- knobs
# What haru-speech-mlx 0.1.0 actually exposes (sdist sha256 c52ac526...ae71):
MITIGATIONS = {
    "temperature/top_k/top_p": "DuplexConfig (frames.py L15-17), used in session._emit (session.py L161). "
                               "CLI: run_inference exposes --temperature/--top-k only (run_inference.py L37-38); "
                               "top_p only via the Python API; haru-mlx-native exposes none (native.py L168-175).",
    "guidance_scale": "DuplexConfig (frames.py L14), clamped to 1-2 by the server (native.py L172).",
    "dry (repetition penalty)": "DuplexConfig.dry = DryConfig(multiplier 0.8, base 1.75, allowed_length 1, lookback 1024, "
                                "max_match_length 32, max_penalty 32) ON by default (frames.py L18, sampling.py L12-25); "
                                "applied to text logits each frame (session.py L153-154, L170-171). Not exposed on any CLI. "
                                "No classic repetition/frequency penalty exists.",
    "eop_bias": "DuplexConfig (frames.py L19, session.py L156-157): >0 makes the model start speaking sooner. API only.",
    "max_frames": "27000 = 60 min hard stop (frames.py L21, session.py L180).",
    "context truncation / reset / watchdog": "NOT in upstream. The attention KV cache grows without bound "
                                             "(models/qwen3_5.py L83-104, 8 of 32 layers, 32 KiB per position in bf16); "
                                             "Gated DeltaNet layers have constant state. Implemented here.",
}

# ----------------------------------------------------------------------------- text utils


def fold(s: str) -> str:
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


STOP = set("""a an the and or but if of to in on at for with is are was were be been it this that i you he she we they me my your
his her our their do does did not no yes so just like what why how when where who very really oh um uh yeah ok okay
le la les un une des de du et ou mais si a au aux en dans sur pour avec est sont etait il elle on nous vous ils elles je tu
me mon ma mes ton ta tes son sa ses ce cette ces qui que quoi pas ne oui non tres bien ah euh bon alors donc""".split())


def words(s: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", fold(s))


def content_words(s: str) -> list[str]:
    return [w for w in words(s) if w not in STOP and len(w) > 2]


def wer(ref: str, hyp: str) -> float:
    """Word error rate (Levenshtein over words) of hyp against ref."""
    r, h = words(ref), words(hyp)
    if not r:
        return 0.0 if not h else 1.0
    prev = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        cur = [i] + [0] * len(h)
        for j, hw in enumerate(h, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (rw != hw))
        prev = cur
    return prev[-1] / len(r)


def repeated_ngram_ratio(ws: list[str], n: int = 3) -> float:
    """1 - distinct n-grams / all n-grams (0 = no repetition, -> 1 = a loop)."""
    grams = [tuple(ws[i:i + n]) for i in range(len(ws) - n + 1)]
    return 0.0 if not grams else 1.0 - len(set(grams)) / len(grams)


def find_loop(tokens: list[int], min_period: int = 2, max_period: int = 32, min_repeats: int = 3) -> tuple[int, int] | None:
    """(period, repeats) if the sequence ENDS with a block repeated back to back >= min_repeats times."""
    n = len(tokens)
    best = None
    for p in range(min_period, max_period + 1):
        if n < p * min_repeats:
            break
        reps = 1
        while (reps + 1) * p <= n and tokens[n - (reps + 1) * p: n - reps * p] == tokens[n - p:]:
            reps += 1
        if reps >= min_repeats and (best is None or reps * p > best[0] * best[1]):
            best = (p, reps)
    return best


def ols_slope(xs, ys) -> float:
    x, y = np.asarray(xs, float), np.asarray(ys, float)
    if x.size < 2 or np.ptp(x) == 0:
        return 0.0
    return float(np.polyfit(x, y, 1)[0])


class TfIdf:
    """Word uni+bigram TF-IDF over content words, fitted on the script's reference texts."""

    def __init__(self, docs: list[str]):
        self.docs = [self._grams(d) for d in docs]
        df = Counter(g for d in self.docs for g in set(d))
        self.idf = {g: math.log((1 + len(docs)) / (1 + c)) + 1 for g, c in df.items()}

    @staticmethod
    def _grams(s):
        w = content_words(s)
        return w + [a + "_" + b for a, b in zip(w, w[1:])]

    def vec(self, s):
        tf = Counter(g for g in self._grams(s) if g in self.idf)
        v = {g: c * self.idf[g] for g, c in tf.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {g: x / norm for g, x in v.items()}

    @staticmethod
    def cos(a, b):
        return sum(x * b.get(g, 0.0) for g, x in a.items())


def dbfs(x: np.ndarray) -> float:
    r = float(np.sqrt(np.mean(np.square(x, dtype=np.float64)))) if x.size else 0.0
    return -120.0 if r <= 1e-6 else 20 * math.log10(r)


def spectral_flatness(x: np.ndarray) -> float:
    s = np.abs(np.fft.rfft(x * np.hanning(x.size))) + 1e-10
    return float(np.exp(np.mean(np.log(s))) / np.mean(s))


SUB = 400                       # 16.7 ms VAD sub-windows -> 8 per 133 ms frame (bit i of `vm` = sub-window i voiced)
SUB_S = SUB / SR
F0_WIN, F0_LO, F0_HI, F0_THR = 960, 60.0, 400.0, 0.5
_F0_HANN = np.hanning(F0_WIN)
_F0_WAC = np.fft.irfft(np.abs(np.fft.rfft(_F0_HANN, 2 * F0_WIN)) ** 2)[:F0_WIN]
_F0_WAC = _F0_WAC / _F0_WAC[0]


def voiced_mask(x: np.ndarray, threshold=VOICED_DBFS) -> int:
    n = x.size // SUB
    if n == 0:
        return 0
    rms = np.sqrt(np.mean(np.square(x[:n * SUB].reshape(n, SUB), dtype=np.float64), axis=1))
    lim = 10 ** (threshold / 20)
    return int(sum(1 << i for i, r in enumerate(rms) if r > lim))


def f0_autocorr(x: np.ndarray) -> float:
    """Median F0 (Hz) over voiced 40 ms windows; 0.0 if unvoiced/aperiodic. Boersma-style autocorrelation:
    Hann-windowed, normalised by the window's own autocorrelation, parabolic peak interpolation, 60-400 Hz."""
    out = []
    lmin, lmax = int(SR / F0_HI), int(SR / F0_LO)
    for s0 in range(0, x.size - F0_WIN + 1, F0_WIN):
        w = x[s0:s0 + F0_WIN].astype(np.float64)
        if dbfs(w) <= VOICED_DBFS:
            continue
        w = (w - w.mean()) * _F0_HANN
        ac = np.fft.irfft(np.abs(np.fft.rfft(w, 2 * F0_WIN)) ** 2)[:F0_WIN]
        if ac[0] <= 0:
            continue
        r = (ac / ac[0]) / np.maximum(_F0_WAC, 1e-3)
        seg = r[lmin:lmax + 1]
        gmax = float(seg.max())
        if gmax < F0_THR:
            continue
        # smallest-lag local peak close to the best one (avoids picking 2x / 3x the period: octave errors)
        peaks = [j for j in range(1, seg.size - 1) if seg[j] >= seg[j - 1] and seg[j] >= seg[j + 1] and seg[j] >= max(F0_THR, 0.85 * gmax)]
        i = peaks[0] if peaks else int(np.argmax(seg)); lag = lmin + i
        if 0 < i < seg.size - 1:
            a_, b_, c_ = seg[i - 1], seg[i], seg[i + 1]
            den = a_ - 2 * b_ + c_
            lag = lag + (0.5 * (a_ - c_) / den if den != 0 else 0.0)
        out.append(SR / lag)
    return float(np.median(out)) if out else 0.0


def sanitize(u) -> tuple[np.ndarray, list[str]]:
    """Input guard: exactly FRAME float32 samples, finite, within [-1, 1]. Returns (frame, issues)."""
    issues = []
    u = np.asarray(u, dtype=np.float32).reshape(-1)
    if u.size != FRAME:
        issues.append(f"size {u.size}")
        u = np.pad(u[:FRAME], (0, max(0, FRAME - u.size)))
    if not np.isfinite(u).all():
        issues.append("nonfinite")
        u = np.nan_to_num(u, nan=0.0, posinf=0.0, neginf=0.0)
    if u.size and float(np.max(np.abs(u))) > 1.0:
        issues.append("over_range")
        u = np.clip(u, -1.0, 1.0)
    return u.astype(np.float32), issues


def free_gib(path) -> float:
    st = os.statvfs(str(path))
    return st.f_bavail * st.f_frsize / 2**30


def write_wav(path, chans: list[np.ndarray]):
    """PCM16 WAV with the stdlib (no soundfile needed); chans = equal-length float arrays."""
    import wave
    x = np.stack([np.clip(np.nan_to_num(c), -1, 1) for c in chans], axis=1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(len(chans)); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def read_jsonl(path) -> tuple[list[dict], int]:
    """Tolerant JSONL reader: a torn last line (process killed mid-write) is counted, not fatal."""
    rows, bad = [], 0
    p = Path(path)
    if not p.exists():
        return rows, 0
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            bad += 1
    return rows, bad


def pct(a, q):
    a = np.asarray(a, float)
    return float(np.percentile(a, q)) if a.size else None


def popcount(v: int) -> int:
    return bin(v).count("1")

# ----------------------------------------------------------------------------- explicit state machines


class Turn(enum.Enum):
    IDLE = "idle"                  # both silent >= hangover: the only state where resets are allowed
    USER = "user_speaking"
    MODEL = "model_speaking"
    OVERLAP = "overlap"            # both voiced (barge-in or backchannel)


class TurnTracker:
    """VAD on both channels -> explicit turn state. Pure: next(user_dbfs, model_dbfs) -> Turn."""

    def __init__(self, threshold=VOICED_DBFS, hangover_frames=6):
        self.threshold, self.hang = threshold, hangover_frames
        self.state, self._u_quiet, self._m_quiet = Turn.IDLE, hangover_frames, hangover_frames

    def next(self, user_dbfs: float, model_dbfs: float) -> Turn:
        u, m = user_dbfs > self.threshold, model_dbfs > self.threshold
        self._u_quiet = 0 if u else self._u_quiet + 1
        self._m_quiet = 0 if m else self._m_quiet + 1
        ua, ma = self._u_quiet < self.hang, self._m_quiet < self.hang   # active incl. hangover
        self.state = Turn.OVERLAP if (ua and ma) else Turn.USER if ua else Turn.MODEL if ma else Turn.IDLE
        return self.state


class Wd(enum.Enum):
    OK = "ok"
    PENDING = "pending_restart"    # a soft fault: restart at the next IDLE
    RESTART = "restart_now"        # emitted once; the driver restarts and calls restarted()
    COOLDOWN = "cooldown"


@dataclass
class WatchdogConfig:
    loop_repeats: int = 3          # a token block repeated back to back this many times
    loop_min_period: int = 3
    latency_ms: float = 120.0      # hard: p95 over the last `latency_window` frames (a frame is 133 ms)
    latency_window: int = 225      # 30 s
    mem_gb: float = 14.0           # hard: MLX active memory
    silent_turns: int = 3          # soft: user turns in a row with < 1 s of voiced reply
    cooldown_frames: int = 450     # 60 s
    garbage_frames: int = 23       # soft: ~3 s of noise-like voiced audio in a row


class Watchdog:
    """Explicit state machine: OK -> PENDING (soft fault) -> RESTART (at IDLE) -> COOLDOWN -> OK.
    Hard faults go OK/PENDING -> RESTART immediately."""

    def __init__(self, cfg: WatchdogConfig):
        self.cfg, self.state, self.reason, self._cool = cfg, Wd.OK, None, 0
        self.lat = deque(maxlen=cfg.latency_window)

    def next(self, *, turn: Turn, step_ms: float, loop: tuple[int, int] | None, mem_gb: float | None,
             silent_turns: int, garbage_run: int) -> Wd:
        c = self.cfg
        self.lat.append(step_ms)
        if self.state == Wd.COOLDOWN:
            self._cool -= 1
            if self._cool <= 0:
                self.state = Wd.OK
            return self.state
        hard = None
        if len(self.lat) == self.lat.maxlen and float(np.percentile(self.lat, 95)) > c.latency_ms:
            hard = f"latency p95 {np.percentile(self.lat, 95):.1f} ms > {c.latency_ms}"
        if mem_gb is not None and mem_gb > c.mem_gb:
            hard = f"memory {mem_gb:.2f} GB > {c.mem_gb}"
        if hard:
            self.state, self.reason = Wd.RESTART, hard
            return self.state
        soft = None
        if loop and loop[1] >= c.loop_repeats and loop[0] >= c.loop_min_period:
            soft = f"loop period {loop[0]} x{loop[1]}"
        elif silent_turns >= c.silent_turns:
            soft = f"{silent_turns} unanswered turns"
        elif garbage_run >= c.garbage_frames:
            soft = f"{garbage_run} garbage frames"
        if soft and self.state == Wd.OK:
            self.state, self.reason = Wd.PENDING, soft
        if self.state == Wd.PENDING and turn == Turn.IDLE:
            self.state = Wd.RESTART
        return self.state

    def restarted(self):
        self.state, self._cool, self.lat = Wd.COOLDOWN, self.cfg.cooldown_frames, deque(maxlen=self.cfg.latency_window)

# ----------------------------------------------------------------------------- rolling KV truncation


class WindowedKVCache:
    """Drop-in for haru_mlx.models.qwen3_5.KVCache that keeps the prompt prefix + the last
    `window` positions (attention-sink style). Keys keep the RoPE rotation of their true
    position: `offset` (what Attention.attend passes to RoPE, qwen3_5.py L204-205) keeps
    counting; only the stored length is bounded. Compaction runs every `slack` positions.
    EXPERIMENTAL: Haru was not trained with evicted context; the soak measures the effect."""

    STEP = 256

    def __init__(self, src, prefix: int, window: int, xp, slack: int = 256):
        self.xp, self.prefix, self.window, self.slack = xp, prefix, window, slack
        self.keys, self.values = src.keys, src.values
        self.offset = src.offset       # absolute position (RoPE)
        self.length = src.offset       # positions stored
        self.evicted = 0

    def update_and_fetch(self, keys, values):
        xp = self.xp
        t = keys.shape[2]
        start, end = self.length, self.length + t
        cap = 0 if self.keys is None else self.keys.shape[2]
        if end > cap:
            extra = -(-(end - cap) // self.STEP) * self.STEP
            b, h, _, d = keys.shape
            block = xp.zeros((b, h, extra, d), dtype=keys.dtype)
            self.keys = block if self.keys is None else xp.concatenate([self.keys, block], axis=2)
            block = xp.zeros((b, h, extra, d), dtype=values.dtype)
            self.values = block if self.values is None else xp.concatenate([self.values, block], axis=2)
        self.keys[..., start:end, :] = keys
        self.values[..., start:end, :] = values
        self.length, self.offset = end, self.offset + t
        if self.length > self.prefix + self.window + self.slack:
            keep_from = self.length - self.window
            self.evicted += keep_from - self.prefix
            self.keys = xp.concatenate([self.keys[..., :self.prefix, :], self.keys[..., keep_from:self.length, :]], axis=2)
            self.values = xp.concatenate([self.values[..., :self.prefix, :], self.values[..., keep_from:self.length, :]], axis=2)
            self.length = self.prefix + self.window
        return self.keys[..., :self.length, :], self.values[..., :self.length, :]

    def arrays(self):
        return [] if self.keys is None else [self.keys, self.values]

# ----------------------------------------------------------------------------- script


TOPICS = {
    "en": [
        ("intro", ["Hi, I'm Sam. Nice to meet you. What's your name?", "Hello there, I'm Sam. Who am I talking to?", "Hey, I'm Sam. Tell me a bit about yourself."],
         ["name", "haru", "college", "student", "twenty"]),
        ("running", ["Do you do any sport? I try to run in the morning.", "I started running last month. Any tips?", "How far do you usually run?"],
         ["run", "running", "morning", "miles", "kilometers", "pace", "shoes"]),
        ("startups", ["What do you think about startups?", "Would you ever start your own company?", "Which startup idea excites you right now?"],
         ["startup", "company", "founder", "idea", "business", "product", "money"]),
        ("history", ["What period of history do you find most interesting?", "Do you like history? Which era?", "If you could visit any century, which one?"],
         ["history", "century", "war", "empire", "ancient", "roman", "revolution"]),
        ("economics", ["Why do prices keep going up?", "Is inflation good or bad?", "What do you think of interest rates right now?"],
         ["inflation", "prices", "rates", "economy", "money", "bank", "interest"]),
        ("food", ["What's your favourite food?", "Do you cook at all?", "What did you eat today?"],
         ["food", "cook", "eat", "dinner", "pasta", "rice", "favorite", "favourite"]),
        ("tech", ["What new technology are you excited about?", "Do you use AI tools for school?", "What phone do you have?"],
         ["technology", "ai", "phone", "computer", "app", "tool", "software"]),
        ("travel", ["Have you travelled anywhere nice?", "Where would you like to go next?", "Do you prefer the beach or the mountains?"],
         ["travel", "trip", "beach", "mountains", "country", "city", "visit"]),
        ("music", ["What kind of music do you listen to?", "Do you play an instrument?", "Any concert you'd love to see?"],
         ["music", "song", "band", "guitar", "piano", "concert", "listen"]),
        ("weekend", ["What are you doing this weekend?", "How do you relax after classes?", "What did you do last weekend?"],
         ["weekend", "friends", "relax", "movie", "sleep", "party", "saturday"]),
    ],
    "fr": [
        ("intro", ["Salut, moi c'est Sam. Et toi, comment tu t'appelles ?", "Bonjour, je suis Sam. Tu peux te présenter ?", "Enchanté, je m'appelle Sam. Tu fais quoi dans la vie ?"],
         ["haru", "appelle", "etudiant", "etudes", "ans", "fac"]),
        ("running", ["Tu fais du sport ? Moi j'essaie de courir le matin.", "J'ai commencé la course à pied. Tu as des conseils ?", "Tu cours combien de kilomètres en général ?"],
         ["courir", "course", "matin", "kilometres", "sport", "chaussures"]),
        ("startups", ["Tu penses quoi des startups ?", "Tu aimerais créer ton entreprise un jour ?", "Quelle idée de startup te plaît en ce moment ?"],
         ["startup", "entreprise", "idee", "creer", "produit", "argent", "business"]),
        ("history", ["Quelle période de l'histoire te passionne ?", "Tu aimes l'histoire ? Quelle époque ?", "Si tu pouvais visiter un siècle, lequel ?"],
         ["histoire", "siecle", "guerre", "empire", "romain", "revolution", "epoque"]),
        ("economics", ["Pourquoi les prix augmentent tout le temps ?", "L'inflation, c'est bien ou pas ?", "Tu penses quoi des taux d'intérêt en ce moment ?"],
         ["inflation", "prix", "taux", "economie", "argent", "banque", "interet"]),
        ("food", ["C'est quoi ton plat préféré ?", "Tu cuisines un peu ?", "Tu as mangé quoi aujourd'hui ?"],
         ["manger", "plat", "cuisine", "cuisiner", "pates", "prefere", "diner"]),
        ("tech", ["Quelle nouvelle technologie t'intéresse ?", "Tu utilises l'IA pour tes cours ?", "Tu as quel téléphone ?"],
         ["technologie", "ia", "telephone", "ordinateur", "application", "outil", "logiciel"]),
        ("travel", ["Tu as voyagé quelque part de sympa ?", "Tu aimerais partir où la prochaine fois ?", "Tu préfères la plage ou la montagne ?"],
         ["voyage", "voyager", "plage", "montagne", "pays", "ville", "visiter"]),
        ("music", ["Tu écoutes quel genre de musique ?", "Tu joues d'un instrument ?", "Un concert que tu rêves de voir ?"],
         ["musique", "chanson", "groupe", "guitare", "piano", "concert", "ecouter"]),
        ("weekend", ["Tu fais quoi ce week-end ?", "Comment tu te détends après les cours ?", "Tu as fait quoi le week-end dernier ?"],
         ["week", "amis", "detendre", "film", "dormir", "soiree", "samedi"]),
    ],
}


def script_turns(lang: str, seed: int = 0) -> list[dict]:
    """30 unique turns (10 topics x 3 paraphrases), deterministic order."""
    rng = random.Random(seed)
    turns = []
    for para in range(3):
        topics = list(TOPICS[lang])
        rng.shuffle(topics)
        for tid, qs, kws in topics:
            turns.append({"topic": tid, "text": qs[para], "keywords": kws})
    return turns


def build_timeline(turn_audio: list[np.ndarray], turns: list[dict], minutes: float, gap_s: float, lead_s: float = 1.0,
                   barge_every: int = 0, barge_after_s: float = 2.0, truncate_at_s: float | None = None):
    """User track for `minutes` of audio (turns cycle) + labels.
    barge_every N: after every Nth user turn the NEXT user turn starts `barge_after_s` into Haru's reply (a barge-in);
    that reply is labelled cut=True and the next turn barge=True. truncate_at_s: the first user turn starting at or
    after that time is cut off at 40 % of its audio (labelled truncated=True)."""
    total = int(minutes * 60 * SR) // FRAME * FRAME
    track = np.zeros(total, dtype=np.float32)
    labels = []
    pos, k, trunc_done, barge_next = int(lead_s * SR), 0, truncate_at_s is None, False
    while pos < total:
        i = k % len(turns)
        a = turn_audio[i]
        truncated = False
        if not trunc_done and pos >= truncate_at_s * SR:
            a, truncated, trunc_done = a[: int(a.size * 0.4)], True, True
        end_speech = min(total, pos + a.size)
        track[pos:end_speech] = a[: end_speech - pos]
        cut = bool(barge_every) and (k + 1) % barge_every == 0
        end_gap = min(total, end_speech + int((barge_after_s if cut else gap_s) * SR))
        labels.append({"start": pos, "end_speech": end_speech, "end_gap": end_gap, "turn": i, "cycle": k // len(turns), "k": k,
                       "cut": cut, "barge": barge_next, "truncated": truncated})
        barge_next = cut
        pos, k = end_gap, k + 1
    return track, labels


def cmd_make_script(a):
    if sys.platform != "darwin":
        sys.exit("make-script uses macOS `say` (built-in synthetic voices); run it on the Mac, or use --fake-audio")
    import soundfile as sf
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    turns = script_turns(a.lang, a.seed)
    voice = a.voice or {"fr": "Thomas", "en": "Samantha"}[a.lang]
    for i, t in enumerate(turns):
        p = out / f"turn_{i:02d}.wav"
        subprocess.run(["say", "-v", voice, "-o", str(p), "--file-format=WAVE", f"--data-format=LEI16@{SR}", t["text"]], check=True)
        x, sr = sf.read(str(p), dtype="float32", always_2d=True)
        assert sr == SR, sr
        t["file"], t["seconds"] = p.name, x.shape[0] / SR
    (out / "script.json").write_text(json.dumps({"lang": a.lang, "voice": voice, "seed": a.seed, "turns": turns}, ensure_ascii=False, indent=1))
    print(f"{len(turns)} turns -> {out}")


def load_script(d: Path, fake_audio: bool = False):
    if fake_audio:  # box / selftest: speech-like noise bursts instead of `say`
        lang = "en"
        turns = script_turns(lang)
        rng = np.random.default_rng(0)
        audio = []
        for t in turns:
            n = int((1.5 + 0.12 * len(t["text"].split())) * SR)
            env = np.abs(np.sin(np.linspace(0, math.pi * len(t["text"].split()) / 2, n)))
            audio.append((0.1 * env * rng.standard_normal(n)).astype(np.float32))
        return {"lang": lang, "turns": turns}, audio
    import soundfile as sf
    s = json.loads((d / "script.json").read_text(encoding="utf-8"))
    audio = [sf.read(str(d / t["file"]), dtype="float32")[0].reshape(-1) for t in s["turns"]]
    return s, audio

# ----------------------------------------------------------------------------- backends


@dataclass
class Step:
    audio: np.ndarray
    token: int
    text: str
    seconds: float


class HaruBackend:
    """The real model through the upstream Python API (pinned haru-speech-mlx 0.1.0)."""

    name = "haru"

    def __init__(self, a):
        import mlx.core as mx
        from haru_mlx.frames import DuplexConfig
        from haru_mlx.models import load_model
        from haru_mlx.sampling import DryConfig
        self.mx, self.a, self.DuplexConfig, self.DryConfig = mx, a, DuplexConfig, DryConfig
        if mx.metal.is_available():  # same as LocalBackend._load (backends.py L165-171)
            mx.set_wired_limit(mx.device_info()["max_recommended_working_set_size"])
        mx.set_cache_limit(1 << 30)
        t = time.perf_counter()
        self.model = load_model(a.model, quantize=None if a.quantize == "none" else int(a.quantize))
        self.load_seconds = time.perf_counter() - t
        self.silent = {self.model.config.pad_token_id, self.model.config.eop_token_id}
        self.system_prompt = Path(a.system_prompt_file).read_text(encoding="utf-8").strip() if a.system_prompt_file else ""
        self.session, self.restarts = None, 0

    def config(self, max_frames):
        a = self.a
        dry = None if a.dry == "off" else self.DryConfig(multiplier=a.dry_multiplier, lookback=a.dry_lookback)
        return self.DuplexConfig(guidance_scale=a.guidance_scale, temperature=a.temperature, top_k=a.top_k, top_p=a.top_p,
                                 dry=dry, eop_bias=a.eop_bias, max_frames=max_frames, seed=a.seed + self.restarts)

    def start(self, max_frames) -> Step:
        from haru_mlx.session import DuplexSession
        from haru_mlx.models.qwen3_5 import KVCache
        self.session = None
        gc.collect(); self.mx.clear_cache()
        self.session = DuplexSession(self.model, self.system_prompt, None, self.config(max_frames))
        f = self.session.start()
        if self.a.kv_window:
            # session._cache is private API of the pinned version (session.py L70, L92).
            c = self.session._cache
            for i, layer in enumerate(c):
                if isinstance(layer, KVCache):
                    c[i] = WindowedKVCache(layer, self.session.prompt_length, self.a.kv_window, self.mx)
        return Step(f.audio, f.token, f.text, f.seconds)

    def step(self, user: np.ndarray) -> Step:
        f = self.session.step(user)
        return Step(f.audio, f.token, f.text, f.seconds)

    def restart(self, max_frames) -> Step:
        self.restarts += 1
        return self.start(max_frames)

    def memory(self) -> dict:
        mx = self.mx
        get = lambda n: getattr(mx, n, None) or getattr(mx.metal, n, None)
        kv = sum(getattr(c, "length", getattr(c, "offset", 0)) for c in self.session._cache if hasattr(c, "offset")) if self.session else 0
        return {"mlx_active": get("get_active_memory")(), "mlx_peak": get("get_peak_memory")(), "mlx_cache": get("get_cache_memory")(),
                "kv_positions_stored": kv}


class FakeBackend:
    """Deterministic stand-in with injectable faults, for the selftest and for dry runs on the box.
    Speaks a templated on-topic answer in each reply gap; faults start at given minutes:
    loop (repeats one phrase forever), drift (step time grows), leak (memory grows), garbage (noise audio).
    A restart clears every fault (as a real fresh session would clear a loop)."""

    name = "fake"

    def __init__(self, a, script, labels):
        self.a, self.script, self.labels = a, script, labels
        self.load_seconds, self.restarts, self.k = 0.0, 0, 0
        self.silent = {0}
        self._leak, self._queue, self._fault_cleared_at = [], deque(), -1
        self.rng = np.random.default_rng(a.seed)
        self.vocab = {}

    def _tok(self, w):
        return self.vocab.setdefault(w, len(self.vocab) + 1)

    def _minute(self):
        return self.k * FRAME_S / 60

    def _active(self, at):
        return at is not None and at >= 0 and self._minute() >= at and self._fault_cleared_at < at * 60 / FRAME_S

    def start(self, max_frames):
        self._queue.clear()
        return Step(np.zeros(FRAME, np.float32), 0, "", 0.001)

    def restart(self, max_frames):
        self.restarts += 1
        self._fault_cleared_at, self._leak = self.k, []
        return self.start(max_frames)

    def step(self, user):
        if np.asarray(user).size != FRAME:
            raise ValueError(f"fake backend: frame of {np.asarray(user).size} samples, expected {FRAME}")
        self.k += 1
        a = self.a
        sample = self.k * FRAME
        lab = next((l for l in self.labels if l["end_speech"] <= sample < l["end_gap"]), None)
        if lab and 4 * FRAME <= sample - lab["end_speech"] < 5 * FRAME and not self._queue:   # answer after ~0.5 s
            t = self.script["turns"][lab["turn"]]
            kws = t["keywords"]
            phrase = f"well about {t['topic']} I think {kws[lab['k'] % len(kws)]} and {kws[(lab['k'] + 1) % len(kws)]} matter a lot to me"
            if self._active(a.fake_loop_at):
                phrase = " ".join(["and then I"] * 12)
            self._queue.extend(phrase.split())
        secs = 0.080 + (a.fake_drift_ms_per_min * self._minute() / 1000 if self._active(a.fake_drift_at) else 0.0)
        if self._active(a.fake_leak_at):
            self._leak.append(np.ones(int(a.fake_leak_mb_per_min * 2**20 / 450 / 8)))  # per frame, float64
        if lab is None:
            self._queue.clear()          # the user took the floor: a cut reply is dropped, not resumed later
        speaking = bool(self._queue) and lab is not None
        word = self._queue.popleft() if speaking else ""
        if speaking:
            tt = np.arange(FRAME) / SR
            audio = (0.1 * np.sin(2 * np.pi * 180 * tt)).astype(np.float32)
            if self._active(a.fake_garbage_at):
                audio = (0.3 * self.rng.standard_normal(FRAME)).astype(np.float32)
        else:
            audio = np.zeros(FRAME, np.float32)
        return Step(audio, self._tok(word) if word else 0, (" " + word) if word else "", secs)

    def memory(self):
        return {"mlx_active": sum(x.nbytes for x in self._leak), "mlx_peak": None, "mlx_cache": None, "kv_positions_stored": self.k}

# ----------------------------------------------------------------------------- run


def rss_bytes():
    try:
        with open("/proc/self/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1]) * 1024
    except FileNotFoundError:
        pass
    r = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss  # macOS: bytes (peak; current via ps below)
    try:
        return int(subprocess.run(["ps", "-o", "rss=", "-p", str(os.getpid())], capture_output=True, text=True).stdout) * 1024
    except Exception:
        return r


INJECTIONS = ("none", "bad_frame", "bad_frame_raw", "garbage_input", "truncated_input", "stall", "loop", "latency", "disk_low")
LOOP_TOKENS, LOOP_WORDS = (900001, 900002, 900003), ("and", "then", "I")


def sample_windows(n_frames: int, seconds: float) -> dict:
    """start / middle / end listening windows (frame index ranges), non-overlapping; fewer for short runs."""
    w = int(seconds / FRAME_S)
    if w <= 0 or n_frames < w + 4:
        return {}
    s0 = min(int(30 / FRAME_S), max(0, n_frames - w - 1))      # start: from 0:30 (skip the greeting/warm-up)
    out = {"start": (s0, s0 + w)}
    mid = (n_frames // 2 - w // 2, n_frames // 2 - w // 2 + w)
    end = (n_frames - 1 - w, n_frames - 1)
    if mid[0] >= out["start"][1]:
        out["middle"] = mid
    if end[0] >= max(r[1] for r in out.values()):
        out["end"] = end
    return out


def cmd_run(a):
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    ef = open(out / "events.jsonl", "w")
    wall0 = time.perf_counter()

    def event(_ev, k, **kw):
        ef.write(json.dumps({"k": k, "min": round(k * FRAME_S / 60, 3), "wall_s": round(time.perf_counter() - wall0, 3),
                             "event": _ev, **kw}) + "\n"); ef.flush()

    fg = free_gib(out)
    if fg < a.min_free_gib:      # disk-low guard, before anything heavy (model load, logs)
        event("disk_low", 0, free_gib=round(fg, 2), min_free_gib=a.min_free_gib, where="start")
        ef.close(); print(json.dumps({"aborted": "disk_low", "free_gib": fg})); sys.exit(3)
    script, turn_audio = load_script(Path(a.script) if a.script else None, a.fake_audio)
    inj = a.inject
    user, labels = build_timeline(turn_audio, script["turns"], a.minutes, a.gap, barge_every=a.barge_in_every,
                                  truncate_at_s=60 * a.inject_at if inj == "truncated_input" else None)
    n_frames = user.size // FRAME
    k_inj = max(1, int(60 * a.inject_at / FRAME_S)) if inj != "none" else -1
    backend = FakeBackend(a, script, labels) if a.backend == "fake" else HaruBackend(a)
    wd = Watchdog(WatchdogConfig(latency_ms=a.wd_latency_ms, mem_gb=a.wd_mem_gb, loop_repeats=a.wd_loop_repeats)) if a.watchdog else None
    tracker = TurnTracker()
    windows = sample_windows(n_frames, a.sample_seconds)
    meta = {"args": vars(a), "backend": backend.name, "frames": n_frames, "minutes": a.minutes, "load_seconds": backend.load_seconds,
            "labels": labels, "script": script, "mitigation_knobs": MITIGATIONS, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "inject": {"kind": inj, "frame": k_inj, "minute": a.inject_at if inj != "none" else None},
            "sample_windows": {kk: [v[0], v[1]] for kk, v in windows.items()}, "sub_window_samples": SUB, "harness_version": 2}
    if backend.name == "haru":
        import haru_mlx, mlx.core as mx
        meta.update(haru_mlx=haru_mlx.__version__, mlx=mx.__version__)
    (out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    ff = open(out / "frames.jsonl", "w"); mf = open(out / "mem.jsonl", "w")
    reply = np.zeros(n_frames * FRAME, np.float32) if a.save_audio else None
    caps = {kk: ([], []) for kk in windows}

    max_frames = n_frames + 2
    first = backend.start(max_frames)
    event("start", 0, prompt_seconds=first.seconds)
    tokens = deque(maxlen=256)
    last_mem = -1e9
    session_start_k, last_anchor_k = 0, 0
    silent_turns, garbage_run, voiced_in_gap = 0, 0, 0
    lab_i, errors, aborted = 0, 0, None
    inj_active, inj_cleared = False, False         # loop / latency injections last until the next restart
    awaiting_recovery = False
    rng = np.random.default_rng(1234)
    for k in range(n_frames - 1):
        if a.pace == "realtime":
            due = wall0 + (k + 1) * FRAME_S
            while time.perf_counter() < due:
                time.sleep(min(0.002, max(0.0, due - time.perf_counter())))
        u = user[k * FRAME:(k + 1) * FRAME]
        guard = not a.no_input_guard
        # ---------------------------------------------------------------- fault injection (explicit cases)
        if k == k_inj and inj in ("bad_frame", "bad_frame_raw", "garbage_input", "stall", "loop", "latency", "disk_low"):
            event("inject", k + 1, kind=inj)
            awaiting_recovery = True
        if inj in ("bad_frame", "bad_frame_raw") and k in (k_inj, k_inj + 1):
            u = u[:FRAME - 200] if k == k_inj else np.concatenate([u, u])      # one short frame, then one double frame
            guard = inj == "bad_frame"
        if inj == "garbage_input" and k_inj <= k < k_inj + int(3 / FRAME_S):
            u = (0.9 * rng.standard_normal(FRAME)).astype(np.float32)
            if k == k_inj + 5:
                u[::7] = np.nan
            if k == k_inj + 6:
                u[::11] = np.inf
            if k == k_inj + 7:
                u = u * 4.0
            if k == k_inj + int(3 / FRAME_S) - 1:
                event("inject_end", k + 1, kind=inj)
        if inj == "stall" and k == k_inj:
            time.sleep(a.stall_s)
            event("stall_end", k + 1, stall_s=a.stall_s)
        if inj in ("loop", "latency") and k == k_inj and not inj_cleared:
            inj_active = True
        if inj == "disk_low" and k == k_inj:
            a.min_free_gib = 1e9                    # simulated: the threshold jumps above any real free space
        if guard:
            u, issues = sanitize(u)
            if issues:
                event("input_fixed", k + 1, issues=issues)
        t0 = time.perf_counter()
        try:
            st = backend.step(u)
        except Exception as e:                        # recovery path: log, restart the session, continue
            errors += 1
            event("step_error", k + 1, error=f"{type(e).__name__}: {e}"[:300])
            awaiting_recovery = True
            if errors > 5:
                aborted = "too many step errors"; event("abort", k + 1, reason=aborted); break
            t = time.perf_counter(); f0r = backend.restart(max_frames)
            event("restart", k + 1, reason="step error", turn=tracker.state.value, prompt_seconds=round(f0r.seconds, 3),
                  wall_seconds=round(time.perf_counter() - t, 3), session_frames=k + 1 - session_start_k)
            session_start_k = last_anchor_k = k + 1
            tokens.clear(); silent_turns = garbage_run = 0
            if wd:
                wd.restarted()
            st = Step(np.zeros(FRAME, np.float32), next(iter(backend.silent)), "", 0.0)
            ff.write(json.dumps({"k": k + 1, "ms": None, "wall_ms": round(1000 * (time.perf_counter() - t0), 3), "tok": int(st.token),
                                 "text": "", "m_db": -120.0, "u_db": round(dbfs(np.nan_to_num(np.asarray(u, np.float32))), 1),
                                 "turn": tracker.state.value, "flat": 0.0, "garbage": False, "finite": True, "error": True,
                                 "vm": 0, "uvm": 0, "f0": 0.0, "clip": 0.0}) + "\n")
            continue
        wall_ms = 1000 * (time.perf_counter() - t0)
        if inj_active and inj == "loop":
            st = Step(st.audio, LOOP_TOKENS[k % 3], " " + LOOP_WORDS[k % 3], st.seconds)
        if inj_active and inj == "latency":
            st = Step(st.audio, st.token, st.text, st.seconds + a.inject_latency_ms / 1000)   # simulated, no real sleep
        audio = np.asarray(st.audio, np.float32).reshape(-1)
        if reply is not None and audio.size == FRAME:
            reply[(k + 1) * FRAME:(k + 2) * FRAME] = audio
        uu = np.nan_to_num(np.asarray(u, np.float32).reshape(-1))
        u_db, m_db = dbfs(uu), dbfs(np.nan_to_num(audio))
        finite = bool(np.isfinite(audio).all()) and audio.size == FRAME
        flat = spectral_flatness(audio) if m_db > VOICED_DBFS and finite else 0.0
        clip = float(np.mean(np.abs(audio) >= 0.999)) if audio.size else 0.0
        garbage = (not finite) or (m_db > VOICED_DBFS and flat > 0.5) or clip > 0.01
        garbage_run = garbage_run + 1 if garbage else 0
        vm = voiced_mask(np.nan_to_num(audio)) if finite else 0
        f0 = f0_autocorr(audio) if finite and vm else 0.0
        for kk, (r0, r1) in windows.items():
            if r0 <= k < r1:
                uc = uu[:FRAME] if uu.size >= FRAME else np.pad(uu, (0, FRAME - uu.size))
                ac = audio if audio.size == FRAME else np.zeros(FRAME, np.float32)
                caps[kk][0].append(uc); caps[kk][1].append(ac)
        turn = tracker.next(u_db, m_db)
        if st.token not in backend.silent:
            tokens.append(st.token)
        loop = find_loop(list(tokens), min_period=2, max_period=32, min_repeats=3) if st.text else None
        sample = (k + 1) * FRAME
        while lab_i < len(labels) and sample >= labels[lab_i]["end_gap"]:
            if not labels[lab_i].get("cut"):
                silent_turns = silent_turns + 1 if voiced_in_gap * FRAME_S < 1.0 else 0
            voiced_in_gap, lab_i = 0, lab_i + 1
        if lab_i < len(labels) and labels[lab_i]["end_speech"] <= sample < labels[lab_i]["end_gap"] and m_db > VOICED_DBFS:
            voiced_in_gap += 1
        ff.write(json.dumps({"k": k + 1, "ms": round(1000 * st.seconds, 3), "wall_ms": round(wall_ms, 3), "tok": int(st.token),
                             "text": st.text, "m_db": round(m_db, 1), "u_db": round(u_db, 1), "turn": turn.value,
                             "flat": round(flat, 3), "garbage": garbage, "finite": finite,
                             "vm": vm, "uvm": voiced_mask(uu[:FRAME]), "f0": round(f0, 1), "clip": round(clip, 4)}, ensure_ascii=False) + "\n")
        if awaiting_recovery and finite and not garbage and not inj_active and (inj != "garbage_input" or k >= k_inj + int(3 / FRAME_S)):
            event("recovered", k + 1, step_ms=round(1000 * st.seconds, 3))
            awaiting_recovery = False
        now = time.perf_counter()
        mem = None
        if now - last_mem >= a.mem_every or k == n_frames - 2:
            m = backend.memory(); m.update(k=k + 1, min=round((k + 1) * FRAME_S / 60, 3), rss=rss_bytes(), wall_s=round(now - wall0, 2))
            mf.write(json.dumps(m) + "\n"); mf.flush(); last_mem = now
            mem = (m["mlx_active"] or 0) / 1e9
        if (k + 1) % 450 == 0 or k == k_inj:
            fg = free_gib(out)
            if fg < a.min_free_gib:
                aborted = "disk_low"
                event("disk_low", k + 1, free_gib=round(fg, 2), min_free_gib=a.min_free_gib, where="run")
                break
        if loop and loop[1] >= 3:
            event("loop", k + 1, period=loop[0], repeats=loop[1])
            tokens.clear()
        restart_reason = None
        if wd:
            s_ = wd.next(turn=turn, step_ms=1000 * st.seconds, loop=loop, mem_gb=mem, silent_turns=silent_turns, garbage_run=garbage_run)
            if s_ == Wd.PENDING and not getattr(wd, "_logged_pending", False):
                event("watchdog_pending", k + 1, reason=wd.reason, turn=turn.value); wd._logged_pending = True
            if s_ == Wd.RESTART:
                restart_reason = "watchdog: " + str(wd.reason)
        if not restart_reason and a.reanchor_minutes and turn == Turn.IDLE and (k + 1 - last_anchor_k) * FRAME_S >= 60 * a.reanchor_minutes:
            restart_reason = f"re-anchor every {a.reanchor_minutes} min"
        if restart_reason:
            t = time.perf_counter()
            f0r = backend.restart(max_frames)
            event("restart", k + 1, reason=restart_reason, turn=turn.value, prompt_seconds=round(f0r.seconds, 3),
                  wall_seconds=round(time.perf_counter() - t, 3), session_frames=k + 1 - session_start_k)
            session_start_k = last_anchor_k = k + 1
            tokens.clear(); silent_turns = garbage_run = 0
            if inj_active:
                inj_active, inj_cleared = False, True
            if wd:
                wd.restarted(); wd._logged_pending = False
    ff.close(); mf.close()
    for kk, (uc, ac) in caps.items():
        if uc:
            write_wav(out / f"sample_{kk}.wav", [np.concatenate(uc), np.concatenate(ac)])
    if reply is not None:
        write_wav(out / "reply.wav", [reply])
    event("end", n_frames, aborted=aborted, step_errors=errors)
    ef.close()
    res = analyze(out)
    print(json.dumps({"run": str(out), "aborted": aborted, "frames": len(res.get("checkpoints", {})) and n_frames}, indent=1))
    if aborted == "disk_low":
        sys.exit(3)
    if aborted:
        sys.exit(4)

# ----------------------------------------------------------------------------- analyze


def _runs(bits: list[int]) -> list[tuple[int, int, int]]:
    """(value, start, length) runs of a 0/1 list."""
    out, i = [], 0
    while i < len(bits):
        j = i
        while j < len(bits) and bits[j] == bits[i]:
            j += 1
        out.append((bits[i], i, j - i)); i = j
    return out


def _subbits(frames, key="vm", k0=0, k1=None) -> list[int]:
    """Expand per-frame 8-bit voiced masks to a 16.7 ms-resolution 0/1 list for frames[k0:k1]."""
    per = FRAME // SUB
    out = []
    for f in frames[k0:k1]:
        v = f.get(key, 0) or 0
        out.extend((v >> i) & 1 for i in range(per))
    return out


def _dist(xs) -> dict:
    xs = [x for x in xs if x is not None]
    return {"n": len(xs), "p50": pct(xs, 50), "p90": pct(xs, 90), "p95": pct(xs, 95), "max": float(max(xs)) if xs else None,
            "mean": float(np.mean(xs)) if xs else None}


def turn_metrics(meta, frames) -> list[dict]:
    """Per scripted user turn: reply gap (first-audio latency), barge-in yield, and reply prosody proxies."""
    labels = meta["labels"]
    per = FRAME // SUB
    nf = len(frames)
    rows = []
    for li, lab in enumerate(labels):
        k_end = lab["end_speech"] // FRAME              # frame index (0-based into frames[]) where the user stopped
        k_next = (labels[li + 1]["start"] // FRAME) if li + 1 < len(labels) else nf
        if k_end >= nf:
            break
        k_next = min(k_next, nf)
        bits = _subbits(frames, "vm", k_end, k_next)
        off = (lab["end_speech"] - k_end * FRAME) // SUB  # sub-window offset of the user end inside frame k_end
        bits_after = bits[off:]
        # model already talking when the user stopped (overlap) -> gap 0 if voiced in the first sub-window
        first = next((i for i, b in enumerate(bits_after) if b), None)
        gap_s = first * SUB_S if first is not None else None
        voiced_s = sum(bits_after) * SUB_S
        seg = frames[k_end:k_next]
        txt = "".join(f.get("text", "") for f in seg)
        nw = len(words(txt))
        # pauses inside the reply: unvoiced runs between the first and last voiced sub-window, >= 100 ms
        pauses = []
        if first is not None:
            last = len(bits_after) - 1 - next(i for i, b in enumerate(reversed(bits_after)) if b)
            for v, st, ln in _runs(bits_after[first:last + 1]):
                if v == 0 and ln * SUB_S >= 0.1:
                    pauses.append(ln * SUB_S)
        f0s = [f["f0"] for f in seg if f.get("f0")]
        vdb = [f["m_db"] for f in seg if f["m_db"] > VOICED_DBFS]
        row = {"k": lab["k"], "cut": bool(lab.get("cut")), "barge": bool(lab.get("barge")), "truncated": bool(lab.get("truncated")),
               "user_end_min": round(lab["end_speech"] / SR / 60, 3), "reply_gap_s": gap_s, "voiced_s": round(voiced_s, 3),
               "words": nw, "speaking_rate_wps": (nw / voiced_s) if voiced_s >= 1.0 and nw else None,
               "pauses_s": [round(x, 3) for x in pauses], "f0_median_hz": float(np.median(f0s)) if f0s else None,
               "f0_range_st": float(12 * np.log2(np.percentile(f0s, 95) / np.percentile(f0s, 5))) if len(f0s) >= 4 else None,
               "energy_std_db": float(np.std(vdb)) if len(vdb) >= 4 else None}
        if lab.get("barge"):
            # barge-in: the user starts while Haru talks. yield = time from user start until Haru is silent >= 200 ms.
            ks = max(0, lab["start"] // FRAME - 3)
            kb = min(nf, lab["start"] // FRAME + int(5 / FRAME_S))
            b2 = _subbits(frames, "vm", ks, kb)
            o2 = (lab["start"] - ks * FRAME) // SUB
            talking = any(b2[max(0, o2 - int(0.3 / SUB_S)):o2 + 1])     # Haru voiced in the 300 ms before the user barged in
            need = int(0.2 / SUB_S)
            y = None
            if talking:
                for i in range(len(b2) - o2 - need + 1):
                    if not any(b2[o2 + i:o2 + i + need]):
                        y = i * SUB_S; break
            row.update(barge_model_talking=talking, barge_yield_s=y if talking else 0.0, barge_yielded=(y is not None and y <= 2.0) if talking else True)
        rows.append(row)
    return rows


def naturalness(frames, turns_rows, k0=0, k1=None) -> dict:
    """Objective prosody PROXIES (not MOS) over frames[k0:k1] and the turns whose user end falls inside."""
    fr = [f for f in frames[k0:k1] if f.get("ms") is not None]
    if not fr:
        return {}
    voiced = [f for f in fr if f["m_db"] > VOICED_DBFS]
    f0 = np.array([f["f0"] for f in voiced if f.get("f0")], float)
    vdb = np.array([f["m_db"] for f in voiced], float)
    lo_min = (k0 + 1) * FRAME_S / 60; hi_min = ((k1 if k1 is not None else len(frames)) + 1) * FRAME_S / 60
    tr = [t for t in turns_rows if lo_min <= t["user_end_min"] < hi_min]
    pauses = [p for t in tr if not t["cut"] for p in t["pauses_s"]]
    speech_s = sum(t["voiced_s"] for t in tr if not t["cut"])
    rates = [t["speaking_rate_wps"] for t in tr if t["speaking_rate_wps"]]
    barge = [t for t in tr if t["barge"]]
    talking = [t for t in barge if t.get("barge_model_talking")]
    return {
        "label": "objective proxies computed with numpy from Haru's output audio; NOT a MOS / listening score",
        "pause_s": {**_dist(pauses), "per_min_speech": (len(pauses) / (speech_s / 60)) if speech_s > 5 else None,
                    "long_pause_gt_1_5s_rate": float(np.mean([p > 1.5 for p in pauses])) if pauses else None},
        "speaking_rate_wps": _dist(rates),
        "f0": {"voiced_frames_with_f0": int(f0.size), "voiced_frames": len(voiced),
               "median_hz": float(np.median(f0)) if f0.size else None,
               "range_st_p5_p95": float(12 * np.log2(np.percentile(f0, 95) / np.percentile(f0, 5))) if f0.size >= 4 else None,
               "std_st": float(np.std(12 * np.log2(f0 / np.median(f0)))) if f0.size >= 4 else None,
               "per_turn_range_st_median": pct([t["f0_range_st"] for t in tr if t["f0_range_st"] is not None], 50)},
        "energy": {"voiced_db_p10": pct(vdb, 10), "voiced_db_p95": pct(vdb, 95),
                   "dynamic_range_db": (pct(vdb, 95) - pct(vdb, 10)) if vdb.size else None, "voiced_db_std": float(np.std(vdb)) if vdb.size else None,
                   "per_turn_std_db_median": pct([t["energy_std_db"] for t in tr if t["energy_std_db"] is not None], 50)},
        "clipping_frame_ratio": float(np.mean([(f.get("clip") or 0) > 0.001 for f in fr])),
        "silence_ratio": float(np.mean([f["m_db"] <= VOICED_DBFS for f in fr])),
        "garbage_ratio": float(np.mean([f["garbage"] for f in fr])),
        "turn_taking": {"reply_gap_s": _dist([t["reply_gap_s"] for t in tr if not t["cut"]]),
                        "no_reply_turns": sum(1 for t in tr if not t["cut"] and t["reply_gap_s"] is None),
                        "overlap_start_turns": sum(1 for t in tr if t["reply_gap_s"] == 0.0),
                        "barge_ins": len(barge), "barge_ins_model_talking": len(talking),
                        "barge_yield_s": _dist([t.get("barge_yield_s") for t in talking]),
                        "barge_yield_rate_le_2s": float(np.mean([t["barge_yielded"] for t in talking])) if talking else None},
    }


def deep_metrics(meta, frames, mem, events, run: Path) -> dict:
    """Latency per 5-min window, first-audio latency, naturalness proxies (whole run + thirds), sample WAV index."""
    turns_rows = turn_metrics(meta, frames) if frames and "vm" in frames[-1] else []
    win_frames = int(300 / FRAME_S)
    windows = []
    for w0 in range(0, len(frames), win_frames):
        fr = [f for f in frames[w0:w0 + win_frames] if f.get("ms") is not None and f["k"] > 16]
        if not fr:
            continue
        ms = np.array([f["ms"] for f in fr]); wall = np.array([f["wall_ms"] for f in fr])
        t0m, t1m = w0 * FRAME_S / 60, min(len(frames), w0 + win_frames) * FRAME_S / 60
        tr = [t for t in turns_rows if t0m <= t["user_end_min"] < t1m and not t["cut"]]
        mm = [m for m in mem if t0m <= m["min"] < t1m + 1e-9]
        windows.append({"t0_min": round(t0m, 3), "t1_min": round(t1m, 3), "frames": len(fr),
                        "p50_ms": pct(ms, 50), "p95_ms": pct(ms, 95), "p99_ms": pct(ms, 99), "max_ms": float(ms.max()),
                        "wall_p50_ms": pct(wall, 50), "wall_p99_ms": pct(wall, 99),
                        "rtf_model": float(ms.sum() / (1000 * FRAME_S * ms.size)), "rtf_wall": float(wall.sum() / (1000 * FRAME_S * wall.size)),
                        "frames_over_133ms": int((ms > 1000 * FRAME_S).sum()),
                        "first_audio_s": _dist([t["reply_gap_s"] for t in tr]),
                        "no_reply_turns": sum(1 for t in tr if t["reply_gap_s"] is None),
                        "garbage_ratio": float(np.mean([f["garbage"] for f in fr])),
                        "voiced_ratio": float(np.mean([f["m_db"] > VOICED_DBFS for f in fr])),
                        "mlx_active_gb_end": ((mm[-1].get("mlx_active") or 0) / 1e9) if mm else None,
                        "rss_mb_end": (mm[-1]["rss"] / 2**20) if mm else None,
                        "restarts": sum(1 for e in events if e["event"] == "restart" and t0m <= e["min"] < t1m)})
    n = len(frames)
    thirds = {}
    if turns_rows:
        for name, (a_, b_) in {"first_third": (0, n // 3), "middle_third": (n // 3, 2 * n // 3), "last_third": (2 * n // 3, n)}.items():
            thirds[name] = naturalness(frames, turns_rows, a_, b_)
    samples = []
    for kk, (r0, r1) in (meta.get("sample_windows") or {}).items():
        pth = run / f"sample_{kk}.wav"
        if pth.exists():
            import hashlib
            samples.append({"position": kk, "file": pth.name, "from_min": round(r0 * FRAME_S / 60, 3), "to_min": round(r1 * FRAME_S / 60, 3),
                            "sha256": hashlib.sha256(pth.read_bytes()).hexdigest(), "channels": "L=user (synthetic), R=Haru"})
    lat_all = [f["ms"] for f in frames if f.get("ms") is not None and f["k"] > 16]
    return {"latency_overall": {"p50_ms": pct(lat_all, 50), "p95_ms": pct(lat_all, 95), "p99_ms": pct(lat_all, 99),
                                "max_ms": float(max(lat_all)) if lat_all else None,
                                "drift_ms_per_min": ols_slope([f["k"] * FRAME_S / 60 for f in frames if f.get("ms") is not None and f["k"] > 16], lat_all)},
            "latency_windows_5min": windows,
            "first_audio_latency_s": _dist([t["reply_gap_s"] for t in turns_rows if not t["cut"]]),
            "naturalness_proxies": {"whole_run": naturalness(frames, turns_rows) if turns_rows else {}, **thirds},
            "turns": turns_rows, "samples": samples}



def analyze(run: Path, write=True) -> dict:
    meta = json.loads((run / "meta.json").read_text(encoding="utf-8"))
    frames, torn_f = read_jsonl(run / "frames.jsonl")
    assert all(f["k"] == i + 1 for i, f in enumerate(frames)), "frames.jsonl must be contiguous from k=1"
    mem, torn_m = read_jsonl(run / "mem.jsonl")
    events, torn_e = read_jsonl(run / "events.jsonl")
    labels, turns = meta["labels"], meta["script"]["turns"]
    refs = [f"{t['text']} {' '.join(t['keywords'])} {t['topic']}" for t in turns]
    tfidf = TfIdf(refs + [t["topic"] for t in turns])
    ref_vecs = [tfidf.vec(r) for r in refs]
    topic_of = [t["topic"] for t in turns]
    out = {"run": str(run), "backend": meta["backend"], "minutes": meta["minutes"], "args": {k: meta["args"][k] for k in (
        "temperature", "top_k", "top_p", "guidance_scale", "eop_bias", "dry", "kv_window", "reanchor_minutes", "watchdog", "quantize", "seed")},
        "checkpoints": {}, "frames_logged": len(frames), "torn_lines": {"frames": torn_f, "mem": torn_m, "events": torn_e}}
    restarts = [e for e in events if e["event"] == "restart"]
    loops = [e for e in events if e["event"] == "loop"]
    per_turn = []  # a warm-up-only run never enters the checkpoint body; replies.jsonl is then empty
    for cp in sorted({m for m in (10, 30, 60) if m <= meta["minutes"] + 1e-9} | {meta["minutes"]}):
        kmax = int(cp * 60 / FRAME_S)
        fr = [f for f in frames if f["k"] <= kmax and f["k"] > 16 and f.get("ms") is not None]  # skip warm-up + error frames
        if not fr:
            continue
        ms = np.array([f["ms"] for f in fr]); mins = np.array([f["k"] * FRAME_S / 60 for f in fr])
        last = ms[mins > cp - 1]; first = ms[mins <= 1]
        mm = [m for m in mem if m["k"] <= kmax]
        # replies per scripted turn: model text from the gap start to the next turn's start
        per_turn = []
        for li, lab in enumerate(labels):
            if lab["end_speech"] >= kmax * FRAME:
                break
            k0 = lab["end_speech"] // FRAME; k1 = (labels[li + 1]["start"] // FRAME) if li + 1 < len(labels) else kmax
            seg = frames[k0:min(k1, kmax)]  # frames[i]["k"] == i + 1
            txt = "".join(f["text"] for f in seg)
            voiced = sum(1 for f in seg if f["m_db"] > VOICED_DBFS) * FRAME_S
            v = tfidf.vec(txt)
            own = TfIdf.cos(v, ref_vecs[lab["turn"]])
            others = [TfIdf.cos(v, ref_vecs[j]) for j in range(len(turns)) if topic_of[j] != topic_of[lab["turn"]]]
            kw = set(fold(w) for w in turns[lab["turn"]]["keywords"])
            hit = bool(kw & set(words(txt)))
            per_turn.append({"k": lab["k"], "topic": topic_of[lab["turn"]], "voiced_s": voiced, "text": txt.strip(), "kw_hit": hit,
                             "cut": bool(lab.get("cut")), "truncated": bool(lab.get("truncated")),
                             "margin": own - (float(np.mean(others)) if others else 0.0), "words": len(words(txt))})
        full = [p for p in per_turn if not p["cut"]]          # replies not cut short by a scripted barge-in
        answered = [p for p in full if p["voiced_s"] >= 1.0]
        all_words = words("".join(f["text"] for f in fr))
        win = [repeated_ngram_ratio(all_words[i:i + 100], 3) for i in range(0, max(1, len(all_words) - 99), 50)]
        consec = [len(set(zip(*[words(a["text"])[i:] for i in range(4)])) & set(zip(*[words(b["text"])[i:] for i in range(4)])))
                  / max(1, len(set(zip(*[words(b["text"])[i:] for i in range(4)])))) for a, b in zip(per_turn, per_turn[1:])]
        user_frames = [f for f in fr if f["u_db"] > VOICED_DBFS]
        def half_rate(sel):
            return float(np.mean([p["kw_hit"] for p in sel])) if sel else None
        n = len(full)
        wall = np.array([f["wall_ms"] for f in fr])
        out["checkpoints"][f"{cp:g}min"] = {
            "frames": len(fr),
            "latency": {"p50_ms": float(np.percentile(ms, 50)), "p95_ms": float(np.percentile(ms, 95)), "p99_ms": float(np.percentile(ms, 99)), "max_ms": float(ms.max()),
                        "rtf_model": float(ms.sum() / (1000 * FRAME_S * ms.size)), "rtf_wall": float(wall.sum() / (1000 * FRAME_S * wall.size)),
                        "first_min_p50_ms": float(np.median(first)) if first.size else None, "last_min_p50_ms": float(np.median(last)) if last.size else None,
                        "drift_ms_per_min": ols_slope(mins, ms), "frames_over_133ms": int((ms > 1000 * FRAME_S).sum())},
            "memory": {"rss_mb_per_min": ols_slope([m["min"] for m in mm], [m["rss"] / 2**20 for m in mm]) if len(mm) > 1 else None,
                       "mlx_active_mb_per_min": ols_slope([m["min"] for m in mm], [(m["mlx_active"] or 0) / 2**20 for m in mm]) if len(mm) > 1 else None,
                       "rss_mb_end": mm[-1]["rss"] / 2**20 if mm else None, "mlx_active_gb_end": (mm[-1]["mlx_active"] or 0) / 1e9 if mm else None,
                       "kv_positions_end": mm[-1]["kv_positions_stored"] if mm else None},
            "repetition": {"repeated_3gram_ratio_median": float(np.median(win)) if win else 0.0, "repeated_3gram_ratio_max": float(max(win)) if win else 0.0,
                           "loop_events": sum(1 for e in loops if e["k"] <= kmax), "consecutive_reply_4gram_overlap_median": float(np.median(consec)) if consec else 0.0},
            "on_topic": {"turns": n, "keyword_hit_rate": half_rate(answered), "tfidf_margin_positive_rate": float(np.mean([p["margin"] > 0 for p in answered])) if answered else None,
                         "keyword_hit_rate_first_half": half_rate([p for p in answered if p["k"] < n / 2]),
                         "keyword_hit_rate_second_half": half_rate([p for p in answered if p["k"] >= n / 2])},
            "responsiveness": {"answered_turn_rate": len(answered) / n if n else None,
                               "talk_over_ratio": float(np.mean([f["m_db"] > VOICED_DBFS for f in user_frames])) if user_frames else None},
            "audio": {"garbage_frame_ratio": float(np.mean([f["garbage"] for f in fr])), "nonfinite_frames": sum(1 for f in fr if not f["finite"]),
                      "voiced_frame_ratio": float(np.mean([f["m_db"] > VOICED_DBFS for f in fr]))},
            "restarts": sum(1 for e in restarts if e["k"] <= kmax),
        }
    out["restart_events"] = restarts
    out["events_summary"] = dict(Counter(e["event"] for e in events))
    out.update(deep_metrics(meta, frames, mem, events, run))
    if write:
        (run / "metrics.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
        (run / "replies.jsonl").write_text("".join(json.dumps(p, ensure_ascii=False) + "\n" for p in per_turn))
    return out


def cmd_analyze(a):
    print(json.dumps(analyze(Path(a.run)), indent=1, ensure_ascii=False))

# ----------------------------------------------------------------------------- explicit error / recovery cases

FAULT_CASES = [  # id, run args, expected
    ("bad_frame", ["--inject", "bad_frame"],
     "input guard pads/trims the 2 malformed frames (3000 and 6400 samples): 2 input_fixed events, no step_error, no restart, output finite, run exits 0"),
    ("bad_frame_raw", ["--inject", "bad_frame_raw"],
     "guard bypassed: the backend either accepts the malformed frames with finite output, or raises; on a raise the driver logs step_error, "
     "restarts the session and the next frame is finite; run exits 0"),
    ("garbage_input", ["--inject", "garbage_input"],
     "3 s of loud noise incl. NaN / inf / 4x over-range frames: guard sanitises (input_fixed nonfinite + over_range), output stays finite, "
     "no step_error, normal output (non-garbage, finite) resumes after the burst; run exits 0"),
    ("truncated_input", ["--inject", "truncated_input"],
     "a user utterance cut at 40 %: no error, output finite, and the next full user turn is answered (>= 1 s voiced reply); run exits 0"),
    ("stall", ["--inject", "stall"],
     "input stalls for STALL s mid-stream: no error/restart; first post-stall frame wall latency <= max(2x, +5 ms) the pre-stall median "
     "and back to <= max(1.2x, +2 ms) within 3 frames; run exits 0"),
    ("watchdog_loop", ["--inject", "loop", "--watchdog"],
     "forced token loop (period 3): loop event -> watchdog_pending -> restart at turn state idle -> finite output; no loop after the restart; run exits 0"),
    ("watchdog_latency", ["--inject", "latency", "--watchdog", "--inject-latency-ms", "200"],
     "simulated +200 ms/frame: hard watchdog restart (latency reason) within the 30 s p95 window, regardless of turn state; "
     "latency back under 120 ms after the restart; run exits 0"),
    ("disk_low", ["--inject", "disk_low"],
     "free-space threshold jumps above real free space mid-run: disk_low event, clean stop with exit 3, logs + metrics.json written and parseable"),
    ("process_kill", [],
     "SIGKILL mid-run: logs stay parseable (at most 1 torn line per file), no orphan process; a fresh process loads, starts and "
     "produces its first frame; that run exits 0"),
]


def _evs(run):
    return read_jsonl(Path(run) / "events.jsonl")[0]


def _judge(cid, run: Path, rc: int, a) -> dict:
    ev = _evs(run)
    kinds = Counter(e["event"] for e in ev)
    frames = read_jsonl(run / "frames.jsonl")[0]
    def first(kind):
        return next((e for e in ev if e["event"] == kind), None)
    inj, rec = first("inject"), first("recovered")
    restarts = [e for e in ev if e["event"] == "restart"]
    nonfinite = sum(1 for f in frames if not f["finite"])
    rec_s = round(rec["wall_s"] - inj["wall_s"], 3) if (inj and rec) else None
    obs, ok = {}, False
    if cid == "bad_frame":
        fixes = [e for e in ev if e["event"] == "input_fixed"]
        obs = {"input_fixed": [e["issues"] for e in fixes], "step_errors": kinds["step_error"], "restarts": len(restarts), "nonfinite_frames": nonfinite}
        ok = rc == 0 and len(fixes) >= 2 and not kinds["step_error"] and not restarts and nonfinite == 0
    elif cid == "bad_frame_raw":
        errs = [e["error"] for e in ev if e["event"] == "step_error"]
        obs = {"backend_raised": bool(errs), "errors": errs, "restarts": [e["reason"] for e in restarts], "nonfinite_frames": nonfinite,
               "recovered": rec is not None}
        ok = rc == 0 and ((not errs and nonfinite == 0) or (errs and restarts and rec is not None))
        obs["behaviour"] = ("backend raised -> session restarted -> recovered" if errs else "backend accepted malformed frames silently")
    elif cid == "garbage_input":
        issues = sorted({i.split()[0] for e in ev if e["event"] == "input_fixed" for i in e["issues"]})
        k_end = (first("inject_end") or {"k": 0})["k"]
        after = [f for f in frames if k_end < f["k"] <= k_end + int(10 / FRAME_S)]
        g = float(np.mean([f["garbage"] for f in after])) if after else None
        obs = {"guard_issues": issues, "step_errors": kinds["step_error"], "nonfinite_frames": nonfinite, "garbage_ratio_10s_after": g}
        ok = rc == 0 and {"nonfinite", "over_range"} <= set(issues) and not kinds["step_error"] and nonfinite == 0 and rec is not None
        if first("inject_end") and rec:
            rec_s = round(rec["wall_s"] - first("inject_end")["wall_s"], 3)
    elif cid == "truncated_input":
        meta = json.loads((run / "meta.json").read_text())
        li = next((i for i, l in enumerate(meta["labels"]) if l.get("truncated")), None)
        m = json.loads((run / "metrics.json").read_text()) if (run / "metrics.json").exists() else {}
        rows = {t["k"]: t for t in m.get("turns", [])}
        nxt = rows.get(meta["labels"][li]["k"] + 1) if li is not None else None
        tr = rows.get(meta["labels"][li]["k"]) if li is not None else None
        obs = {"truncated_turn": li, "reply_to_truncated_voiced_s": tr and tr["voiced_s"], "next_turn_voiced_s": nxt and nxt["voiced_s"],
               "next_turn_gap_s": nxt and nxt["reply_gap_s"], "step_errors": kinds["step_error"], "nonfinite_frames": nonfinite}
        ok = rc == 0 and li is not None and not kinds["step_error"] and nonfinite == 0 and bool(nxt) and nxt["voiced_s"] >= 1.0
        rec_s = None
    elif cid == "stall":
        se = first("stall_end")
        k = se["k"] if se else 0
        pre = [f["wall_ms"] for f in frames if k - 60 <= f["k"] < k and f.get("ms") is not None]
        post = [f["wall_ms"] for f in frames if k <= f["k"] < k + 10]
        med = float(np.median(pre)) if pre else None
        back = next((i for i, x in enumerate(post) if med is not None and x <= max(1.2 * med, med + 2.0)), None)
        obs = {"stall_s": a.stall_s, "pre_median_wall_ms": med, "post_stall_wall_ms_first5": post[:5], "frames_until_normal": back,
               "step_errors": kinds["step_error"], "restarts": len(restarts)}
        ok = rc == 0 and med is not None and post and post[0] <= max(2 * med, med + 5.0) and back is not None and back <= 3 and not kinds["step_error"] and not restarts
        rec_s = round(sum(post[:back + 1]) / 1000, 3) if back is not None else None
    elif cid == "watchdog_loop":
        pend = first("watchdog_pending")
        wr = [e for e in restarts if "loop" in e["reason"]]
        after_loops = [e for e in ev if e["event"] == "loop" and wr and e["k"] > wr[0]["k"] + 3]
        obs = {"loop_events": kinds["loop"], "pending": pend and pend["reason"], "restart": wr[0] if wr else None,
               "loops_after_restart": len(after_loops), "nonfinite_frames": nonfinite}
        obs["note"] = "watchdog went straight OK->RESTART (already idle)" if wr and not pend else "OK->PENDING->RESTART at idle"
        ok = rc == 0 and kinds["loop"] >= 1 and bool(wr) and wr[0]["turn"] == "idle" and not after_loops and rec is not None
    elif cid == "watchdog_latency":
        wr = [e for e in restarts if "latency" in e["reason"]]
        post = [f["ms"] for f in frames if wr and f["k"] > wr[0]["k"] and f.get("ms") is not None][:225]
        audio_s = round((wr[0]["k"] - inj["k"]) * FRAME_S, 2) if (wr and inj) else None
        obs = {"restart": wr[0] if wr else None, "audio_s_inject_to_restart": audio_s, "turn_at_restart": wr[0]["turn"] if wr else None,
               "post_restart_p95_ms": pct(post, 95)}
        ok = rc == 0 and bool(wr) and audio_s is not None and audio_s <= 31 and post and pct(post, 95) < 120
    elif cid == "disk_low":
        dl = first("disk_low")
        mp = run / "metrics.json"
        parse_ok = mp.exists() and bool(json.loads(mp.read_text()))
        obs = {"exit_code": rc, "disk_low_event": dl, "metrics_written": parse_ok, "frames_logged": len(frames)}
        ok = rc == 3 and dl is not None and parse_ok
        rec_s = round(dl["wall_s"] - inj["wall_s"], 3) if (dl and inj) else None
    return {"pass": bool(ok), "observed": obs, "recovery_s": rec_s, "exit_code": rc}


def _run_cmd(a, out, minutes, extra):
    cmd = [sys.executable, os.path.abspath(__file__), "run", "--backend", a.backend, "--out", str(out), "--minutes", str(minutes),
           "--seed", "0", "--stall-s", str(a.stall_s), "--sample-seconds", "0", "--barge-in-every", "0"]
    if a.backend == "fake":
        cmd += ["--fake-audio"]
    else:
        cmd += ["--model", a.model, "--quantize", str(a.quantize), "--script", a.script]
        if a.system_prompt_file:
            cmd += ["--system-prompt-file", a.system_prompt_file]
    return cmd + list(extra)


def cmd_faults(a):
    """Each case runs ONCE in its own process (retries 0); a failure is recorded as a failure, never re-run."""
    import signal
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    only = set(a.only.split(",")) if a.only else None
    res_path = out / "faults.json"
    done = {r["case"]: r for r in json.loads(res_path.read_text())["cases"]} if res_path.exists() else {}
    results = []
    for cid, extra, expected in FAULT_CASES:
        if only and cid not in only:
            continue
        expected = expected.replace("STALL", f"{a.stall_s:g}")
        if cid in done:                                     # retries 0: never re-run, keep the first outcome
            results.append({**done[cid], "note": "kept from the first attempt (retries 0)"}); continue
        run = out / cid
        log = open(out / f"{cid}.log", "w")
        t0 = time.time()
        r = {"case": cid, "expected": expected, "run_dir": cid, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        try:
            if cid != "process_kill":
                rc = subprocess.run(_run_cmd(a, run, a.minutes, extra), stdout=log, stderr=subprocess.STDOUT).returncode
                r.update(_judge(cid, run, rc, a))
            else:
                victim = out / "process_kill_victim"
                pr = subprocess.Popen(_run_cmd(a, victim, max(a.minutes, 2.0), []), stdout=log, stderr=subprocess.STDOUT)
                deadline = time.time() + a.kill_timeout
                while time.time() < deadline and pr.poll() is None:
                    if len(read_jsonl(victim / "frames.jsonl")[0]) >= 60:
                        break
                    time.sleep(0.2)
                n_before = len(read_jsonl(victim / "frames.jsonl")[0])
                alive = pr.poll() is None
                t_kill = time.time()
                if alive:
                    pr.send_signal(signal.SIGKILL)
                rc_v = pr.wait(timeout=30)
                orphan = subprocess.run(["ps", "-p", str(pr.pid)], capture_output=True).returncode == 0
                torn = {f: read_jsonl(victim / f)[1] for f in ("frames.jsonl", "events.jsonl", "mem.jsonl")}
                fresh = out / cid
                pr2 = subprocess.Popen(_run_cmd(a, fresh, 0.5, []), stdout=log, stderr=subprocess.STDOUT)
                t_first = None
                while pr2.poll() is None or t_first is None:
                    if t_first is None and (fresh / "frames.jsonl").exists() and (fresh / "frames.jsonl").stat().st_size > 0:
                        t_first = time.time()
                    if pr2.poll() is not None:
                        if t_first is None and (fresh / "frames.jsonl").exists() and (fresh / "frames.jsonl").stat().st_size > 0:
                            t_first = time.time()
                        break
                    time.sleep(0.05)
                rc2 = pr2.wait()
                obs = {"victim_was_running": alive, "victim_frames_before_kill": n_before, "victim_returncode": rc_v,
                       "orphan_after_kill": orphan, "torn_lines": torn, "fresh_run_exit": rc2,
                       "note": "the fresh run's frames.jsonl is block-buffered, so first-frame time is an upper bound"}
                ok = alive and rc_v == -signal.SIGKILL and not orphan and max(torn.values()) <= 1 and rc2 == 0 and t_first is not None
                r.update({"pass": bool(ok), "observed": obs, "recovery_s": round(t_first - t_kill, 3) if t_first else None, "exit_code": rc2})
        except Exception as e:
            r.update({"pass": False, "observed": {"harness_error": f"{type(e).__name__}: {e}"[:400]}, "recovery_s": None, "exit_code": None})
        r["wall_s"] = round(time.time() - t0, 1)
        log.close()
        results.append(r)
        res_path.write_text(json.dumps({"retries": 0, "backend": a.backend, "cases": list({**done, **{x["case"]: x for x in results}}.values())},
                                       indent=1, ensure_ascii=False))
        print(f"[{time.strftime('%H:%M:%S')}] {cid}: {'PASS' if r['pass'] else 'FAIL'} recovery_s={r.get('recovery_s')} wall_s={r['wall_s']}", flush=True)
    merged = {**done, **{r["case"]: {k: v for k, v in r.items() if k != "note"} for r in results}}
    order = [c[0] for c in FAULT_CASES]
    res_path.write_text(json.dumps({"retries": 0, "backend": a.backend, "cases": sorted(merged.values(), key=lambda r: order.index(r["case"]))},
                                   indent=1, ensure_ascii=False))
    return results


# ----------------------------------------------------------------------------- summary (box side)

SUMMARY_SCHEMA_VERSION = "echo-soak/2"


def _sha(path: Path) -> str:
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def _read_status(path) -> dict:
    st = {}
    if path and Path(path).exists():
        for line in Path(path).read_text().splitlines():
            parts = line.split("\t")
            if len(parts) >= 5 and parts[0] != "id":
                st[parts[0]] = {"exit_code": int(parts[1]) if parts[1].lstrip("-").isdigit() else None, "wall_s": float(parts[2] or 0),
                                "started": parts[3], "ended": parts[4], "note": parts[5] if len(parts) > 5 else ""}
    return st


def cmd_summarize(a):
    res = Path(a.results)
    status = _read_status(a.status or (res / "STATUS.tsv"))
    runs, faults = [], []
    for d in sorted(p for p in res.iterdir() if p.is_dir() and (p / "meta.json").exists()):
        rid = d.name
        try:
            m = analyze(d, write=True)
            meta = json.loads((d / "meta.json").read_text())
            st = status.get(rid, {})
            ck = m["checkpoints"]; last = ck[sorted(ck, key=lambda x: float(x[:-3]))[-1]] if ck else {}
            mm = read_jsonl(d / "mem.jsonl")[0]
            ev = read_jsonl(d / "events.jsonl")[0]
            ended = next((e for e in ev if e["event"] == "end"), None)
            ok = st.get("exit_code", 0 if ended and not ended.get("aborted") else 1) == 0 and bool(ended) and not ended.get("aborted")
            runs.append({
                "run_id": rid, "kind": "smoke" if rid.upper().startswith("SMOKE") else "soak", "status": "ok" if ok else "failed",
                "exit_code": st.get("exit_code"), "wall_s": st.get("wall_s"), "started": meta.get("started"),
                "config": {**m["args"], "minutes": meta["minutes"], "barge_in_every": meta["args"].get("barge_in_every", 0),
                           "backend": meta["backend"], "haru_mlx": meta.get("haru_mlx"), "mlx": meta.get("mlx")},
                "frames_logged": m["frames_logged"], "load_seconds": meta.get("load_seconds"),
                "latency": {"overall": m["latency_overall"], "windows_5min": m["latency_windows_5min"],
                            "first_audio_latency_s": m["first_audio_latency_s"],
                            "first_min_p50_ms": last.get("latency", {}).get("first_min_p50_ms"),
                            "last_min_p50_ms": last.get("latency", {}).get("last_min_p50_ms"),
                            "frames_over_133ms": last.get("latency", {}).get("frames_over_133ms"),
                            "rtf_model": last.get("latency", {}).get("rtf_model"), "rtf_wall": last.get("latency", {}).get("rtf_wall")},
                "memory": {**last.get("memory", {}), "mlx_peak_gb": max(((x.get("mlx_peak") or 0) / 1e9 for x in mm), default=None),
                           "rss_mb_start": (mm[0]["rss"] / 2**20) if mm else None},
                "stability": {"repetition": last.get("repetition"), "on_topic": last.get("on_topic"), "responsiveness": last.get("responsiveness"),
                              "audio": last.get("audio"), "restarts": m["restart_events"], "events": m["events_summary"],
                              "checkpoints": {k: {"p50_ms": v["latency"]["p50_ms"], "p95_ms": v["latency"]["p95_ms"], "p99_ms": v["latency"].get("p99_ms"),
                                                  "loop_events": v["repetition"]["loop_events"], "keyword_hit_rate": v["on_topic"]["keyword_hit_rate"],
                                                  "answered_turn_rate": v["responsiveness"]["answered_turn_rate"],
                                                  "garbage_frame_ratio": v["audio"]["garbage_frame_ratio"], "restarts": v["restarts"]} for k, v in ck.items()}},
                "naturalness_proxies": m["naturalness_proxies"],
                "samples": [{**s_, "path": f"{rid}/{s_['file']}"} for s_ in m["samples"]],
                "artifacts_dir": rid})
        except Exception as e:
            runs.append({"run_id": rid, "kind": "soak", "status": "failed", "error": f"analyze: {type(e).__name__}: {e}"[:400], "artifacts_dir": rid})
    for rid, st in status.items():          # planned runs with no directory (skipped / never started)
        if not any(r["run_id"] == rid for r in runs) and rid != "FAULTS":
            runs.append({"run_id": rid, "kind": "soak", "status": "skipped" if "SKIP" in st.get("note", "") else "missing", **st})
    fj = res / "faults" / "faults.json"
    if fj.exists():
        faults = json.loads(fj.read_text())["cases"]
    # blind listening pack: shuffled copies + a separate key
    import shutil
    blind = res / "blind"
    allsamp = [(r["run_id"], s_) for r in runs for s_ in r.get("samples", [])]
    if allsamp:
        blind.mkdir(exist_ok=True)
        order = list(range(len(allsamp))); random.Random(20261120).shuffle(order)
        key = {}
        for n_, i in enumerate(order, 1):
            rid, s_ = allsamp[i]
            name = f"S{n_:02d}.wav"
            shutil.copyfile(res / s_["path"], blind / name)
            key[name] = {"run_id": rid, "position": s_["position"], "source": s_["path"], "sha256": s_["sha256"]}
        (blind / "KEY.json").write_text(json.dumps(key, indent=1))
        (blind / "README.txt").write_text("Blind listening: play S01..Snn without opening KEY.json; rate each (1-5) for naturalness, "
                                          "coherence and audio quality; then open KEY.json to unblind. L = synthetic user, R = Haru.\n")
    soak = [r for r in runs if r["kind"] == "soak"]
    summary = {
        "schema_version": SUMMARY_SCHEMA_VERSION, "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "model": {"repo": "higurashi-ai/Haru-4B", "revision": "8d6e83bcd3701a76fc27a764965665da1df7da78",
                  "model_safetensors_sha256": "ad2c3534ef6bd88525e22e5da3ac4fb739368406bf3b1c852cbafbade647c0fa", "quantize": 8},
        "policy": {"retries": 0, "voices": "synthetic only (macOS say), no voice reference",
                   "naturalness": "objective proxies only, not MOS; blind listening pack provided"},
        "totals": {"runs": len(soak), "ok": sum(r["status"] == "ok" for r in soak), "failed": sum(r["status"] == "failed" for r in soak),
                   "skipped": sum(r["status"] in ("skipped", "missing") for r in soak),
                   "fault_cases": len(faults), "fault_pass": sum(1 for f in faults if f.get("pass")),
                   "fault_fail": sum(1 for f in faults if not f.get("pass"))},
        "runs": runs, "faults": faults, "verdict": None,
    }
    (res / "summary.json").write_text(json.dumps(summary, indent=1, ensure_ascii=False))
    (res / "report.md").write_text(render_report(summary))
    files = sorted(p for p in res.rglob("*") if p.is_file() and p.name != "MANIFEST.sha256")
    (res / "MANIFEST.sha256").write_text("".join(f"{_sha(p)}  {p.relative_to(res)}\n" for p in files))
    print(json.dumps(summary["totals"]))


def _f(x, nd=1):
    return "-" if x is None else (f"{x:.{nd}f}" if isinstance(x, float) else str(x))


def render_report(S) -> str:
    L = [f"# Haru-4B soak report ({S['generated']})", "",
         f"Model {S['model']['repo']}@{S['model']['revision'][:12]} q8. Retries: 0 (failures are reported, never re-run). "
         "Naturalness numbers are objective proxies, not MOS.", "",
         f"Runs: {S['totals']['ok']} ok / {S['totals']['failed']} failed / {S['totals']['skipped']} skipped. "
         f"Fault cases: {S['totals']['fault_pass']} pass / {S['totals']['fault_fail']} fail.", "",
         "## Runs", "",
         "| run | status | min | config | p50/p95/p99/max ms | p50 1st→last min | drift ms/min | RTF | first-audio p50/p95 s | MLX MB/min | RSS MB/min | rep 3g max | loops | kw hit | answered | garbage | restarts |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in S["runs"]:
        if r["status"] in ("skipped", "missing") or "latency" not in r:
            L.append(f"| {r['run_id']} | {r['status']} | | {r.get('note', r.get('error', ''))} |" + " |" * 13); continue
        c, lo, la, me, st = r["config"], r["latency"]["overall"], r["latency"], r["memory"], r["stability"]
        cfg = f"T{c['temperature']} k{c['top_k']} p{c['top_p']} dry {c['dry']} kv{c['kv_window']} ra{c['reanchor_minutes']} wd {c['watchdog']}"
        fa = la["first_audio_latency_s"]
        L.append(f"| {r['run_id']} | {r['status']} | {c['minutes']:g} | {cfg} | {_f(lo['p50_ms'])}/{_f(lo['p95_ms'])}/{_f(lo['p99_ms'])}/{_f(lo['max_ms'])} | "
                 f"{_f(la['first_min_p50_ms'])}→{_f(la['last_min_p50_ms'])} | {_f(lo['drift_ms_per_min'], 3)} | {_f(la['rtf_model'], 3)} | "
                 f"{_f(fa['p50'], 2)}/{_f(fa['p95'], 2)} | {_f(me.get('mlx_active_mb_per_min'), 2)} | {_f(me.get('rss_mb_per_min'), 2)} | "
                 f"{_f((st['repetition'] or {}).get('repeated_3gram_ratio_max'), 2)} | {(st['repetition'] or {}).get('loop_events')} | "
                 f"{_f((st['on_topic'] or {}).get('keyword_hit_rate'), 2)} | {_f((st['responsiveness'] or {}).get('answered_turn_rate'), 2)} | "
                 f"{_f((st['audio'] or {}).get('garbage_frame_ratio'), 3)} | {len(st['restarts'])} |")
    L += ["", "## Latency per 5-min window", ""]
    for r in S["runs"]:
        w = r.get("latency", {}).get("windows_5min")
        if not w:
            continue
        L += [f"**{r['run_id']}**", "", "| window | p50 | p95 | p99 | max | RTF | first-audio p50 s | MLX GB | RSS MB | restarts |", "|---|---|---|---|---|---|---|---|---|---|"]
        L += [f"| {x['t0_min']:g}-{x['t1_min']:g} | {_f(x['p50_ms'])} | {_f(x['p95_ms'])} | {_f(x['p99_ms'])} | {_f(x['max_ms'])} | {_f(x['rtf_model'], 3)} | "
              f"{_f(x['first_audio_s']['p50'], 2)} | {_f(x['mlx_active_gb_end'], 2)} | {_f(x['rss_mb_end'], 0)} | {x['restarts']} |" for x in w]
        L.append("")
    L += ["## Naturalness proxies (not MOS)", "",
          "| run | part | pause p50/p90 s | long pauses | rate w/s p50 | F0 med Hz | F0 range st | F0 std st | energy DR dB | clip | silence | garbage | reply gap p50/p95 s | barge yield p50 s / rate |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in S["runs"]:
        for part, n in (r.get("naturalness_proxies") or {}).items():
            if not n:
                continue
            t = n["turn_taking"]
            L.append(f"| {r['run_id']} | {part} | {_f(n['pause_s']['p50'], 2)}/{_f(n['pause_s']['p90'], 2)} | {_f(n['pause_s']['long_pause_gt_1_5s_rate'], 2)} | "
                     f"{_f(n['speaking_rate_wps']['p50'], 2)} | {_f(n['f0']['median_hz'], 0)} | {_f(n['f0']['range_st_p5_p95'], 1)} | {_f(n['f0']['std_st'], 2)} | "
                     f"{_f(n['energy']['dynamic_range_db'], 1)} | {_f(n['clipping_frame_ratio'], 3)} | {_f(n['silence_ratio'], 2)} | {_f(n['garbage_ratio'], 3)} | "
                     f"{_f(t['reply_gap_s']['p50'], 2)}/{_f(t['reply_gap_s']['p95'], 2)} | {_f(t['barge_yield_s']['p50'], 2)} / {_f(t['barge_yield_rate_le_2s'], 2)} |")
    L += ["", "## Error and recovery cases (each run once)", "", "| case | result | recovery s | expected | observed |", "|---|---|---|---|---|"]
    for f in S["faults"]:
        L.append(f"| {f['case']} | {'PASS' if f.get('pass') else 'FAIL'} | {_f(f.get('recovery_s'), 2)} | {f['expected']} | "
                 f"{json.dumps(f.get('observed'), ensure_ascii=False)[:600].replace('|', '/')} |")
    L += ["", "## Listening samples", "", "Blind pack in `blind/` (S01..Snn.wav, key in `blind/KEY.json`). Per run:", ""]
    for r in S["runs"]:
        for s_ in r.get("samples", []):
            L.append(f"- {s_['path']} ({s_['position']}, {s_['from_min']}-{s_['to_min']} min) sha256 {s_['sha256']}")
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------------------- selftest


def _args(**kw):
    p = build_parser()
    a = p.parse_args(["run", "--backend", "fake", "--fake-audio", "--out", kw.pop("out"), "--minutes", str(kw.pop("minutes", 10))])
    for k, v in kw.items():
        setattr(a, k, v)
    return a


def cmd_selftest(_a):
    import tempfile
    ok = 0
    def check(cond, msg):
        nonlocal ok
        if not cond:
            raise AssertionError(msg)
        ok += 1
    # metrics
    check(wer("the cat sat", "the cat sat") == 0 and abs(wer("the cat sat", "the dog sat") - 1 / 3) < 1e-9, "wer")
    check(wer("le chat", "le chat noir") == 0.5, "wer insertion")
    check(repeated_ngram_ratio("a b c d e f".split()) == 0.0 and repeated_ngram_ratio(("x y z " * 10).split()) > 0.8, "ngram ratio")
    check(find_loop([1, 2, 3] * 4) == (3, 4) and find_loop([1, 2, 3, 4, 5, 6]) is None and find_loop([9, 1, 2, 1, 2, 1, 2]) == (2, 3), "loop finder")
    check(abs(ols_slope([0, 1, 2, 3], [1, 3, 5, 7]) - 2) < 1e-9, "slope")
    tf = TfIdf(["running morning shoes", "inflation prices bank"])
    v = tf.vec("I love running in the morning")
    check(TfIdf.cos(v, tf.vec("running morning shoes")) > TfIdf.cos(v, tf.vec("inflation prices bank")), "tfidf")
    # turn state machine: every transition of the table
    tt = TurnTracker(hangover_frames=2)
    seq = [(-90, -90, Turn.IDLE), (-20, -90, Turn.USER), (-20, -20, Turn.OVERLAP), (-90, -20, Turn.OVERLAP),
           (-90, -20, Turn.MODEL), (-90, -90, Turn.MODEL), (-90, -90, Turn.IDLE)]
    for u, m, want in seq:
        got = tt.next(u, m)
        check(got == want, f"turn tracker: ({u},{m}) -> {got}, want {want}")
    # watchdog state machine
    w = Watchdog(WatchdogConfig(latency_window=4, latency_ms=100, cooldown_frames=2))
    base = dict(step_ms=80, loop=None, mem_gb=1.0, silent_turns=0, garbage_run=0)
    check(w.next(turn=Turn.MODEL, **base) == Wd.OK, "wd ok")
    check(w.next(turn=Turn.MODEL, **{**base, "loop": (4, 3)}) == Wd.PENDING, "wd soft -> pending")
    check(w.next(turn=Turn.MODEL, **base) == Wd.PENDING, "wd waits for idle")
    check(w.next(turn=Turn.IDLE, **base) == Wd.RESTART, "wd restarts at idle")
    w.restarted(); check(w.state == Wd.COOLDOWN, "wd cooldown")
    w.next(turn=Turn.IDLE, **base); check(w.next(turn=Turn.IDLE, **base) == Wd.OK, "wd back to ok")
    for _ in range(4):
        s = w.next(turn=Turn.USER, **{**base, "step_ms": 150})
    check(s == Wd.RESTART and "latency" in w.reason, "wd hard latency restarts even while user speaks")
    w2 = Watchdog(WatchdogConfig())
    check(w2.next(turn=Turn.USER, **{**base, "mem_gb": 20}) == Wd.RESTART, "wd hard memory")
    # windowed KV cache (numpy stands in for mlx.core; same indexing semantics)
    class Src: keys = values = None; offset = 0
    src = Src(); src.keys = np.arange(10, dtype=np.float32).reshape(1, 1, 10, 1); src.values = src.keys.copy(); src.offset = 10
    c = WindowedKVCache(src, prefix=10, window=8, xp=np, slack=4)
    for p in range(10, 200):
        kk, vv = c.update_and_fetch(np.full((1, 1, 1, 1), p, np.float32), np.full((1, 1, 1, 1), p, np.float32))
    stored = kk[0, 0, :, 0]
    check(c.offset == 200 and c.length <= 10 + 8 + 4, f"kv bounded (offset {c.offset}, len {c.length})")
    check(list(stored[:10]) == list(range(10)) and stored[-1] == 199 and list(stored[-8:]) == list(range(192, 200)), "kv keeps prefix + recent")
    tt_ = np.arange(FRAME) / SR
    check(abs(f0_autocorr((0.1 * np.sin(2 * np.pi * 180 * tt_)).astype(np.float32)) - 180) < 2, "f0 sine 180")
    check(abs(f0_autocorr((0.1 * np.sign(np.sin(2 * np.pi * 120 * tt_))).astype(np.float32)) - 120) < 2, "f0 square 120")
    check(f0_autocorr(np.random.default_rng(0).standard_normal(FRAME).astype(np.float32) * 0.1) == 0.0, "f0 noise -> 0")
    check(f0_autocorr(np.zeros(FRAME, np.float32)) == 0.0, "f0 silence -> 0")
    x_ = np.zeros(FRAME, np.float32); x_[:SUB] = 0.1
    check(voiced_mask(x_) == 1 and voiced_mask(np.full(FRAME, 0.1, np.float32)) == 255, "voiced mask")
    g_, iss = sanitize(np.array([np.nan, 2.0, -3.0], np.float32))
    check(g_.size == FRAME and np.isfinite(g_).all() and float(np.abs(g_).max()) <= 1 and len(iss) == 3, f"sanitize {iss}")
    check(sanitize(np.zeros(FRAME, np.float32))[1] == [], "sanitize clean")
    sw = sample_windows(int(60 * 60 / FRAME_S), 45)
    check(set(sw) == {"start", "middle", "end"} and sw["start"][1] <= sw["middle"][0] and sw["middle"][1] <= sw["end"][0], "sample windows")
    _, labs = build_timeline([np.ones(SR, np.float32)] * 3, [{}] * 3, 1.0, 4.0, barge_every=2, truncate_at_s=10)
    check(labs[1]["cut"] and labs[2]["barge"] and labs[2]["start"] - labs[1]["end_speech"] == 2 * SR, "barge timeline")
    check(sum(l["truncated"] for l in labs) == 1, "truncate timeline")
    print(f"unit checks: {ok} passed")
    # integration with the fake backend
    with tempfile.TemporaryDirectory() as td:
        clean = analyze_run(_args(out=f"{td}/clean", minutes=10))["checkpoints"]["10min"]
        check(clean["repetition"]["loop_events"] == 0 and clean["restarts"] == 0, f"clean run: {clean['repetition']}")
        check(clean["on_topic"]["keyword_hit_rate"] > 0.9 and clean["on_topic"]["tfidf_margin_positive_rate"] > 0.9, f"clean on-topic {clean['on_topic']}")
        check(clean["responsiveness"]["answered_turn_rate"] > 0.9 and abs(clean["latency"]["drift_ms_per_min"]) < 0.01, "clean responsive/no drift")
        loop = analyze_run(_args(out=f"{td}/loop", minutes=10, fake_loop_at=3.0))["checkpoints"]["10min"]
        check(loop["repetition"]["loop_events"] > 0 and loop["on_topic"]["keyword_hit_rate_second_half"] < 0.5, f"loop detected {loop['repetition']} {loop['on_topic']}")
        fixed = analyze_run(_args(out=f"{td}/loop_wd", minutes=10, fake_loop_at=3.0, watchdog=True))
        cp = fixed["checkpoints"]["10min"]
        check(cp["restarts"] >= 1 and all(e["turn"] == "idle" for e in fixed["restart_events"]), f"watchdog restart at idle {fixed['restart_events']}")
        check(cp["on_topic"]["keyword_hit_rate"] > loop["on_topic"]["keyword_hit_rate"], "watchdog restores on-topic replies")
        drift = analyze_run(_args(out=f"{td}/drift", minutes=10, fake_drift_at=0.0, fake_drift_ms_per_min=2.0,
                                  fake_leak_at=0.0, fake_leak_mb_per_min=20.0))["checkpoints"]["10min"]
        check(abs(drift["latency"]["drift_ms_per_min"] - 2.0) < 0.2, f"drift slope {drift['latency']['drift_ms_per_min']}")
        check(abs(drift["memory"]["mlx_active_mb_per_min"] - 20.0) < 3.0, f"leak slope {drift['memory']['mlx_active_mb_per_min']}")
        hard = analyze_run(_args(out=f"{td}/hard", minutes=10, fake_drift_at=0.0, fake_drift_ms_per_min=10.0, watchdog=True, wd_latency_ms=120.0))
        check(any("latency" in e["reason"] for e in hard["restart_events"]), "watchdog catches latency drift")
        garb = analyze_run(_args(out=f"{td}/garbage", minutes=10, fake_garbage_at=2.0))["checkpoints"]["10min"]
        check(garb["audio"]["garbage_frame_ratio"] > 0.05 and clean["audio"]["garbage_frame_ratio"] == 0.0, "garbage audio detected")
        rea = analyze_run(_args(out=f"{td}/reanchor", minutes=10, reanchor_minutes=3.0))
        check(rea["checkpoints"]["10min"]["restarts"] == 3 and all(e["turn"] == "idle" for e in rea["restart_events"]), f"re-anchor x3 at idle {rea['restart_events']}")
        # v2: barge-in, listening samples, per-window latency, naturalness proxies
        v2 = analyze_run(_args(out=f"{td}/v2", minutes=12, barge_in_every=4, sample_seconds=20.0))
        check(len(v2["latency_windows_5min"]) == 3 and all(w["p99_ms"] is not None for w in v2["latency_windows_5min"]), "5-min windows")
        check({s_["position"] for s_ in v2["samples"]} == {"start", "middle", "end"}, f"samples {v2['samples']}")
        import wave
        with wave.open(f"{td}/v2/sample_middle.wav") as w_:
            check(w_.getnchannels() == 2 and abs(w_.getnframes() / SR - 20.0) < 0.2, "sample wav stereo ~20 s")
        nat = v2["naturalness_proxies"]["whole_run"]
        check(abs(nat["f0"]["median_hz"] - 180) < 3 and nat["f0"]["range_st_p5_p95"] < 0.5, f"fake f0 180 Hz flat {nat['f0']}")
        check(nat["turn_taking"]["barge_ins_model_talking"] >= 3 and nat["turn_taking"]["barge_yield_rate_le_2s"] == 1.0, f"barge {nat['turn_taking']}")
        check(nat["turn_taking"]["reply_gap_s"]["p50"] is not None and 0.4 < nat["turn_taking"]["reply_gap_s"]["p50"] < 0.7, f"reply gap {nat['turn_taking']['reply_gap_s']}")
        check(nat["speaking_rate_wps"]["p50"] and 5 < nat["speaking_rate_wps"]["p50"] < 9, f"rate {nat['speaking_rate_wps']}")   # fake: 1 word/frame
        check(v2["checkpoints"]["12min"]["responsiveness"]["answered_turn_rate"] > 0.9, "cut replies excluded from answered rate")
        check(set(v2["naturalness_proxies"]) == {"whole_run", "first_third", "middle_third", "last_third"}, "thirds")
        # error / recovery cases (fake backend), each once
        fr_ = cmd_faults(build_parser().parse_args(["faults", "--backend", "fake", "--out", f"{td}/res/faults", "--stall-s", "0.5"]))
        bad = [r_["case"] for r_ in fr_ if not r_["pass"]]
        check(len(fr_) == len(FAULT_CASES) and not bad, f"fault cases failed: {bad}")
        again = cmd_faults(build_parser().parse_args(["faults", "--backend", "fake", "--out", f"{td}/res/faults", "--only", "stall"]))
        check(again[0].get("note", "").startswith("kept"), "retries 0: a recorded case is not re-run")
        # summarize: summary.json + report + blind pack + manifest
        import shutil
        shutil.copytree(f"{td}/v2", f"{td}/res/C12-fake")
        Path(f"{td}/res/STATUS.tsv").write_text("id\texit\twall_s\tstart\tend\tnote\nC12-fake\t0\t1\ta\tb\t\nB60\t\t0\t-\t-\tSKIP budget\n")
        cmd_summarize(build_parser().parse_args(["summarize", "--results", f"{td}/res"]))
        S = json.loads(Path(f"{td}/res/summary.json").read_text())
        check(S["schema_version"] == SUMMARY_SCHEMA_VERSION and S["totals"]["fault_pass"] == len(FAULT_CASES), "summary totals")
        check([r_["status"] for r_ in S["runs"]] == ["ok", "skipped"], f"run statuses {[r_['status'] for r_ in S['runs']]}")
        check(len(json.loads(Path(f"{td}/res/blind/KEY.json").read_text())) == 3, "blind pack")
        man = Path(f"{td}/res/MANIFEST.sha256").read_text().splitlines()
        check(all(_sha(Path(f"{td}/res") / l.split("  ", 1)[1]) == l.split("  ", 1)[0] for l in man) and len(man) > 10, "manifest")
    print(f"selftest: {ok} checks passed")


def analyze_run(a):
    import contextlib, io
    with contextlib.redirect_stdout(io.StringIO()):
        cmd_run(a)
    return analyze(Path(a.out), write=False)

# ----------------------------------------------------------------------------- plan


PLAN = [  # id, minutes, lang, flags, purpose
    ("A60", 60, "en", "", "baseline = upstream defaults (DRY on, T 0.7, top-k 25); 10/30/60 min are checkpoints of this one run"),
    ("A30fr", 30, "fr", "", "baseline in French (Atlas/Athena/Zeus are FR+EN)"),
    ("B60", 60, "en", "--kv-window 4096 --reanchor-minutes 15 --watchdog", "all mitigations on"),
    ("C10-dryoff", 10, "en", "--dry off", "ablation: is upstream DRY what keeps loops away?"),
    ("C10-t05", 10, "en", "--temperature 0.5", "lower temperature"),
    ("C10-t09p09", 10, "en", "--temperature 0.9 --top-p 0.9", "higher temperature, nucleus"),
    ("C10-kv1024", 10, "en", "--kv-window 1024", "KV truncation active after ~2.3 min (does quality hold?)"),
    ("C10-dry12", 10, "en", "--dry-multiplier 1.2", "stronger DRY"),
]


def cmd_plan(_a):
    B = "~/echo-haru-soak"
    lines = [f"# Mac run plan (as-fast pacing: wall time ~= 0.6 x audio time at q8, measured RTF 0.604-0.609)",
             f"# Needs: >= 17 GiB free before start (model 10.54 GB = 9.8 GiB + venv ~0.6 GiB + logs/audio ~0.6 GiB, then the >= 6 GiB floor).",
             f"# Total audio {sum(p[1] for p in PLAN)} min -> wall ~{0.62 * sum(p[1] for p in PLAN):.0f} min + 8 x ~25 s load/prompt ~= {0.62 * sum(p[1] for p in PLAN) / 60 + 8 * 25 / 3600:.1f} h.",
             f"B={B}; mkdir -p $B/runs && cd $B",
             "# copy in from the box: haru_soak.py, requirements.txt (the benchmark's hash-locked file), card_en.txt, card_fr.txt",
             "export TMPDIR=$B/tmp HF_HOME=$B/hf HF_HUB_OFFLINE=1 PIP_CACHE_DIR=$B/pipcache; mkdir -p $TMPDIR",
             "python3.12 -m venv venv   # 3.12.13, as in the benchmark\n./venv/bin/pip install --require-hashes --no-deps -r requirements.txt   # same hash-locked set as the benchmark (mlx 0.32.4, no torch)",
             "# model: same pinned revision + sha256 as the benchmark",
             "curl -L --fail -o Haru-4B/model.safetensors --create-dirs https://huggingface.co/higurashi-ai/Haru-4B/resolve/8d6e83bcd3701a76fc27a764965665da1df7da78/model.safetensors",
             "for f in config.json tokenizer.json; do curl -L --fail -o Haru-4B/$f https://huggingface.co/higurashi-ai/Haru-4B/resolve/8d6e83bcd3701a76fc27a764965665da1df7da78/$f; done",
             "[ \"$(shasum -a 256 Haru-4B/model.safetensors | cut -d' ' -f1)\" = ad2c3534ef6bd88525e22e5da3ac4fb739368406bf3b1c852cbafbade647c0fa ] || exit 2",
             "./venv/bin/python haru_soak.py selftest",
             "./venv/bin/python haru_soak.py make-script --lang en --out script_en && ./venv/bin/python haru_soak.py make-script --lang fr --out script_fr"]
    for pid, mins, lang, flags, why in PLAN:
        lines.append(f"# {pid}: {why}")
        lines.append(f"[ $(df -k ~ | awk 'NR==2{{print $4}}') -gt $((6*1024*1024)) ] || exit 3; "
                     f"./venv/bin/python haru_soak.py run --backend haru --model Haru-4B --quantize 8 --script script_{lang} "
                     f"--system-prompt-file card_{lang}.txt --minutes {mins} --seed 0 {flags} --out runs/{pid} > runs/{pid}.log 2>&1")
    lines += ["tar czf echo-haru-soak-results.tgz runs/*/metrics.json runs/*/events.jsonl runs/*/mem.jsonl runs/*/frames.jsonl runs/*/replies.jsonl runs/*/meta.json runs/*.log",
              "# after copying the tarball back: rm -rf ~/echo-haru-soak   (only that folder)"]
    print("\n".join(lines))

# ----------------------------------------------------------------------------- cli


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make-script"); m.add_argument("--lang", choices=("en", "fr"), required=True); m.add_argument("--out", required=True)
    m.add_argument("--voice"); m.add_argument("--seed", type=int, default=0)
    r = sub.add_parser("run")
    r.add_argument("--backend", choices=("haru", "fake"), default="haru")
    r.add_argument("--model", help="LOCAL checkpoint dir (never downloads)"); r.add_argument("--quantize", choices=("8", "none"), default="8")
    r.add_argument("--script"); r.add_argument("--fake-audio", action="store_true", help="speech-like noise instead of `say` (box/selftest)")
    r.add_argument("--system-prompt-file"); r.add_argument("--out", required=True)
    r.add_argument("--minutes", type=float, default=10); r.add_argument("--gap", type=float, default=8.0, help="reply window after each user turn (s)")
    r.add_argument("--pace", choices=("asfast", "realtime"), default="asfast"); r.add_argument("--seed", type=int, default=0)
    r.add_argument("--mem-every", type=float, default=10.0, help="memory sample period (wall s)"); r.add_argument("--save-audio", action="store_true")
    r.add_argument("--temperature", type=float, default=0.7); r.add_argument("--top-k", type=int, default=25); r.add_argument("--top-p", type=float, default=1.0)
    r.add_argument("--guidance-scale", type=float, default=1.5); r.add_argument("--eop-bias", type=float, default=0.0)
    r.add_argument("--dry", choices=("on", "off"), default="on"); r.add_argument("--dry-multiplier", type=float, default=0.8); r.add_argument("--dry-lookback", type=int, default=1024)
    r.add_argument("--kv-window", type=int, default=0); r.add_argument("--reanchor-minutes", type=float, default=0.0)
    r.add_argument("--watchdog", action="store_true"); r.add_argument("--wd-latency-ms", type=float, default=120.0)
    r.add_argument("--wd-mem-gb", type=float, default=14.0); r.add_argument("--wd-loop-repeats", type=int, default=3)
    for f in ("loop", "drift", "leak", "garbage"):
        r.add_argument(f"--fake-{f}-at", type=float, default=None, help=f"fake backend: start the {f} fault at this minute")
    r.add_argument("--fake-drift-ms-per-min", type=float, default=0.0); r.add_argument("--fake-leak-mb-per-min", type=float, default=0.0)
    r.add_argument("--barge-in-every", type=int, default=0, help="every Nth user turn, the next turn barges in 2 s into the reply")
    r.add_argument("--sample-seconds", type=float, default=45.0, help="listening WAVs at start/middle/end (0 = none)")
    r.add_argument("--min-free-gib", type=float, default=6.0, help="disk-low guard: stop cleanly (exit 3) under this")
    r.add_argument("--no-input-guard", action="store_true", help="feed frames to the backend unsanitised")
    r.add_argument("--inject", choices=INJECTIONS, default="none", help="explicit fault case (see `faults`)")
    r.add_argument("--inject-at", type=float, default=0.25, help="minute of the injection")
    r.add_argument("--stall-s", type=float, default=5.0); r.add_argument("--inject-latency-ms", type=float, default=200.0)
    an = sub.add_parser("analyze"); an.add_argument("--run", required=True)
    sub.add_parser("selftest"); sub.add_parser("plan")
    fa = sub.add_parser("faults", help="explicit error/recovery cases, each run once (retries 0)")
    fa.add_argument("--backend", choices=("haru", "fake"), default="haru"); fa.add_argument("--model"); fa.add_argument("--quantize", default="8")
    fa.add_argument("--script"); fa.add_argument("--system-prompt-file"); fa.add_argument("--out", required=True)
    fa.add_argument("--minutes", type=float, default=1.5); fa.add_argument("--stall-s", type=float, default=5.0)
    fa.add_argument("--only", help="comma-separated case ids"); fa.add_argument("--kill-timeout", type=float, default=240.0)
    su = sub.add_parser("summarize", help="(box) build summary.json, report.md, blind pack, MANIFEST.sha256")
    su.add_argument("--results", required=True); su.add_argument("--status", help="STATUS.tsv from run_all.sh")
    return p


def main(argv=None):
    a = build_parser().parse_args(argv)
    if a.cmd == "run" and a.backend == "haru" and not (a.model and Path(a.model).expanduser().is_dir()):
        sys.exit("--model must be a local directory (this script never downloads)")
    if a.cmd == "faults" and a.backend == "haru" and not (a.model and Path(a.model).expanduser().is_dir()):
        sys.exit("--model must be a local directory (this script never downloads)")
    {"make-script": cmd_make_script, "run": cmd_run, "analyze": cmd_analyze, "selftest": cmd_selftest, "plan": cmd_plan,
     "faults": cmd_faults, "summarize": cmd_summarize}[a.cmd](a)


if __name__ == "__main__":
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    main()
