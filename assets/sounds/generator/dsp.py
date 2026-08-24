"""Shared synthesis primitives for the Forge UGC UI sound set.

Everything here is generated from first principles -- modal resonators, FM
operators, filtered noise, and a small synthetic reverb -- so the resulting
sounds are original, non-vocal, and contain no sampled or third-party audio.
"""
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 44100
NYQ = SR / 2


# ---------------------------------------------------------------- utilities

def t_axis(duration):
    return np.arange(int(round(SR * duration))) / SR


def db(x):
    return 10 ** (x / 20.0)


def sos_lowpass(sig, hz, order=4):
    hz = min(hz, NYQ * 0.98)
    return sosfilt(butter(order, hz / NYQ, btype="low", output="sos"), sig)


def sos_highpass(sig, hz, order=2):
    hz = max(min(hz, NYQ * 0.98), 1.0)
    return sosfilt(butter(order, hz / NYQ, btype="high", output="sos"), sig)


def sos_bandpass(sig, lo, hi, order=2):
    lo = max(lo, 1.0)
    hi = min(hi, NYQ * 0.98)
    return sosfilt(butter(order, [lo / NYQ, hi / NYQ], btype="band", output="sos"), sig)


def rng(seed):
    return np.random.default_rng(seed)


# ---------------------------------------------------------------- envelopes

def perc_env(t, tau, attack=0.0015, curve=1.0):
    """Percussive envelope: near-instant attack, exponential decay.

    `curve` > 1 makes the decay start faster then linger (more natural for
    struck bodies than a pure exponential).
    """
    env = np.exp(-(t / tau) ** curve)
    a = max(int(SR * attack), 1)
    if a > 1:
        # Raised-cosine attack: no DC step, so no click at sample 0.
        env[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    return env


def swell_env(t, attack, hold, release, ease=2.0):
    """Smooth attack / hold / release, all raised-cosine shaped."""
    n = len(t)
    env = np.zeros(n)
    a = int(SR * attack)
    h = int(SR * hold)
    r = int(SR * release)
    a = min(a, n)
    h = min(h, n - a)
    r = min(r, n - a - h)
    idx = 0
    if a:
        env[idx:idx + a] = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))) ** (1 / ease)
        idx += a
    if h:
        env[idx:idx + h] = 1.0
        idx += h
    if r:
        env[idx:idx + r] = (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))) ** ease
        idx += r
    if idx < n:
        env[idx:] = 0.0
    return env


def edge_fade(sig, in_ms=0.4, out_ms=3.0):
    """Guarantee the buffer starts and ends at silence.

    The fade-in is deliberately very short and asymmetric with the fade-out.
    Every envelope here already opens from zero, so the only job at the head
    is insuring against a DC step -- a symmetric multi-millisecond fade there
    would instead blunt the transient, which for a "tick" or "click" is the
    entire character of the sound.
    """
    sig = sig.copy()
    ni = min(max(int(SR * in_ms / 1000.0), 2), len(sig) // 2)
    no = min(max(int(SR * out_ms / 1000.0), 2), len(sig) // 2)
    sig[:ni] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ni))
    sig[-no:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, no))
    return sig


# ---------------------------------------------------------------- oscillators

def phase_sweep(f0, f1, t, shape="exp"):
    """Anti-alias-safe swept sine via integrated instantaneous frequency."""
    dur = t[-1] if len(t) else 1.0
    frac = t / dur if dur else t
    if shape == "exp":
        inst = f0 * (f1 / f0) ** frac
    elif shape == "log":
        # Fast move first, settling toward f1 -- reads as a "landing".
        inst = f0 + (f1 - f0) * (1 - np.exp(-4 * frac)) / (1 - np.exp(-4))
    else:
        inst = f0 + (f1 - f0) * frac
    inst = np.clip(inst, 1.0, NYQ * 0.95)
    return np.sin(2 * np.pi * np.cumsum(inst) / SR)


def modal(t, f0, ratios, amps, tau0, damp_exp=0.7, seed=0, jitter=0.0):
    """Modal (struck-body) resonator bank.

    Frequency-dependent damping is the thing that separates a real struck
    object from a stack of sine waves: high partials shed energy far faster
    than the fundamental, so the tone darkens as it decays. `damp_exp`
    controls how strongly -- 0 is uniform decay, ~1 is glassy/metallic.
    """
    r = rng(seed)
    out = np.zeros_like(t)
    for ratio, amp in zip(ratios, amps):
        f = f0 * ratio
        if jitter:
            f *= 1.0 + r.uniform(-jitter, jitter)
        if f >= NYQ * 0.92:
            continue
        tau = tau0 * (f0 / f) ** damp_exp
        phase = r.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * f * t + phase) * np.exp(-t / tau)
    return out


def fm_voice(t, carrier, ratio, index0, index_tau, amp_tau, amp_curve=1.0):
    """Two-operator FM -- the standard way to get a bell/chime timbre.

    The modulation index decays faster than the amplitude, so the tone starts
    bright and inharmonic then settles toward a clean sine, exactly how a
    struck bell behaves.
    """
    index = index0 * np.exp(-t / index_tau)
    mod = index * np.sin(2 * np.pi * carrier * ratio * t)
    return np.sin(2 * np.pi * carrier * t + mod) * perc_env(t, amp_tau, curve=amp_curve)


