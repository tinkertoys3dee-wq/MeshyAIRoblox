"""The ten Forge UGC UI cues, built to docs/SOUND_SETUP.md's spec.

Each sound is modeled on how the object in its written description actually
behaves -- glass and metal get real inharmonic mode ratios with
frequency-dependent damping, chimes are FM bells whose brightness decays
faster than their amplitude, the "pop" follows a collapsing-bubble pitch rise
-- rather than being approximated with a plain sine and an exponential fade.
"""
import numpy as np

from dsp import (
    SR, NYQ, t_axis, db, rng,
    sos_lowpass, sos_highpass, sos_bandpass,
    perc_env, swell_env, phase_sweep, modal, fm_voice, noise_burst, air,
    saturate, reverb_ir, apply_reverb, place, finalize,
)

# Measured mode ratios for real struck bodies. These are what make a sound
# read as "glass" or "metal" rather than as a stack of harmonics -- a
# harmonic series (1, 2, 3, 4...) always sounds like a musical instrument,
# never like a tapped object.
GLASS_MODES = [1.0, 2.38, 4.36, 6.85, 9.81, 13.1]      # small glass vessel
METAL_BAR_MODES = [1.0, 2.756, 5.404, 8.933, 13.34]     # free-free bar
PLATE_MODES = [1.0, 1.59, 2.14, 2.65, 3.31, 4.20]       # small stiff plate


def swept_modal(t, f_start, f_end, ratios, amps, tau0, damp_exp=0.7,
                sweep_shape="exp", seed=0):
    """Modal bank whose whole body glides in pitch.

    Needed for anything that both has a struck-object timbre and moves in
    pitch (a dropping metal object): the partials have to stay locked to
    their inharmonic ratios while the fundamental slides, which a fixed-pitch
    resonator bank can't do.
    """
    dur = t[-1] if len(t) else 1.0
    frac = t / dur if dur else t
    base = f_start * (f_end / f_start) ** frac if sweep_shape == "exp" \
        else f_start + (f_end - f_start) * frac
    r = rng(seed)
    out = np.zeros_like(t)
    for ratio, amp in zip(ratios, amps):
        inst = np.clip(base * ratio, 1.0, NYQ * 0.95)
        if inst[0] >= NYQ * 0.92:
            continue
        phase = 2 * np.pi * np.cumsum(inst) / SR + r.uniform(0, 2 * np.pi)
        tau = tau0 * (f_start / (f_start * ratio)) ** damp_exp
        out += amp * np.sin(phase) * np.exp(-t / tau)
    return out


def decay_amps(n, rolloff=0.62):
    return [rolloff ** i for i in range(n)]


# ------------------------------------------------------- 1. Hover (60-90 ms)

def hover():
    """Soft glass tick: a fingernail-light tap on a small glass vessel.

    Two parts, as in the real thing -- a broadband contact transient of a
    couple of milliseconds, then the glass body ringing its inharmonic modes
    and darkening rapidly as the high partials shed energy first.
    """
    dur = 0.078
    t = t_axis(dur)

    # Pitched down from the first pass: this cue fires on every pointer move,
    # and a ~4 kHz centroid that reads fine in isolation becomes listening
    # fatigue when it repeats a few hundred times a session. Still clearly
    # glass, just a slightly larger, warmer piece of it.
    body = modal(t, 1950, GLASS_MODES, decay_amps(6, 0.52),
                 tau0=0.021, damp_exp=0.88, seed=11, jitter=0.004)

    # Contact noise: brief, and gone almost immediately.
    contact = noise_burst(0.006, 2800, 8000, tau=0.0015, seed=12) * 0.42

    sig = body * perc_env(t, 0.026, attack=0.0006, curve=1.15)
    sig[:len(contact)] += contact
    sig = sos_lowpass(sig, 7000)
    sig = apply_reverb(sig, wet=0.07, dur=0.10, lo=800, hi=6000, damping=6.0, seed=13)
    return finalize(sig, dur, target_db=-17.0, peak_ceiling=0.46, hp=260)


# ------------------------------------------------------- 2. Press (90-130 ms)

