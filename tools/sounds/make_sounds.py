#!/usr/bin/env python3
"""Zeus's own sound set, rendered offline by synthesis (stdlib only; nothing is sampled or copied).

  tools/sounds/make_sounds.py --out /tmp/zeus-sounds-wav            render 16-bit 48 kHz mono WAVs
  tools/sounds/make_sounds.py --out /tmp/zeus-sounds-wav --stats    also print peak / RMS / clipping / click checks
  tools/sounds/make_sounds.py --out /tmp/zeus-sounds-wav --convert Sources/Zeus/Sounds
                                                                    also write AAC .m4a (afconvert) into the app resources

Durations mirror the event set of the reference app (running 1.96 s, permission 1.96 / 2.96 s, respond
0.96 s, success 2.96 s, dictation begin 0.50 s and end 0.46 s); the table at the bottom is the source
of truth and Sources/ZeusCore/Sound/SoundCatalog.swift repeats it for the app and the tests.
"""
import argparse, math, os, random, struct, subprocess, sys, wave

SR = 48000
TAU = 2 * math.pi

def frames(seconds):
    return int(round(seconds * SR))

# ---- notes -----------------------------------------------------------------------------------
NOTE = {"C3": 130.81, "E3": 164.81, "G3": 196.0, "A3": 220.0, "C4": 261.63, "D4": 293.66, "E4": 329.63, "G4": 392.0,
        "A4": 440.0, "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99, "A5": 880.0,
        "B5": 987.77, "C6": 1046.5, "D6": 1174.66, "E6": 1318.51, "G6": 1567.98, "A6": 1760.0}

# ---- voices (each adds into a list of floats) -------------------------------------------------
def ramp(x):          # raised-cosine 0..1
    x = min(1.0, max(0.0, x))
    return 0.5 - 0.5 * math.cos(math.pi * x)

def bell(buf, t0, freq, amp, decay=0.9, attack=0.004, partials=None):
    partials = partials or [(1.0, 1.0, 1.0), (2.0, 0.34, 0.65), (2.76, 0.22, 0.45), (4.07, 0.08, 0.3)]
    start = frames(t0)
    for ratio, a, d in partials:
        w = TAU * freq * ratio / SR
        life = decay * d
        length = min(len(buf) - start, frames(life * 7))
        for i in range(max(0, length)):
            t = i / SR
            env = ramp(t / attack) * math.exp(-t / life)
            buf[start + i] += amp * a * env * math.sin(w * i)

def pluck(buf, t0, freq, amp, decay=0.25, partials=((1, 1.0), (2, 0.4), (3, 0.16), (4.2, 0.07))):
    start = frames(t0)
    for ratio, a in partials:
        w = TAU * freq * ratio / SR
        life = decay / (1 + 0.5 * (ratio - 1))
        length = min(len(buf) - start, frames(life * 7))
        for i in range(max(0, length)):
            t = i / SR
            buf[start + i] += amp * a * ramp(t / 0.002) * math.exp(-t / life) * math.sin(w * i)

def pad(buf, t0, freq, dur, amp, attack, release, detune=0.004, vibrato=0.0):
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    for k, (ratio, a) in enumerate(((1.0, 1.0), (1.0 + detune, 0.8), (2.0, 0.22), (0.5, 0.3))):
        w = TAU * freq * ratio / SR
        ph = k * 1.3
        for i in range(max(0, length)):
            t = i / SR
            env = ramp(t / attack) * ramp((dur - t) / release)
            vib = 1 + vibrato * math.sin(TAU * 5.2 * t)
            buf[start + i] += amp * a * env * math.sin(w * i * vib + ph)

def sweep(buf, t0, f0, f1, dur, amp, attack=0.02, release=0.08, curve=1.0, tremolo=0.0):
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    phase = 0.0
    for i in range(max(0, length)):
        t = i / SR
        x = (t / dur) ** curve
        f = f0 + (f1 - f0) * x
        phase += TAU * f / SR
        env = ramp(t / attack) * ramp((dur - t) / release)
        trem = 1 - tremolo + tremolo * (0.5 + 0.5 * math.sin(TAU * 9 * t))
        buf[start + i] += amp * env * trem * (math.sin(phase) + 0.25 * math.sin(2 * phase))