def noise_burst(dur, lo, hi, tau, seed=0, order=2):
    t = t_axis(dur)
    n = sos_bandpass(rng(seed).standard_normal(len(t)), lo, hi, order=order)
    return n * np.exp(-t / tau)


def air(dur, lo, hi, env, seed=0):
    t = t_axis(dur)
    n = sos_bandpass(rng(seed).standard_normal(len(t)), lo, hi)
    return n * env


# ---------------------------------------------------------------- processing

def saturate(sig, drive=1.0):
    """Soft asymmetric-free tanh saturation: adds warmth, tames peaks."""
    return np.tanh(sig * drive) / np.tanh(drive)


def reverb_ir(dur=0.28, lo=200, hi=6500, damping=4.0, seed=7, predelay=0.006):
    """Small synthetic room: exponentially decaying, band-limited noise.

    Cheap, but for the ~200ms tails these sounds want it reads as real space
    and keeps the cues from sounding like they were recorded inside a box.
    """
    t = t_axis(dur)
    n = rng(seed).standard_normal(len(t))
    n = sos_bandpass(n, lo, hi)
    n *= np.exp(-damping * t / dur)
    # Progressive lowpass smear so the tail darkens as it decays.
    n = sos_lowpass(n, hi) * 0.7 + sos_lowpass(n, hi * 0.35) * 0.3
    pd = int(SR * predelay)
    ir = np.concatenate([np.zeros(pd), n])
    ir /= np.max(np.abs(ir)) or 1.0
    return ir


def apply_reverb(sig, wet=0.16, ir=None, **kw):
    if wet <= 0:
        return sig
    ir = reverb_ir(**kw) if ir is None else ir
    tail = fftconvolve(sig, ir)[: len(sig) + len(ir)]
    tail /= np.max(np.abs(tail)) or 1.0
    out = np.concatenate([sig, np.zeros(len(tail) - len(sig))])
    return out * (1 - wet) + tail * wet


def place(total_dur, parts):
    """Mix (signal, start_time) pairs onto one buffer."""
    out = np.zeros(int(round(SR * total_dur)))
    for sig, t0 in parts:
        s = int(round(SR * t0))
        e = s + len(sig)
        if e > len(out):
            sig = sig[: len(out) - s]
            e = len(out)
        if s < len(out):
            out[s:e] += sig
    return out


# ---------------------------------------------------------------- loudness

def k_weight(sig):
    """Rough ITU-R BS.1770 style weighting for perceptual level matching."""
    x = sos_highpass(sig, 80, order=2)
    shelf = sos_highpass(x, 1800, order=1) * db(4.0)
    return x + shelf


def lufs_ish(sig, gate_db=-20.0):
    """Gated weighted RMS.

    Ungated RMS over the whole buffer would rate an 820 ms chime -- loud for
    200 ms, then a long quiet tail -- as far quieter than a 110 ms click that
    is loud throughout, which is the opposite of how they actually sit next
    to each other. Gating to the portion within `gate_db` of the peak
    measures the part a listener actually judges the level by.
    """
    w = k_weight(sig)
    if not len(w):
        return -120.0
    peak = np.max(np.abs(w)) or 1e-9
    loud = w[np.abs(w) >= peak * db(gate_db)]
    if len(loud) < 8:
        loud = w
    rms = np.sqrt(np.mean(loud ** 2)) or 1e-9
    return 20 * np.log10(rms)


def normalize_loudness(sig, target_db, peak_ceiling=0.5):
    """Match perceived loudness, then hard-guarantee peak headroom.

    Peak normalization alone makes a 75 ms tick and an 820 ms chime with the
    same peak feel wildly different in level, so level-matching is done on a
    weighted RMS and the peak only acts as a ceiling.
    """
    sig = sig - np.mean(sig)
    cur = lufs_ish(sig)
    sig = sig * db(target_db - cur)
    peak = np.max(np.abs(sig)) or 1.0
    if peak > peak_ceiling:
        sig = sig * (peak_ceiling / peak)
    return sig


def fit_duration(sig, duration):
    """Trim or pad to exactly `duration`, ending in silence.

    Reverb extends a buffer past what was synthesized, so the tail is cut
    back to the length the spec asks for rather than letting the room decide
    how long a UI cue lasts.
    """
    n = int(round(SR * duration))
    if len(sig) > n:
        sig = sig[:n].copy()
    elif len(sig) < n:
        sig = np.concatenate([sig, np.zeros(n - len(sig))])
    return sig


def finalize(sig, duration, target_db, peak_ceiling=0.5, hp=45):
    sig = sos_highpass(sig, hp, order=2)
    sig = fit_duration(sig, duration)
    # Fade before normalizing, so the measured level is the level of the
    # finished file rather than of something the fade then quietly lowered.
    sig = edge_fade(sig)
    return normalize_loudness(sig, target_db, peak_ceiling)