def press():
    """Compact glossy click: a small, well-damped resonant body.

    "Glossy" is the resonance -- a tight mid band that rings just long enough
    to sound solid rather than dry -- plus gentle saturation, which rounds
    the transient the way a polished surface does.
    """
    dur = 0.115
    t = t_axis(dur)

    body = modal(t, 1180, PLATE_MODES, decay_amps(6, 0.58),
                 tau0=0.030, damp_exp=0.75, seed=21, jitter=0.006)
    # A touch of downward glide makes the hit feel like it lands.
    glide = phase_sweep(1500, 1050, t, shape="log") * 0.35 * perc_env(t, 0.016)

    click = noise_burst(0.010, 1600, 7000, tau=0.0022, seed=22) * 0.7

    sig = (body * 0.85 + glide) * perc_env(t, 0.034, attack=0.0008, curve=1.2)
    sig[:len(click)] += click
    sig = saturate(sig * 1.5, drive=1.6) * 0.7
    # Dark, fast reverb: a bright tail was holding the top end up and stopping
    # the click from darkening as it decayed, which made it read as a buzz
    # rather than as a struck body.
    sig = apply_reverb(sig, wet=0.08, dur=0.10, lo=400, hi=3200, damping=7.0, seed=23)
    # Progressive top-end roll-off over the decay, standing in for the air
    # absorption and internal damping a real small body has.
    tail_tilt = np.linspace(1.0, 0.0, len(sig)) ** 0.8
    sig = sos_lowpass(sig, 2600) * (1 - tail_tilt) + sig * tail_tilt
    return finalize(sig, dur, target_db=-14.5, peak_ceiling=0.62, hp=140)


# -------------------------------------------------- 3. PanelOpen (250-350 ms)

def panel_open():
    """Airy upward synth bloom.

    Three slightly detuned voices sweeping up together -- the detuning gives
    slow beating that keeps it from sounding like one sterile oscillator --
    under a band of rising air noise, with the whole thing opening up through
    a filter as it swells.
    """
    dur = 0.31
    t = t_axis(dur)

    env = swell_env(t, attack=0.075, hold=0.055, release=0.18, ease=1.9)

    voices = np.zeros_like(t)
    for i, (detune, amp, octave) in enumerate([
        (1.000, 1.00, 1.0),
        (1.0045, 0.55, 1.0),
        (0.9962, 0.45, 2.0),
        (1.007, 0.22, 3.0),
    ]):
        voices += amp * phase_sweep(270 * octave * detune,
                                    1020 * octave * detune, t, shape="exp")
    voices /= 2.2

    breath = air(dur, 900, 5200, swell_env(t, 0.10, 0.05, 0.16, ease=1.4), seed=31) * 0.30

    sig = voices * env + breath
    # Filter opens with the swell: dark at the start, bright at the peak.
    bright = sos_highpass(sig, 400) * 0.55
    sig = sos_lowpass(sig, 5200) + bright * np.linspace(0, 1, len(sig)) ** 1.4
    sig = apply_reverb(sig, wet=0.24, dur=0.32, lo=300, hi=6500, damping=4.2, seed=32)
    return finalize(sig, dur, target_db=-13.5, peak_ceiling=0.64, hp=90)


# ------------------------------------------------- 4. PanelClose (180-250 ms)

def panel_close():
    """Quiet reverse bloom: the open gesture inverted and damped.

    Faster, darker and softer than the open -- closing should acknowledge,
    not announce, so it loses the air layer and most of the top end.
    """
    dur = 0.22
    t = t_axis(dur)

    env = swell_env(t, attack=0.018, hold=0.030, release=0.165, ease=1.5)

    voices = np.zeros_like(t)
    for detune, amp, octave in [(1.000, 1.00, 1.0), (0.9955, 0.5, 1.0), (1.004, 0.3, 2.0)]:
        voices += amp * phase_sweep(940 * octave * detune,
                                    300 * octave * detune, t, shape="exp")
    voices /= 1.8

    breath = air(dur, 600, 2600, swell_env(t, 0.02, 0.02, 0.17, ease=1.3), seed=41) * 0.16

    sig = voices * env + breath
    sig = sos_lowpass(sig, 3200)
    sig = apply_reverb(sig, wet=0.18, dur=0.24, lo=250, hi=4200, damping=5.0, seed=42)
    return finalize(sig, dur, target_db=-15.0, peak_ceiling=0.54, hp=80)


# ----------------------------------------------------- 5. Success (400-600 ms)

