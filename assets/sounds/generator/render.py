#!/usr/bin/env python3
"""Render the UI sound set and verify each result against its written spec.

The verification pass is the point: it measures duration, attack time,
brightness, spectral decay, level and headroom, and fails loudly if a sound
does not actually match the character docs/SOUND_SETUP.md asks for, rather
than trusting that the synthesis code did what it was supposed to.
"""
import os
import sys

import numpy as np
import soundfile as sf

from dsp import SR, db, k_weight, lufs_ish
from sounds import SOUNDS

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Brightness (spectral centroid, Hz) each cue should land in, straight from
# its spec wording -- "soft glass tick" and "warm muted low pulse" cannot
# both be correct at the same centroid.
EXPECT_CENTROID = {
    "ui_hover": (1800, 6000),           # glass: bright
    "ui_press": (700, 3000),            # glossy click: upper-mid
    "ui_panel_open": (500, 2600),       # airy bloom
    "ui_panel_close": (250, 1500),      # darker than open
    "ui_success": (700, 3000),          # clean chime
    "ui_error": (60, 420),              # warm, muted, low
    "ui_queue": (500, 2600),            # metallic but not shrill
    "ui_generation_ready": (900, 3400),  # polished, bright
    "ui_like": (350, 1800),             # soft pop
    "ui_purchase_prompt": (300, 1600),   # warm rising tone
}

# Sounds that model a struck/plucked body must darken as they decay --
# frequency-dependent damping is what separates them from a sine stack.
MUST_DARKEN = {"ui_hover", "ui_press", "ui_queue", "ui_success", "ui_generation_ready"}

# Gesture cues swell in; impact cues must strike immediately.
EXPECT_ATTACK_MS = {
    "ui_hover": (0.0, 6.0),
    "ui_press": (0.0, 8.0),
    "ui_panel_open": (40.0, 170.0),
    "ui_panel_close": (8.0, 90.0),
    "ui_success": (0.0, 20.0),
    "ui_error": (3.0, 40.0),
    "ui_queue": (0.0, 12.0),
    "ui_generation_ready": (0.0, 25.0),
    "ui_like": (2.0, 30.0),
    "ui_purchase_prompt": (25.0, 170.0),
}


def centroid(sig):
    if not np.any(sig):
        return 0.0
    win = np.hanning(len(sig))
    spec = np.abs(np.fft.rfft(sig * win))
    freqs = np.fft.rfftfreq(len(sig), 1 / SR)
    total = spec.sum()
    return float((spec * freqs).sum() / total) if total else 0.0


def attack_ms(sig):
    """Time for the sound to reach full level at its *first* onset.

    Measuring to 90% of the global peak is wrong for a multi-note cue: on an
    ascending three-note chime the loudest moment is the last note, which
    would report a ~190 ms "attack" for a sound that actually strikes
    instantly. Referencing the peak of the opening window measures how fast
    the cue starts, which is what attack means to a listener.
    """
    env = np.abs(sig)
    if not np.any(env):
        return 0.0
    head = env[: min(len(env), int(SR * 0.06))]
    ref = head.max() if head.size else env.max()
    if ref <= 0:
        return 0.0
    idx = int(np.argmax(env >= ref * 0.9))
    return idx / SR * 1000.0


def dc_offset(sig):
    return float(np.mean(sig))


def near_nyquist_ratio(sig):
    """Fraction of spectral energy above 19 kHz.

    FM sidebands and swept partials can fold back over Nyquist and alias into
    audible grit that no envelope will hide. Real content up there is almost
    nil for these cues, so a meaningful reading means something is folding.
    """
    spec = np.abs(np.fft.rfft(sig * np.hanning(len(sig)))) ** 2
    freqs = np.fft.rfftfreq(len(sig), 1 / SR)
    total = spec.sum()
    if not total:
        return 0.0
    return float(spec[freqs >= 19000].sum() / total)


