#!/usr/bin/env python3
"""Export individual pieces of the gold-filigree concept art as transparent
PNGs Roblox can hold as Decals.

Two families:

1. Shared chrome -- Factory.Card/Button/Pill are each defined ONCE and reused
   on every one of the app's 8 screens, plus the topbar logo and the six
   sidebar nav icons. Retexturing those few shared pieces reskins the entire
   live app in one pass. Interactive pieces (real buttons, text boxes, scroll
   frames) stay real Roblox Instances; these images only ever sit *behind*
   them as a ScaleType.Slice or ScaleType.Fit background, via the
   Factory.ImageCard / Factory.ImageButton / Factory.ImagePill / Factory.Icon
   helpers -- each with a code-drawn fallback when its asset id is still 0,
   so nothing breaks before (or if) an upload happens.

2. Individual illustrated items -- every hand-drawn glyph, hero illustration
   and decorative ornament from the concept SVGs (item icons, the Direct
   Forge crystal, the ember mascot, gem studs, corner scrollwork, etc.),
   exported one-per-file exactly as drawn there. These are decorative art,
   not shared chrome, so nothing in App.luau references most of them yet --
   the 5 that match real Create-page content (the idea-chip prompts) get
   wired in; the rest ship exported and ready to use wherever a page needs
   them.

Panels/pills get real gold-filigree corner ornaments (they're big enough to
carry the detail); buttons use a plainer gold-rimmed capsule (they get as
small as 27px tall, where fine scrollwork would just blur into mush).

Run:  python3 export_ui_assets.py
Output: assets/*.png + assets/manifest.json
"""

import json
import pathlib
import subprocess

from build_screens import DEFS, SERIF, SANS, GEMS, ITEM_GLYPHS  # noqa: reuse the approved palette/fonts/glyphs

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


# --------------------------------------------------------------------------
# Individual item glyphs -- the exact illustrations build_screens.py uses for
# example item art (idea chips, gallery cards, Runway entrants, etc), each
# exported alone on its own transparent canvas. "kind": "fit" since these are
# fixed-aspect illustrations, not stretchable frames.
# --------------------------------------------------------------------------
GLYPH_SPECS = {
    # name: (canvas w, canvas h, kwargs passed to the glyph function)
    "wings": (360, 200, {}),
    "crown": (220, 150, {}),
    "katana": (300, 300, {}),
    "hat": (220, 160, {}),
    "butterfly": (300, 180, {}),
    "halo": (200, 110, {}),
    "horns": (180, 140, {}),
    "visor": (200, 110, {}),
    "backpack": (160, 200, {}),
    "avatar": (160, 180, {}),
    "picture": (180, 150, {}),
    "wand": (220, 220, {}),
}


def item_glyph(key: str):
    w, h, kwargs = GLYPH_SPECS[key]
    fn = ITEM_GLYPHS[key]
    body = fn(w / 2, h / 2, 1.0, **kwargs)
    name = f"Item{key.capitalize()}"
    file = f"item_{key}"
    render(body, w, h, file)
    return {"name": name, "file": f"{file}.png", "kind": "fit",
            "usage": f"standalone '{key}' item illustration (idea chips / gallery cards)"}


# --------------------------------------------------------------------------
# Direct Forge hero crystal (with its two sparkle accents), lifted verbatim
# from the Create-page concept art.
# --------------------------------------------------------------------------
def crystal_hero():
    w, h = 170, 180
    cx, cy = 84, 100
    body = f'''
  <g transform="translate({cx},{cy})" filter="url(#arcGlow)">
    <path d="M0 -62 L26 -22 L16 40 L-16 40 L-26 -22 Z" fill="url(#facetC)"/>
    <path d="M0 -62 L0 40 L-16 40 L-26 -22 Z" fill="url(#facetB)" opacity="0.92"/>
    <path d="M0 -62 L26 -22 L0 -8 Z" fill="url(#facetA)" opacity="0.95"/>
    <path d="M-26 -22 L0 -8 L0 40 L-16 40 Z" fill="#2E7FC4" opacity="0.55"/>
    <path d="M0 -62 L26 -22 L16 40 L-16 40 L-26 -22 Z" fill="none" stroke="#EAFBFF" stroke-width="2.2" stroke-linejoin="round"/>
    <path d="M0 -62 L0 40 M-26 -22 L26 -22 M-26 -22 L0 -8 L26 -22" fill="none" stroke="#EAFBFF" stroke-width="1.3" opacity="0.75"/>
    <path d="M6 -46 L14 -26" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" opacity="0.9"/>
  </g>
  <use href="#sparkle" transform="translate({cx+48},{cy-60}) scale(0.62)" fill="#FFF6D8" opacity="0.9"/>
  <use href="#sparkle" transform="translate({cx-44},{cy+54}) scale(0.4)" fill="#BFF0FF" opacity="0.8"/>'''
    render(body, w, h, "crystal_hero")
    return {"name": "CrystalHero", "file": "crystal_hero.png", "kind": "fit",
            "usage": "Direct Forge panel hero illustration"}