def success():
    """Restrained two-note digital chime -- A5 up a perfect fourth to D6.

    FM bells rather than sines: the modulation index decays faster than the
    amplitude, so each note strikes bright and inharmonic then settles into a
    clean tone. "Restrained" means a low index and a short-ish tail -- this
    fires on every saved fit, so it can't be a fanfare.
    """
    dur = 0.54
    parts = []

    for i, (freq, t0, tail, amp) in enumerate([
        (880.00, 0.000, 0.150, 1.00),   # A5
        (1174.66, 0.135, 0.215, 0.92),  # D6
    ]):
        tn = t_axis(tail + 0.16)
        bell = fm_voice(tn, freq, ratio=3.0, index0=1.9,
                        index_tau=0.030, amp_tau=tail, amp_curve=1.15)
        # Detuned partner an octave up, quiet: adds sparkle without brightening
        # the fundamental.
        shimmer = fm_voice(tn, freq * 2.003, ratio=2.0, index0=0.7,
                           index_tau=0.020, amp_tau=tail * 0.55) * 0.16
        # Sub layer for body so it doesn't read as thin on phone speakers.
        sub = np.sin(2 * np.pi * (freq / 2) * tn) * perc_env(tn, tail * 0.7) * 0.13
        parts.append(((bell + shimmer + sub) * amp, t0))

    sig = place(dur, parts)
    sig = sos_lowpass(sig, 9000)
    sig = apply_reverb(sig, wet=0.20, dur=0.34, lo=350, hi=7500, damping=4.0, seed=51)
    return finalize(sig, dur, target_db=-12.5, peak_ceiling=0.70, hp=100)


# ------------------------------------------------------- 6. Error (220-350 ms)

def error():
    """Warm muted low pulse.

    A slight downward pitch bend is what makes it read as negative without
    being harsh -- falling pitch is the universal cue. Heavy lowpass plus
    tanh saturation gives the warmth; there's deliberately almost no reverb,
    because "muted" means close and dry.
    """
    dur = 0.30
    t = t_axis(dur)

    fund = phase_sweep(158, 116, t, shape="log")
    sub = phase_sweep(79, 58, t, shape="log") * 0.55
    # A weak third harmonic thickens it into a "pulse" rather than a pure tone.
    third = phase_sweep(474, 348, t, shape="log") * 0.10

    env = perc_env(t, 0.105, attack=0.009, curve=1.35)
    sig = (fund + sub + third) * env
    sig = saturate(sig * 1.35, drive=1.9) * 0.72
    sig = sos_lowpass(sig, 780, order=4)
    sig = apply_reverb(sig, wet=0.06, dur=0.14, lo=120, hi=1800, damping=6.0, seed=61)
    return finalize(sig, dur, target_db=-13.0, peak_ceiling=0.70, hp=48)


# ------------------------------------------------------- 7. Queue (200-300 ms)

def queue():
    """Subtle metallic drop: a small metal part falling into place.

    Uses free-free bar mode ratios (1 : 2.76 : 5.40 : 8.93 : 13.3), which is
    what actually makes metal sound like metal, and slides the whole mode
    bank downward so the object reads as dropping rather than just ringing.
    """
    dur = 0.265
    t = t_axis(dur)

    body = swept_modal(t, 980, 430, METAL_BAR_MODES, decay_amps(5, 0.60),
                       tau0=0.085, damp_exp=0.80, sweep_shape="exp", seed=71)

    contact = noise_burst(0.012, 2000, 9000, tau=0.0028, seed=72) * 0.45

    sig = body * perc_env(t, 0.095, attack=0.0010, curve=1.25)
    sig[:len(contact)] += contact
    sig = sos_lowpass(sig, 7000)
    sig = apply_reverb(sig, wet=0.16, dur=0.24, lo=300, hi=6000, damping=4.8, seed=73)
    return finalize(sig, dur, target_db=-14.0, peak_ceiling=0.58, hp=120)


# --------------------------------------------- 8. GenerationReady (700-950 ms)