def fm(buf, t0, freq, ratio, index, dur, amp, decay):
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    for i in range(max(0, length)):
        t = i / SR
        env = ramp(t / 0.004) * math.exp(-t / decay)
        mod = index * env * math.sin(TAU * freq * ratio * t)
        buf[start + i] += amp * env * math.sin(TAU * freq * t + mod)

def thump(buf, t0, f0, f1, dur, amp):
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    phase = 0.0
    for i in range(max(0, length)):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-t * 28)
        phase += TAU * f / SR
        buf[start + i] += amp * ramp(t / 0.003) * math.exp(-t / (dur / 4)) * math.sin(phase)

def tick(buf, t0, dur, amp, rng, smooth=0.18):
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    y = 0.0
    for i in range(max(0, length)):
        t = i / SR
        y += smooth * (rng.uniform(-1, 1) - y)
        buf[start + i] += amp * ramp(t / 0.001) * math.exp(-t / (dur / 5)) * y

def odd(buf, t0, freq, dur, amp, decay):
    """Soft square-ish tone (odd harmonics, rounded) for the game-style alert."""
    start = frames(t0)
    length = min(len(buf) - start, frames(dur))
    for i in range(max(0, length)):
        t = i / SR
        env = ramp(t / 0.006) * ramp((dur - t) / 0.03) * math.exp(-t / decay)
        w = TAU * freq * t
        buf[start + i] += amp * env * (math.sin(w) + math.sin(3 * w) / 4 + math.sin(5 * w) / 12)

# ---- space ---------------------------------------------------------------------------------
def reverb(buf, mix=0.25, size=1.0):
    """Four combs and two all-passes: a small, soft room."""
    delays = [int(d * SR / 1000 * size) for d in (29.7, 37.1, 41.1, 43.7)]
    out = [0.0] * len(buf)
    for d in delays:
        line = [0.0] * d
        idx = 0
        fb = 0.72
        damp = 0.0
        for i, x in enumerate(buf):
            y = line[idx]
            damp += 0.45 * (y - damp)
            line[idx] = x + fb * damp
            idx = (idx + 1) % d
            out[i] += y * 0.25
    for d, g in ((int(5.0 * SR / 1000), 0.6), (int(1.7 * SR / 1000), 0.6)):
        line = [0.0] * d
        idx = 0
        for i in range(len(out)):
            delayed = line[idx]
            v = out[i] + g * delayed
            line[idx] = v
            out[i] = delayed - g * v
            idx = (idx + 1) % d
    for i in range(len(buf)):
        buf[i] = buf[i] * (1 - mix * 0.5) + out[i] * mix * 2.0

def finish(buf, loop=False, fade_in=0.004, fade_out=0.05, rms_target=0.075, peak_cap=0.7):
    n = len(buf)
    peak = max(abs(x) for x in buf) or 1.0
    rms = math.sqrt(sum(x * x for x in buf) / n) or 1e-9
    gain = min(rms_target / rms, peak_cap / peak)
    for i in range(n):
        buf[i] *= gain
    if not loop:
        fi, fo = frames(fade_in), frames(min(0.15, max(fade_out, n / SR * 0.2)))
        for i in range(min(fi, n)):
            buf[i] *= ramp(i / fi)
        for i in range(min(fo, n)):
            buf[n - 1 - i] *= ramp(i / fo)
        buf[0] = 0.0
        buf[-1] = 0.0
    return buf

# ---- the sounds ------------------------------------------------------------------------------
def new(seconds):
    return [0.0] * frames(seconds)

def running_classic(rng):
    b = new(1.96); bell(b, 0.0, NOTE["E5"], 0.8, 0.7); bell(b, 0.17, NOTE["A5"], 0.9, 0.85); bell(b, 0.17, NOTE["E4"], 0.18, 1.1)
    reverb(b, 0.26); return b

