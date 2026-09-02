#!/usr/bin/env python3
"""Export individual UI chrome pieces as transparent PNGs Roblox can hold as
Decals, sliced/sized to drop into Factory.luau's shared primitives (Card,
Button, Pill) plus the six nav icons and the brand mark.

Why these and not a screenshot of a whole page: Factory.Card/Button/Pill are
each defined ONCE and reused on every one of the app's 8 screens, so retexturing
those few shared pieces reskins the entire live app in one pass -- no need to
touch each page's layout code. Interactive pieces (real buttons, text boxes,
scroll frames) stay real Roblox Instances; these images only ever sit *behind*
them as a ScaleType.Slice or ScaleType.Fit background, via the new
Factory.ImageCard / Factory.ImageButton / Factory.ImagePill / Factory.Icon
helpers -- each with a code-drawn fallback when its asset id is still 0, so
nothing breaks before (or if) an upload happens.

Panels/pills get real gold-filigree corner ornaments (they're big enough to
carry the detail); buttons use a plainer gold-rimmed capsule (they get as
small as 27px tall, where fine scrollwork would just blur into mush).

Run:  python3 export_ui_assets.py
Output: assets/*.png + assets/manifest.json
"""

import json
import pathlib
import subprocess

from build_screens import DEFS, SERIF, SANS  # noqa: reuse the approved palette/fonts

HERE = pathlib.Path(__file__).parent
OUT = HERE / "assets"
OUT.mkdir(exist_ok=True)
CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"


from PIL import Image

# Headless Chrome's --window-size reserves a fixed ~88px of vertical chrome
# that never receives page content (confirmed against render.py, which has
# always requested +88 and cropped it back off for the full-page renders) --
# without this, every one of these small square assets got its bottom ~88px
# silently clipped to transparent. Request the overshoot, then crop in PIL.
CHROME_HEIGHT_OVERSHOOT = 88


def render(svg_body: str, w: int, h: int, name: str) -> None:
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">' \
          f'<defs>{DEFS}</defs>{svg_body}</svg>'
    svg_path = OUT / f"{name}.svg"
    svg_path.write_text(svg)
    html = OUT / "_r.html"
    html.write_text(
        '<!doctype html><meta charset="utf-8">'
        f'<style>html,body{{margin:0;background:transparent}}img{{display:block;width:{w}px;height:{h}px}}</style>'
        f'<img src="{svg_path.name}">'
    )
    raw = OUT / "_raw.png"
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
         "--default-background-color=00000000", "--force-device-scale-factor=1",
         f"--window-size={w},{h + CHROME_HEIGHT_OVERSHOOT}",
         f"--screenshot={raw}", f"file://{html}"],
        capture_output=True, check=True,
    )
    png = OUT / f"{name}.png"
    Image.open(raw).convert("RGBA").crop((0, 0, w, h)).save(png)
    raw.unlink()
    html.unlink()
    print("wrote", png.name)


# --------------------------------------------------------------------------
# Panel frame (Factory.Card): gold-filigree rounded rect, corner scrollwork,
# transparent middle. No sheen baked in -- Factory.Card keeps drawing its own
# Gloss/DropShadow children on top exactly as it does today, so this decal
# only ever replaces the flat-color fill layer underneath them.
# --------------------------------------------------------------------------
PANEL_SIZE = 240
PANEL_SLICE = 78  # px from each edge kept fixed; leaves a 84px stretch band


def panel_frame():
    s = PANEL_SIZE
    body = f'''
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="26" fill="url(#panelGlass)"/>
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="26" fill="none" stroke="url(#goldBar)" stroke-width="4"/>
  <rect x="13" y="13" width="{s-26}" height="{s-26}" rx="19" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.28"/>
  <use href="#cornerOrn" transform="translate(4,4)"/>
  <use href="#cornerOrn" transform="translate({s-4},4) scale(-1,1)"/>
  <use href="#cornerOrn" transform="translate(4,{s-4}) scale(1,-1)"/>
  <use href="#cornerOrn" transform="translate({s-4},{s-4}) scale(-1,-1)"/>'''
    render(body, s, s, "panel_frame")
    return {"name": "PanelFrame", "file": "panel_frame.png", "kind": "slice",
            "sliceCenter": [PANEL_SLICE, PANEL_SLICE, PANEL_SIZE - PANEL_SLICE, PANEL_SIZE - PANEL_SLICE],
            "usage": "Factory.Card background"}