# Roblox accepts .wav/.flac/.mp3/.ogg and transcodes everything on upload, so
# the right thing to hand it is lossless: an OGG master would be encoded twice
# (here, then again by Roblox) for no benefit. That double encode measurably
# smeared the sharp transient on ui_press by ~13% in brightness. 24-bit PCM
# also means no dither stage, so no quantization noise in the quiet tails.
WAV_SUBTYPE = "PCM_24"


def analyze(name, sig, lo_s, hi_s):
    problems = []
    dur = len(sig) / SR
    if not (lo_s - 1e-4 <= dur <= hi_s + 1e-4):
        problems.append(f"duration {dur*1000:.0f}ms outside spec {lo_s*1000:.0f}-{hi_s*1000:.0f}ms")

    peak = float(np.max(np.abs(sig)))
    if peak > 0.72:
        problems.append(f"peak {peak:.2f} too hot")
    if peak < 0.08:
        problems.append(f"peak {peak:.2f} too quiet")

    off = dc_offset(sig)
    if abs(off) > 1e-3:
        problems.append(f"DC offset {off:.4f}")

    if abs(sig[0]) > 1e-3 or abs(sig[-1]) > 1e-3:
        problems.append("buffer does not start/end at silence")

    c = centroid(sig)
    clo, chi = EXPECT_CENTROID[name]
    if not (clo <= c <= chi):
        problems.append(f"centroid {c:.0f}Hz outside expected {clo}-{chi}Hz")

    a = attack_ms(sig)
    alo, ahi = EXPECT_ATTACK_MS[name]
    if not (alo <= a <= ahi):
        problems.append(f"attack {a:.1f}ms outside expected {alo}-{ahi}ms")

    third = len(sig) // 3
    c_head = centroid(sig[:third])
    c_tail = centroid(sig[2 * third:])
    if name in MUST_DARKEN and c_tail >= c_head * 0.95:
        problems.append(f"does not darken as it decays ({c_head:.0f} -> {c_tail:.0f}Hz)")

    alias = near_nyquist_ratio(sig)
    if alias > 1e-4:
        problems.append(f"{alias*100:.3f}% of energy above 19kHz (aliasing?)")

    loud = lufs_ish(sig)
    return {
        "dur_ms": dur * 1000, "peak": peak, "loud": loud, "centroid": c,
        "attack_ms": a, "c_head": c_head, "c_tail": c_tail, "alias": alias,
        "problems": problems,
    }


def main():
    os.makedirs(f"{OUT}/wav", exist_ok=True)

    rows, failed = [], 0
    loudness = {}

    for name, (fn, (lo_s, hi_s)) in SOUNDS.items():
        sig = np.asarray(fn(), dtype=np.float64)
        report = analyze(name, sig, lo_s, hi_s)
        loudness[name] = report["loud"]

        sf.write(f"{OUT}/wav/{name}.wav", sig.astype(np.float64), SR,
                 subtype=WAV_SUBTYPE)

        rows.append((name, report))
        if report["problems"]:
            failed += 1

    w = max(len(n) for n in SOUNDS)
    print(f"{'sound'.ljust(w)}  {'ms':>6} {'peak':>5} {'loud':>7} {'centr':>7} "
          f"{'atk_ms':>7} {'bright decay':>16}")
    print("-" * (w + 56))
    for name, r in rows:
        print(f"{name.ljust(w)}  {r['dur_ms']:6.0f} {r['peak']:5.2f} {r['loud']:7.1f} "
              f"{r['centroid']:7.0f} {r['attack_ms']:7.1f} "
              f"{r['c_head']:7.0f} -> {r['c_tail']:6.0f}")

    print()
    lo, hi = min(loudness.values()), max(loudness.values())
    print(f"loudness spread across the set: {hi - lo:.1f} dB "
          f"(quietest {min(loudness, key=loudness.get)}, "
          f"loudest {max(loudness, key=loudness.get)})")

    print()
    if failed:
        for name, r in rows:
            for p in r["problems"]:
                print(f"  FAIL  {name}: {p}")
        print(f"\n{failed} sound(s) failed spec verification")
        return 1
    print("all 10 sounds verified against spec")
    return 0


if __name__ == "__main__":
    sys.exit(main())
