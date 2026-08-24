# UI sounds

The ten UI cues for `src/Shared/SoundIds.luau`, synthesized from scratch to
the character spec in `docs/SOUND_SETUP.md`. No samples, no recordings, no
third-party audio — every sound is generated from modal resonators, FM
operators, filtered noise and a small synthetic room, so the whole set is
original work that can be uploaded under your own creator/group without any
licensing question.

`wav/` is the whole deliverable: 44.1 kHz mono 24-bit PCM, which Roblox
accepts for upload directly. There's deliberately no lossy copy — Roblox
transcodes every upload anyway, so handing it an OGG would mean encoding
twice for no benefit (and measurably smeared the sharp transient on
`ui_press` when this set was first built that way). The same files open in
any editor if you want to trim or re-level one by hand.

| File | `SoundIds.luau` key | Spec'd direction | Length | How it's built |
|---|---|---|---|---|
| `ui_hover` | `Hover` | soft glass tick, 60–90 ms | 78 ms | glass mode ratios + contact transient |
| `ui_press` | `Press` | compact glossy click, 90–130 ms | 115 ms | plate modes, saturated, damped tail |
| `ui_panel_open` | `PanelOpen` | airy upward synth bloom, 250–350 ms | 310 ms | 4 detuned sweeps + air noise, filter opens |
| `ui_panel_close` | `PanelClose` | quiet reverse bloom, 180–250 ms | 220 ms | inverted sweep, darker and faster |
| `ui_success` | `Success` | restrained two-note digital chime, 400–600 ms | 540 ms | FM bells, A5 → D6 |
| `ui_error` | `Error` | warm muted low pulse, 220–350 ms | 300 ms | falling low sine, saturated, heavy lowpass |
| `ui_queue` | `Queue` | subtle metallic drop, 200–300 ms | 265 ms | free-free bar modes swept downward |
| `ui_generation_ready` | `GenerationReady` | polished three-note reveal, 700–950 ms | 880 ms | FM bells, C6–E6–G6 + swell |
| `ui_like` | `Like` | tiny soft pop, 100–180 ms | 150 ms | rising sine (collapsing-bubble curve) |
| `ui_purchase_prompt` | `PurchasePrompt` | low-volume rising confirmation, 300–450 ms | 410 ms | rising root + fifth, warm |

## Levels

Files sit within about 5 dB of each other by gated weighted-RMS rather than
being peak-normalized, because peak-matching a 78 ms tick against an 880 ms
chime leaves them sounding nothing alike in level. The per-cue "this one
should sit back" decision belongs to the mixer, not the asset:
`SoundController` sets `Hover` to `Volume` 0.22 and everything else to 0.42.
Baking a large spread into the files *as well* would stack both attenuations
and make the hover inaudible.

Peaks land between 0.20 and 0.58, leaving headroom for that volume scaling
and for Roblox's own transcode.

## Uploading

Roblox has no API for a script to upload audio, so this is manual, same as
the badge/product icons in `assets/icons/`:

1. Creator Hub → your experience or group → **Audio** → upload the file from
   `wav/`.
2. Wait for moderation to approve it.
3. Paste the numeric asset ID into the matching key in
   `src/Shared/SoundIds.luau`, replacing that key's `0`.

A key left at `0` just means `SoundController` skips creating a `Sound` for
it — nothing errors, that cue is simply silent until filled in.

## Regenerating

`generator/` builds the set and verifies it. Needs `numpy`, `scipy` and
`soundfile`; nothing at runtime depends on any of it.

```sh
cd assets/sounds/generator && python3 render.py
```

Every sound is parameterized (mode ratios, damping exponent, FM index,
envelope times, target loudness) rather than hand-drawn, so retuning one
means changing numbers in `sounds.py` and re-running.

`render.py` is not just a renderer — it measures each result against its
spec and fails if it doesn't match: duration inside the documented range,
attack time appropriate to the gesture (an impact cue must strike in under a
few ms; a bloom must actually swell), spectral centroid in the band its
description implies, struck-body sounds genuinely darkening as they decay,
level and headroom, DC offset, silent start/end, and no energy folding down
near Nyquist. That check is what caught the double-encode damage and a
too-bright first draft of `ui_generation_ready`, so keep it passing rather
than widening its bounds to accommodate a change.