def running_spaceship(rng):
    b = new(1.96)
    sweep(b, 0.0, 180, 760, 1.15, 0.55, attack=0.5, release=0.6, curve=1.6)
    sweep(b, 0.05, 362, 1522, 1.1, 0.16, attack=0.5, release=0.6, curve=1.6, tremolo=0.5)
    bell(b, 0.95, NOTE["E6"], 0.35, 0.6); pad(b, 0.5, NOTE["A3"], 1.4, 0.2, 0.6, 0.7, vibrato=0.002)
    reverb(b, 0.3, 1.3); return b

def running_mystery(rng):
    b = new(0.96)
    for k, f in enumerate(("A4", "C5", "E5", "A5")):
        pluck(b, 0.13 * k, NOTE[f], 0.7, 0.2)
    pad(b, 0.0, NOTE["E3"], 0.9, 0.2, 0.25, 0.4); reverb(b, 0.22); return b

def running_tap(rng):
    b = new(1.96)
    thump(b, 0.0, 190, 62, 0.22, 0.9); tick(b, 0.0, 0.03, 0.4, rng)
    bell(b, 0.1, NOTE["G5"], 0.5, 0.7); bell(b, 0.1, NOTE["D5"], 0.25, 0.9); reverb(b, 0.24); return b

def running_loop(rng):
    # Every partial is a whole number of cycles in 4 s, so the end meets the start with no seam.
    b = new(4.0)
    for f, a in ((110.0, 0.9), (165.0, 0.55), (220.0, 0.6), (330.0, 0.28), (440.25, 0.1)):
        for i in range(len(b)):
            t = i / SR
            swell = 0.75 + 0.25 * math.sin(TAU * t / 4.0 - 0.7)
            b[i] += a * swell * math.sin(TAU * round(f * 4) / 4 * t)
    for i in range(len(b)):
        t = i / SR
        pulse = 0.5 + 0.5 * math.cos(TAU * 1.0 * t)
        b[i] *= 0.7 + 0.3 * pulse
    return b

def permission_classic(rng):
    b = new(1.96)
    for t0 in (0.0, 0.95):
        a = 1.0 if t0 == 0 else 0.7
        bell(b, t0, NOTE["G5"], 0.8 * a, 0.65); bell(b, t0 + 0.28, NOTE["E5"], 0.85 * a, 0.9)
    reverb(b, 0.26); return b

def permission_notebook(rng):
    b = new(1.96)
    for base in (0.0, 0.95):
        for k, f in enumerate(("C5", "E5", "G5")):
            pluck(b, base + 0.16 * k, NOTE[f], 0.7 - base * 0.2, 0.28, partials=((1, 1.0), (3.9, 0.35), (9.0, 0.08)))
    reverb(b, 0.2); return b

def permission_gamealert(rng):
    b = new(1.96)
    for base in (0.0, 0.9):
        for k, f in enumerate(("E5", "G5", "C6")):
            odd(b, base + 0.11 * k, NOTE[f], 0.1, 0.5, 0.06)
        odd(b, base + 0.4, NOTE["G5"], 0.35, 0.4, 0.14)
    reverb(b, 0.18, 0.8); return b

def permission_weard(rng):
    b = new(1.96)
    for base in (0.0, 0.85):
        sweep(b, base, 620, 300, 0.55, 0.6, attack=0.05, release=0.25, tremolo=0.35)
        pad(b, base, 330, 0.7, 0.15, 0.1, 0.4, vibrato=0.01)
    reverb(b, 0.28, 1.2); return b

def permission_weard2(rng):
    b = new(1.96)
    for base, f in ((0.0, "A4"), (0.5, "D5"), (1.1, "A4")):
        fm(b, base, NOTE[f], 1.41, 2.2, 0.8, 0.55, 0.35)
    bell(b, 1.1, NOTE["E5"], 0.25, 0.8); reverb(b, 0.3, 1.2); return b