# --------------------------------------------------------------------------
# Ember mascot tip sprite.
# --------------------------------------------------------------------------
def ember_mascot():
    w = h = 140
    cx = cy = 70
    body = f'''
  <g transform="translate({cx},{cy})">
    <g filter="url(#softBlur)" opacity="0.65"><circle r="30" fill="#FF9436"/></g>
    <path d="M0 -34 C12 -18 25 -12 25 4 C25 21 13 33 0 33 C-13 33 -25 21 -25 4 C-25 -12 -12 -18 0 -34 Z" fill="url(#emberSprite)" stroke="#FFE7B0" stroke-width="2.4"/>
    <path d="M0 -18 C7 -8 13 -4 13 5 C13 15 7 22 0 22 C-7 22 -13 15 -13 5 C-13 -4 -7 -8 0 -18 Z" fill="#FFE9A8" opacity="0.55"/>
    <ellipse cx="-8.5" cy="0" rx="6" ry="7.2" fill="#2A1206"/>
    <ellipse cx="8.5" cy="0" rx="6" ry="7.2" fill="#2A1206"/>
    <circle cx="-6.5" cy="-2.4" r="2.2" fill="#FFFFFF"/>
    <circle cx="10.5" cy="-2.4" r="2.2" fill="#FFFFFF"/>
    <path d="M-7 12 Q0 19 7 12" fill="none" stroke="#2A1206" stroke-width="2.6" stroke-linecap="round"/>
  </g>'''
    render(body, w, h, "ember_mascot")
    return {"name": "EmberMascot", "file": "ember_mascot.png", "kind": "fit",
            "usage": "prompt panel tip sprite"}


# --------------------------------------------------------------------------
# Price cartouche -- shield/banner frame only (no baked-in price text, since
# that's real data a Roblox TextLabel should overlay).
# --------------------------------------------------------------------------
def price_cartouche():
    w, h = 220, 140
    cx, cy = 110, 70
    body = f'''
  <g transform="translate({cx},{cy})">
    <path d="M-88 -46 h176 v56 q0 22 -30 30 l-58 16 l-58 -16 q-30 -8 -30 -30 z" fill="#180F32" stroke="url(#goldBar)" stroke-width="2.8"/>
    <path d="M-79 -37 h158 v46 q0 16 -23 23 l-56 15 l-56 -15 q-23 -7 -23 -23 z" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.35"/>
  </g>'''
    render(body, w, h, "price_cartouche")
    return {"name": "PriceCartouche", "file": "price_cartouche.png", "kind": "fit",
            "usage": "decorative price-tag frame (overlay a real TextLabel for the amount)"}


# --------------------------------------------------------------------------
# Reusable decorative primitives -- exported straight from the shared <defs>
# via <use>, standalone.
# --------------------------------------------------------------------------
def corner_ornament():
    w = h = 200
    body = f'<use href="#cornerOrn" transform="translate(20,20) scale(2.4)"/>'
    render(body, w, h, "corner_ornament")
    return {"name": "CornerOrnament", "file": "corner_ornament.png", "kind": "fit",
            "usage": "standalone gold-filigree corner scrollwork"}


def flourish_divider():
    w, h = 300, 60
    body = f'<use href="#flourish" transform="translate(150,30)"/>'
    render(body, w, h, "flourish_divider")
    return {"name": "FlourishDivider", "file": "flourish_divider.png", "kind": "fit",
            "usage": "horizontal gold divider with centre gem"}


def rivet_stud():
    w = h = 40
    body = f'<use href="#rivet" transform="translate(20,20) scale(3)"/>'
    render(body, w, h, "rivet_stud")
    return {"name": "RivetStud", "file": "rivet_stud.png", "kind": "fit",
            "usage": "small gold rivet/stud accent"}


def sparkle_star():
    w = h = 60
    body = f'<use href="#sparkle" transform="translate(30,30) scale(1.5)" fill="#FFF6D8"/>'
    render(body, w, h, "sparkle_star")
    return {"name": "SparkleStar", "file": "sparkle_star.png", "kind": "fit",
            "usage": "4-point sparkle accent"}


# --------------------------------------------------------------------------
# Gem studs -- the small cut-gem diamond used throughout chips/pills/badges,
# one per colour, bigger and standalone.
# --------------------------------------------------------------------------
def gem_stud(gem: str):
    w = h = 60
    cx = cy = 30
    body = f'''
  <g transform="translate({cx},{cy})">
    <path d="M0 -22 L20 0 L0 22 L-20 0 Z" fill="url(#{gem})" stroke="#FFFFFF" stroke-width="2.4" stroke-linejoin="round" opacity="0.95"/>
    <path d="M0 -22 L20 0 L0 0 Z" fill="#FFFFFF" opacity="0.18"/>
    <path d="M-8 -10 L-2 -4" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" opacity="0.8"/>
  </g>'''
    name = gem[0].upper() + gem[1:]
    color = gem[3:].lower()  # "gemCyan" -> "cyan"
    file = f"gem_{color}"
    render(body, w, h, file)
    return {"name": name, "file": f"{file}.png", "kind": "fit",
            "usage": f"standalone {gem} cut-gem stud"}


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

    for key in GLYPH_SPECS:
        manifest.append(item_glyph(key))

    manifest.append(crystal_hero())
    manifest.append(ember_mascot())
    manifest.append(price_cartouche())
    manifest.append(corner_ornament())
    manifest.append(flourish_divider())
    manifest.append(rivet_stud())
    manifest.append(sparkle_star())

    for gem in GEMS:
        manifest.append(gem_stud(gem))

    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\n{len(manifest)} assets exported to {OUT}/")
    print("Next: python3 upload_ui_assets.py  (needs an Open Cloud API key)")
    print("  or: upload the PNGs yourself in Studio, then fill in")
    print("      assets/asset_ids.json and run apply_asset_ids.py")


if __name__ == "__main__":
    main()