# --------------------------------------------------------------------------
# Buttons (Factory.Button): plain gold-rimmed capsule, two fills. Factory.
# Button keeps its own Gloss/Shade code overlays on top -- same deal as Card.
# --------------------------------------------------------------------------
BTN_SIZE = 120
BTN_SLICE = 30


def button_primary():
    s = BTN_SIZE
    body = f'''
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="url(#molten)"/>
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="none" stroke="url(#goldBar)" stroke-width="4"/>
  <rect x="12" y="10" width="{s-24}" height="{(s-8)*0.4}" rx="16" fill="#FFFFFF" opacity="0.22"/>'''
    render(body, s, s, "button_primary")
    return {"name": "ButtonPrimary", "file": "button_primary.png", "kind": "slice",
            "sliceCenter": [BTN_SLICE, BTN_SLICE, BTN_SIZE - BTN_SLICE, BTN_SIZE - BTN_SLICE],
            "usage": "Factory.Button kind='primary'/'mint' background"}


def button_default():
    s = BTN_SIZE
    body = f'''
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="#241645"/>
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="none" stroke="url(#goldSoft)" stroke-width="3.2"/>
  <rect x="12" y="10" width="{s-24}" height="{(s-8)*0.4}" rx="16" fill="#FFFFFF" opacity="0.06"/>'''
    render(body, s, s, "button_default")
    return {"name": "ButtonDefault", "file": "button_default.png", "kind": "slice",
            "sliceCenter": [BTN_SLICE, BTN_SLICE, BTN_SIZE - BTN_SLICE, BTN_SIZE - BTN_SLICE],
            "usage": "Factory.Button default/danger background"}


def button_danger():
    s = BTN_SIZE
    body = f'''
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="url(#gemRuby)"/>
  <rect x="4" y="4" width="{s-8}" height="{s-8}" rx="28" fill="none" stroke="url(#goldBar)" stroke-width="4"/>
  <rect x="12" y="10" width="{s-24}" height="{(s-8)*0.4}" rx="16" fill="#FFFFFF" opacity="0.18"/>'''
    render(body, s, s, "button_danger")
    return {"name": "ButtonDanger", "file": "button_danger.png", "kind": "slice",
            "sliceCenter": [BTN_SLICE, BTN_SLICE, BTN_SIZE - BTN_SLICE, BTN_SIZE - BTN_SLICE],
            "usage": "Factory.Button kind='danger' background"}


# --------------------------------------------------------------------------
# Pill (Factory.Pill): capsule frame, no fixed width since it's 9-sliced.
# --------------------------------------------------------------------------
PILL_SIZE = 80
PILL_SLICE = 22


def pill_frame():
    s = PILL_SIZE
    body = f'''
  <rect x="3" y="3" width="{s-6}" height="{s-6}" rx="{(s-6)/2}" fill="#241645"/>
  <rect x="3" y="3" width="{s-6}" height="{s-6}" rx="{(s-6)/2}" fill="none" stroke="url(#goldBar)" stroke-width="3"/>
  <rect x="9" y="7" width="{s-18}" height="{(s-6)*0.42}" rx="{(s-6)*0.21}" fill="#FFFFFF" opacity="0.14"/>'''
    render(body, s, s, "pill_frame")
    return {"name": "PillFrame", "file": "pill_frame.png", "kind": "slice",
            "sliceCenter": [PILL_SLICE, PILL_SLICE, PILL_SIZE - PILL_SLICE, PILL_SIZE - PILL_SLICE],
            "usage": "Factory.Pill background"}


# --------------------------------------------------------------------------
# Nav icon medallions -- one square, Fit-scaled image each, no fallback
# needed at the call site since App.luau keeps its existing unicode-symbol
# label as a sibling that Factory.Icon's caller can choose to hide only once
# the icon image is actually present.
# --------------------------------------------------------------------------
ICON_SIZE = 160