def permission_shortwarning(rng):
    b = new(2.96)
    for base in (0.0, 0.8, 1.6):
        a = 1.0 - base * 0.22
        bell(b, base, NOTE["E5"], 0.8 * a, 1.0); bell(b, base + 0.2, NOTE["C5"], 0.8 * a, 1.2)
        bell(b, base + 0.4, NOTE["A4"], 0.6 * a, 1.4)
    pad(b, 0.0, NOTE["A3"], 2.6, 0.12, 0.5, 1.2); reverb(b, 0.28, 1.3); return b

def respond_futuristic1(rng):
    b = new(0.96)
    sweep(b, 0.0, 420, 1250, 0.22, 0.6, attack=0.02, release=0.12)
    bell(b, 0.16, NOTE["E6"], 0.55, 0.28); bell(b, 0.16, NOTE["E5"], 0.22, 0.4); reverb(b, 0.22); return b

def respond_futuristic2(rng):
    b = new(0.96)
    fm(b, 0.0, NOTE["A5"], 2.0, 1.4, 0.3, 0.5, 0.12); fm(b, 0.12, NOTE["E6"], 2.0, 1.4, 0.5, 0.5, 0.2)
    reverb(b, 0.25); return b

def success(rng):
    b = new(2.96)
    for k, f in enumerate(("C5", "E5", "G5", "C6")):
        bell(b, 0.12 * k, NOTE[f], 0.7, 1.1)
    bell(b, 0.6, NOTE["E6"], 0.3, 1.0); bell(b, 0.0, NOTE["C4"], 0.3, 1.6)
    pad(b, 0.2, NOTE["C4"], 2.4, 0.18, 0.4, 1.4); pad(b, 0.2, NOTE["G4"], 2.4, 0.12, 0.4, 1.4)
    reverb(b, 0.3, 1.3); return b

def success_gentle(rng):
    b = new(1.96)
    bell(b, 0.0, NOTE["G5"], 0.7, 0.7); bell(b, 0.22, NOTE["C6"], 0.8, 1.0); reverb(b, 0.26); return b

def success_spark(rng):
    b = new(0.96)
    for k, f in enumerate(("E6", "G6", "C6")):
        bell(b, 0.09 * k, NOTE[f], 0.55, 0.3)
    reverb(b, 0.2); return b

def failure(rng):
    b = new(1.46)
    bell(b, 0.0, NOTE["G4"], 0.9, 0.7); bell(b, 0.22, NOTE["D4"], 0.9, 1.0); pad(b, 0.0, NOTE["E3"], 1.2, 0.16, 0.2, 0.7)
    reverb(b, 0.24); return b

def dictation_begin(rng):
    b = new(0.50)
    bell(b, 0.0, NOTE["E5"], 0.7, 0.14); bell(b, 0.09, NOTE["A5"], 0.8, 0.2); reverb(b, 0.12, 0.6); return b

def dictation_end(rng):
    b = new(0.46)
    bell(b, 0.0, NOTE["A5"], 0.7, 0.14); bell(b, 0.09, NOTE["E5"], 0.8, 0.2); reverb(b, 0.12, 0.6); return b

def listen_start(rng):
    b = new(0.40)
    sweep(b, 0.0, 500, 900, 0.14, 0.4, attack=0.02, release=0.08); bell(b, 0.06, NOTE["B5"], 0.6, 0.12); return b

def listen_stop(rng):
    b = new(0.40)
    sweep(b, 0.0, 900, 520, 0.14, 0.4, attack=0.02, release=0.08); bell(b, 0.06, NOTE["E5"], 0.6, 0.12); return b

def answer_done(rng):
    b = new(0.80)
    bell(b, 0.0, NOTE["G5"], 0.7, 0.28); bell(b, 0.12, NOTE["C6"], 0.8, 0.4); reverb(b, 0.2, 0.8); return b

def voice_error(rng):
    b = new(0.70)
    bell(b, 0.0, NOTE["D4"], 0.8, 0.3); bell(b, 0.15, NOTE["G3"], 0.9, 0.4); reverb(b, 0.18, 0.8); return b

