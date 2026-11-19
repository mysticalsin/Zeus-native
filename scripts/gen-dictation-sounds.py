#!/usr/bin/env python3
"""Renders Zeus's own "Crystal" dictation cues: start, stop and cancel.

Everything is synthesized here from sine partials (Python standard library only). Nothing is
sampled, downloaded or copied from any other app. Output is deterministic: the same script
always writes the same samples.

  scripts/gen-dictation-sounds.py                  writes the 16-bit WAV files into Sources/Zeus/Sounds
  scripts/gen-dictation-sounds.py --dest DIR       writes them somewhere else
  scripts/gen-dictation-sounds.py --stats          prints length and peak of each cue

The cues stay uncompressed WAV on purpose: they are tiny (about 20 KB each) and PCM starts with no
decoder priming, so the start cue sounds the instant the key goes down.

Design (44.1 kHz mono, peak -16 dBFS):
  start   two soft glass notes rising a fifth (A5 then E6), about 150 ms of tone and a short ring
  stop    the same two notes falling (E6 then A5)
  cancel  one gentle low blip (E4 gliding a little down), used for cancel and errors

Sources/ZeusCore/Sound/SoundCatalog.swift lists the files and their lengths; the Swift tests hold
the bundled files to those lengths.
"""
import argparse
import math
import os
import struct
import wave

SR = 44100
TAU = 2 * math.pi
PEAK_DBFS = -16.0

A5 = 880.0
E6 = 1318.51
E4 = 329.63

# Glass-like partials: (frequency ratio, level, decay multiplier). The slightly inharmonic
# upper partials give the "glassy" colour; they die away faster than the fundamental.
GLASS = ((1.0, 1.0, 1.0), (2.0, 0.22, 0.55), (2.76, 0.10, 0.4), (4.07, 0.035, 0.25))
# A quiet copy of each partial detuned by a few cents gives a gentle shimmer (slow beating).
SHIMMER_CENTS = 6.0
SHIMMER_LEVEL = 0.35


def raised_cosine(x):
    x = min(1.0, max(0.0, x))
    return 0.5 - 0.5 * math.cos(math.pi * x)


def glass_note(buf, start, freq, level, attack, decay):
    """Adds one struck glass note into buf: soft raised-cosine attack, exponential decay."""
    first = int(round(start * SR))
    detune = 2 ** (SHIMMER_CENTS / 1200.0)
    for i in range(first, len(buf)):
        t = (i - first) / SR
        if t > attack and math.exp(-t / decay) < 1e-5:
            break
        sample = 0.0
        for ratio, amp, decay_mul in GLASS:
            f = freq * ratio
            partial_env = math.exp(-t / (decay * decay_mul))
            sample += amp * partial_env * (math.sin(TAU * f * t) + SHIMMER_LEVEL * math.sin(TAU * f * detune * t + 0.7))
        buf[i] += level * raised_cosine(t / attack) * sample


def low_blip(buf, start, f0, f1, attack, decay):
    """Adds one soft low blip whose pitch glides from f0 towards f1."""
    first = int(round(start * SR))
    phase = 0.0
    for i in range(first, len(buf)):
        t = (i - first) / SR
        freq = f1 + (f0 - f1) * math.exp(-t / 0.05)
        phase += TAU * freq / SR
        env = raised_cosine(t / attack) * math.exp(-t / decay)
        buf[i] += env * (math.sin(phase) + 0.18 * math.sin(2 * phase) + 0.05 * math.sin(3 * phase))


def finish(buf, fade_out=0.02):
    """Normalizes to the target peak and fades the tail to exact silence."""
    peak = max(abs(x) for x in buf) or 1.0
    scale = (10 ** (PEAK_DBFS / 20.0)) / peak
    n_fade = int(fade_out * SR)
    out = []
    for i, x in enumerate(buf):
        from_end = len(buf) - 1 - i
        gain = raised_cosine(from_end / n_fade) if from_end < n_fade else 1.0
        out.append(x * scale * gain)
    out[0] = 0.0
    out[-1] = 0.0
    return out


def blank(seconds):
    return [0.0] * int(round(seconds * SR))


def crystal_start():
    buf = blank(0.26)
    glass_note(buf, 0.000, A5, 0.85, attack=0.004, decay=0.050)
    glass_note(buf, 0.065, E6, 1.00, attack=0.004, decay=0.070)
    return finish(buf)


def crystal_stop():
    buf = blank(0.26)
    glass_note(buf, 0.000, E6, 1.00, attack=0.004, decay=0.050)
    glass_note(buf, 0.065, A5, 0.85, attack=0.004, decay=0.075)
    return finish(buf)


def crystal_cancel():
    buf = blank(0.18)
    low_blip(buf, 0.0, E4, E4 * 0.89, attack=0.008, decay=0.045)
    return finish(buf)


# File name (without extension) -> renderer. Keep in sync with SoundCatalog.swift.
CUES = {
    "dictation_crystal_start": crystal_start,
    "dictation_crystal_stop": crystal_stop,
    "dictation_cancel": crystal_cancel,
}


def write_wav(path, samples):
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SR)
        out.writeframes(b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, s)) * 32767))) for s in samples))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest", default=os.path.join(root, "Sources", "Zeus", "Sounds"), help="where the WAV files go")
    parser.add_argument("--stats", action="store_true", help="print length and peak of each cue")
    args = parser.parse_args()
    os.makedirs(args.dest, exist_ok=True)
    for name, render in CUES.items():
        samples = render()
        write_wav(os.path.join(args.dest, name + ".wav"), samples)
        if args.stats:
            peak = max(abs(s) for s in samples)
            print(f"{name}: {len(samples) / SR:.3f} s, peak {20 * math.log10(peak):.1f} dBFS")


if __name__ == "__main__":
    main()