NAV_ICONS = {
    "NavCreate": ("gemCyan", '<path d="M0 -34 l9 22 22 9 -22 9 -9 22 -9 -22 -22 -9 22 -9 z" fill="url(#gemGold)" stroke="#FFF3C4" stroke-width="2.4"/>'),
    "NavStudio": ("gemCyan", '<g fill="none" stroke="#EAFBFF" stroke-width="4.2" stroke-linejoin="round"><path d="M0 -30 L26 -15 L26 15 L0 30 L-26 15 L-26 -15 Z"/><path d="M-26 -15 L0 0 L26 -15 M0 0 L0 30"/></g>'),
    "NavDiscover": ("gemRose", '<g><circle r="26" fill="none" stroke="#FFD3EC" stroke-width="4.4"/><path d="M13 -13 L-4 4 L-13 13 L4 -4 Z" fill="#FFD3EC"/></g>'),
    "NavAvatarLab": ("gemMint", '<g fill="none" stroke="#DDFFF0" stroke-width="4.4" stroke-linecap="round"><circle cx="0" cy="-12" r="12"/><path d="M-24 30 C-24 6 24 6 24 30"/></g>'),
    "NavAvatarArt": ("gemAmethyst", '<g><rect x="-26" y="-20" width="52" height="40" rx="8" fill="none" stroke="#F1E4FF" stroke-width="4.2"/><path d="M-26 12 L-8 -6 L4 6 L12 -2 L26 12" fill="none" stroke="#F1E4FF" stroke-width="4.2" stroke-linejoin="round"/><circle cx="12" cy="-8" r="5.5" fill="#F1E4FF"/></g>'),
    "NavSettings": ("gemGold", '<g fill="none" stroke="#FFF3C4" stroke-width="4.4"><circle r="9"/><circle r="24" stroke-dasharray="10 8"/></g>'),
}


def nav_icon(key: str, gem: str, glyph: str):
    s = ICON_SIZE
    r = s / 2 - 6
    body = f'''
  <g transform="translate({s/2},{s/2})">
    <g filter="url(#goldGlow)"><circle r="{r}" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="4.4"/></g>
    <circle r="{r-11}" fill="none" stroke="#FFD98A" stroke-width="1.2" opacity="0.4"/>
    {glyph}
  </g>'''
    render(body, s, s, key.lower())
    return {"name": key, "file": f"{key.lower()}.png", "kind": "fit",
            "usage": f"sidebar nav icon for {key}"}


def logo_medallion():
    s = ICON_SIZE
    r = s / 2 - 6
    body = f'''
  <g transform="translate({s/2},{s/2})">
    <g filter="url(#goldGlow)"><circle r="{r}" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="4.4"/></g>
    <circle r="{r-13}" fill="none" stroke="#FFD98A" stroke-width="1.2" opacity="0.45"/>
    <g stroke="url(#goldSoft)" stroke-width="2.6" stroke-linecap="round">
      <path d="M{-r+18} 0 c-8 -11 -16 -13 -24 -11"/><path d="M{r-18} 0 c8 -11 16 -13 24 -11"/>
    </g>
    <path d="M0 -22 l6 15 15 6 -15 6 -6 15 -6 -15 -15 -6 15 -6 z" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="1.2"/>
    <circle r="4" fill="#FFF7E0"/>
  </g>'''
    render(body, s, s, "logo")
    return {"name": "Logo", "file": "logo.png", "kind": "fit", "usage": "topbar brand mark"}


def main():
    manifest = [
        panel_frame(),
        button_primary(),
        button_default(),
        button_danger(),
        pill_frame(),
        logo_medallion(),
    ]
    for key, (gem, glyph) in NAV_ICONS.items():
        manifest.append(nav_icon(key, gem, glyph))

    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\n{len(manifest)} assets exported to {OUT}/")
    print("Next: python3 upload_ui_assets.py  (needs an Open Cloud API key)")
    print("  or: upload the PNGs yourself in Studio, then fill in")
    print("      assets/asset_ids.json and run apply_asset_ids.py")


if __name__ == "__main__":
    main()