def todo_check(rng):
    b = new(0.35)
    pluck(b, 0.0, NOTE["E6"], 0.7, 0.07, partials=((1, 1.0), (2.4, 0.3))); pluck(b, 0.05, NOTE["A6"], 0.5, 0.08, partials=((1, 1.0), (2.4, 0.3)))
    return b

def timer_alarm(rng):
    b = new(2.0)
    for k in range(3):
        t = 0.62 * k
        bell(b, t, NOTE["C6"], 0.7, 0.45); bell(b, t + 0.14, NOTE["G5"], 0.6, 0.5)
    reverb(b, 0.25); return b

# name, builder, seconds, is_loop
SOUNDS = [
    ("running_classic", running_classic, 1.96, False), ("running_spaceship", running_spaceship, 1.96, False),
    ("running_mystery", running_mystery, 0.96, False), ("running_tap", running_tap, 1.96, False),
    ("running_loop", running_loop, 4.00, True),
    ("permission_classic", permission_classic, 1.96, False), ("permission_notebook", permission_notebook, 1.96, False),
    ("permission_gamealert", permission_gamealert, 1.96, False), ("permission_weard", permission_weard, 1.96, False),
    ("permission_weard2", permission_weard2, 1.96, False), ("permission_shortwarning", permission_shortwarning, 2.96, False),
    ("respond_futuristic1", respond_futuristic1, 0.96, False), ("respond_futuristic2", respond_futuristic2, 0.96, False),
    ("success", success, 2.96, False), ("success_gentle", success_gentle, 1.96, False), ("success_spark", success_spark, 0.96, False),
    ("failure", failure, 1.46, False),
    ("dictation_begin", dictation_begin, 0.50, False), ("dictation_end", dictation_end, 0.46, False),
    ("listen_start", listen_start, 0.40, False), ("listen_stop", listen_stop, 0.40, False),
    ("answer_done", answer_done, 0.80, False), ("voice_error", voice_error, 0.70, False),
    ("todo_check", todo_check, 0.35, False), ("timer_alarm", timer_alarm, 2.00, False),
]

def render(name, builder, seconds, loop):
    rng = random.Random(sum(map(ord, name)))
    buf = builder(rng)
    assert len(buf) == frames(seconds), (name, len(buf), frames(seconds))
    return finish(buf, loop=loop)

def write_wav(path, buf):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(round(x * 32767))))) for x in buf))

def stats(name, buf, loop):
    n = len(buf)
    peak = max(abs(x) for x in buf)
    rms = math.sqrt(sum(x * x for x in buf) / n)
    clipped = sum(1 for x in buf if abs(x) >= 0.999)
    step = max(abs(buf[i + 1] - buf[i]) for i in range(n - 1))
    seam = abs(buf[0] - buf[-1])
    # energy in the last 50 ms relative to overall: a tail that is still loud means a cut-off
    tail = math.sqrt(sum(x * x for x in buf[-frames(0.03):]) / frames(0.03))
    flag = ""
    if clipped or peak > 0.95: flag += " CLIP"
    if step > 0.25: flag += " STEP"
    if not loop and (abs(buf[0]) > 1e-4 or abs(buf[-1]) > 1e-4): flag += " EDGE"
    if not loop and tail > rms * 0.2: flag += " TAIL"
    return "%-24s %5.2fs peak %.3f rms %.3f (%.1f dBFS) max-step %.3f seam %.4f tail-rms %.4f%s" % (
        name, n / SR, peak, rms, 20 * math.log10(rms), step, seam, tail, flag)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--convert", metavar="DIR")
    ap.add_argument("--only")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    if args.convert: os.makedirs(args.convert, exist_ok=True)
    bad = False
    for name, builder, seconds, loop in SOUNDS:
        if args.only and args.only != name: continue
        buf = render(name, builder, seconds, loop)
        wav = os.path.join(args.out, name + ".wav")
        write_wav(wav, buf)
        line = stats(name, buf, loop)
        if args.stats: print(line)
        bad |= any(f in line for f in ("CLIP", "STEP", "EDGE", "TAIL"))
        if args.convert:
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", "-s", "3", wav, os.path.join(args.convert, name + ".m4a")], check=True)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