def generation_ready():
    """Polished three-note reveal -- an ascending C major triad, C6-E6-G6.

    The payoff cue, so it gets the longest tails, the most reverb, and a
    shimmer layer that swells underneath the third note. Each note still
    starts bright and settles, same FM bell construction as Success, but with
    a higher index and longer decay so it rings rather than ticks.
    """
    dur = 0.88
    parts = []

    for freq, t0, tail, amp in [
        (1046.50, 0.000, 0.230, 0.92),  # C6
        (1318.51, 0.175, 0.260, 0.96),  # E6
        (1567.98, 0.350, 0.400, 1.00),  # G6
    ]:
        tn = t_axis(tail + 0.22)
        # Ratio 2.0 at a moderate index keeps the sidebands close to
        # octave-related, which is what "polished" sounds like. The 3.5 ratio
        # and higher index this started with scattered energy up past 4 kHz
        # and read as tinkly/cheap rather than as a finished reveal.
        bell = fm_voice(tn, freq, ratio=2.0, index0=1.6,
                        index_tau=0.042, amp_tau=tail, amp_curve=1.1)
        shimmer = fm_voice(tn, freq * 2.004, ratio=2.0, index0=0.6,
                           index_tau=0.028, amp_tau=tail * 0.6) * 0.13
        sub = np.sin(2 * np.pi * (freq / 2) * tn) * perc_env(tn, tail * 0.8) * 0.20
        parts.append(((bell + shimmer + sub) * amp, t0))

    # Slow swell under the final note -- the "reveal" lift. Kept an octave
    # lower than the first attempt so it adds weight, not glare.
    lift_t = t_axis(0.42)
    lift = (np.sin(2 * np.pi * 1046.5 * lift_t) * 0.5
            + np.sin(2 * np.pi * 1568.0 * lift_t) * 0.28)
    lift *= swell_env(lift_t, attack=0.20, hold=0.02, release=0.19, ease=2.2) * 0.11
    parts.append((lift, 0.33))

    sig = place(dur, parts)
    sig = sos_lowpass(sig, 7200)
    sig = apply_reverb(sig, wet=0.28, dur=0.48, lo=300, hi=8000, damping=3.4, seed=81)
    return finalize(sig, dur, target_db=-11.8, peak_ceiling=0.72, hp=100)


# --------------------------------------------------------- 9. Like (100-180 ms)

def like():
    """Tiny soft pop.

    A collapsing bubble rises in pitch as it closes, which is why a rising
    sine reads as a "pop" and a falling one reads as a "blip". Nearly pure
    tone, rounded attack, no transient click at all -- the softness is the
    whole point.
    """
    dur = 0.150
    t = t_axis(dur)

    fund = phase_sweep(430, 980, t, shape="log")
    second = phase_sweep(860, 1960, t, shape="log") * 0.13

    env = perc_env(t, 0.042, attack=0.0055, curve=1.5)
    sig = (fund + second) * env
    sig = sos_lowpass(sig, 4200)
    sig = apply_reverb(sig, wet=0.10, dur=0.14, lo=350, hi=5000, damping=5.5, seed=91)
    return finalize(sig, dur, target_db=-15.0, peak_ceiling=0.56, hp=180)


# ----------------------------------------------- 10. PurchasePrompt (300-450 ms)

def purchase_prompt():
    """Low-volume rising confirmation tone.

    Deliberately the most neutral cue in the set: it plays immediately before
    Roblox's own purchase modal, so it should read as "here comes a
    decision", never as a reward. Root plus a fifth rising together, warm
    triangle-ish timbre, slow attack, quiet.
    """
    dur = 0.41
    t = t_axis(dur)

    root = phase_sweep(392.0, 523.25, t, shape="log")          # G4 -> C5
    fifth = phase_sweep(587.33, 783.99, t, shape="log") * 0.45  # D5 -> G5
    # Weak odd harmonic gives a triangle-ish warmth rather than a bare sine.
    colour = phase_sweep(1176.0, 1569.0, t, shape="log") * 0.09

    env = swell_env(t, attack=0.055, hold=0.135, release=0.20, ease=1.7)
    sig = (root + fifth + colour) * env
    sig = saturate(sig * 1.15, drive=1.3) * 0.85
    sig = sos_lowpass(sig, 4800)
    sig = apply_reverb(sig, wet=0.15, dur=0.26, lo=250, hi=5000, damping=4.6, seed=101)
    return finalize(sig, dur, target_db=-14.5, peak_ceiling=0.58, hp=100)


SOUNDS = {
    "ui_hover": (hover, (0.060, 0.090)),
    "ui_press": (press, (0.090, 0.130)),
    "ui_panel_open": (panel_open, (0.250, 0.350)),
    "ui_panel_close": (panel_close, (0.180, 0.250)),
    "ui_success": (success, (0.400, 0.600)),
    "ui_error": (error, (0.220, 0.350)),
    "ui_queue": (queue, (0.200, 0.300)),
    "ui_generation_ready": (generation_ready, (0.700, 0.950)),
    "ui_like": (like, (0.100, 0.180)),
    "ui_purchase_prompt": (purchase_prompt, (0.300, 0.450)),
}
