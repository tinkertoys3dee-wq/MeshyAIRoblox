#!/usr/bin/env python3
"""Draw the Forge UI concept screens as SVG.

The <defs> block (gradients, filters, corner ornaments, flourishes) is read
straight out of the hand-authored forge-create-screen.svg, so every screen
here stays on exactly the same design system as the one that was approved.
Common chrome -- top bar, sidebar, page title -- is drawn once and the per
page content is composed on top of it.

Run:  python3 build_screens.py
"""

import pathlib

HERE = pathlib.Path(__file__).parent
CREATE = HERE / "forge-create-screen.svg"

DEFS = CREATE.read_text().split("<defs>", 1)[1].split("</defs>", 1)[0]

SERIF = "'Cinzel','Liberation Serif','DejaVu Serif',Georgia,serif"
SANS = "'Liberation Sans','DejaVu Sans',Arial,sans-serif"

GEMS = ["gemCyan", "gemRose", "gemMint", "gemAmethyst", "gemGold", "gemRuby"]


# --------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------
def panel(x, y, w, h, rx=26, s=1.0, sheen=None):
    """Filigree panel: glass fill, gold rim, inner hairline, corner scrollwork."""
    sheen = sheen if sheen is not None else min(h * 0.34, 96)
    return f'''
  <g filter="url(#deepShadow)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="url(#panelGlass)"/></g>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="none" stroke="url(#goldBar)" stroke-width="3"/>
  <rect x="{x+9}" y="{y+9}" width="{w-18}" height="{h-18}" rx="{max(rx-7,6)}" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.24"/>
  <rect x="{x+9}" y="{y+9}" width="{w-18}" height="{sheen}" rx="{max(rx-7,6)}" fill="url(#panelSheen)"/>
  <use href="#cornerOrn" transform="translate({x},{y}) scale({s})"/>
  <use href="#cornerOrn" transform="translate({x+w},{y}) scale({-s},{s})"/>
  <use href="#cornerOrn" transform="translate({x},{y+h}) scale({s},{-s})"/>
  <use href="#cornerOrn" transform="translate({x+w},{y+h}) scale({-s},{-s})"/>'''


def banner(cx, y, w, text, color="#FFE3A6", fs=16, h=40):
    """Notched ribbon header, centred on cx."""
    x0, hh, k = cx - w / 2, h / 2, 16
    return f'''
  <g filter="url(#popShadow)">
    <path d="M{x0} {y} h{w} l{k} {hh} l{-k} {hh} h{-w} l{-k} {-hh} z" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="2.2"/>
  </g>
  <text x="{cx}" y="{y+hh+6}" font-family="{SERIF}" font-size="{fs}" font-weight="700" fill="{color}" letter-spacing="2.4" text-anchor="middle">{text}</text>'''


def molten_rect(x, y, w, h, label, fs=32, rx=None, glow=True, caps=False):
    """Big molten CTA with gold rim, sheen band and optional starburst caps."""
    rx = rx or min(h / 2 + 4, 30)
    g = ' filter="url(#moltenGlow)"' if glow else ' filter="url(#popShadow)"'
    out = f'''
  <g{g}><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="url(#molten)" stroke="url(#goldBar)" stroke-width="3.4"/></g>
  <rect x="{x+12}" y="{y+10}" width="{w-24}" height="{max(h*0.34,18)}" rx="{max(h*0.17,9)}" fill="url(#moltenSheen)" opacity="0.6"/>
  <rect x="{x+10}" y="{y+10}" width="{w-20}" height="{h-20}" rx="{max(rx-6,6)}" fill="none" stroke="#FFF0C0" stroke-width="1.2" opacity="0.5"/>'''
    if caps:
        for cx in (x + 0.13 * w, x + 0.87 * w):
            out += f'''
  <g transform="translate({cx},{y+h/2})">
    <circle r="{h*0.25}" fill="#3A1206" fill-opacity="0.35" stroke="url(#goldBar)" stroke-width="2.2"/>
    <path d="M0 -13 l3.6 8.9 8.9 3.6 -8.9 3.6 -3.6 8.9 -3.6 -8.9 -8.9 -3.6 8.9 -3.6 z" fill="#FFF0C0"/>
  </g>'''
    out += f'''
  <text x="{x+w/2}" y="{y+h/2+fs*0.35}" font-family="{SERIF}" font-size="{fs}" font-weight="700" fill="#3A1206" letter-spacing="1.2" text-anchor="middle">{label}</text>'''
    return out


def molten_hex(x, y, w, h, label, fs=17, fill="url(#molten)", text="#3A1206"):
    """Hex-ended action button."""
    k, hh = 16, h / 2
    return f'''
  <g filter="url(#popShadow)">
    <path d="M{x+k} {y} h{w-2*k} l{k} {hh} l{-k} {hh} h{-(w-2*k)} l{-k} {-hh} z" fill="{fill}" stroke="url(#goldBar)" stroke-width="2.4"/>
  </g>
  <path d="M{x+k+6} {y+7} h{w-2*k-12} l-8 {h*0.26} h{-(w-2*k-12)} z" fill="#FFFFFF" opacity="0.22"/>
  <text x="{x+w/2}" y="{y+hh+fs*0.35}" font-family="{SERIF}" font-size="{fs}" font-weight="700" fill="{text}" text-anchor="middle">{label}</text>'''


def ghost_hex(x, y, w, h, label, fs=17, stroke="url(#goldBar)", text="#EBDCFF"):
    k, hh = 16, h / 2
    return f'''
  <path d="M{x+k} {y} h{w-2*k} l{k} {hh} l{-k} {hh} h{-(w-2*k)} l{-k} {-hh} z" fill="#241645" stroke="{stroke}" stroke-width="2.2"/>
  <text x="{x+w/2}" y="{y+hh+fs*0.35}" font-family="{SERIF}" font-size="{fs}" fill="{text}" text-anchor="middle">{label}</text>'''


def gem_chip(x, y, w, label, gem, h=42, fs=15.5, active=False):
    """Cut-gem chip with an inlaid stone on the left."""
    body = w - 36
    hh = h / 2
    fill = "url(#molten)" if active else "#241645"
    tcol = "#3A1206" if active else "#EBDCFF"
    return f'''
  <g transform="translate({x},{y})">
    <path d="M18 0 h{body} l18 {hh} -18 {hh} h{-body} l-18 {-hh} z" fill="{fill}" stroke="url(#goldBar)" stroke-width="2.2"/>
    <path d="M24 5 h{body-12} l-9 {hh*0.5} h{-(body-12)} z" fill="#FFFFFF" opacity="{0.2 if active else 0.07}"/>
    <path d="M4 {hh} l7.5 -7.5 7.5 7.5 -7.5 7.5 z" fill="url(#{gem})" transform="translate(22,0)"/>
    <text x="{(w+28)/2}" y="{hh+fs*0.36}" font-family="{SANS}" font-size="{fs}" font-weight="700" fill="{tcol}" text-anchor="middle">{label}</text>
  </g>'''


def well(x, y, w, h, rx=20, glow=True, studs=True):
    """Inset input well."""
    g = ' filter="url(#arcGlow)"' if glow else ""
    out = f'''
  <g{g}><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="url(#inkWell)" stroke="#7FD8FF" stroke-width="2.4"/></g>
  <rect x="{x+8}" y="{y+8}" width="{w-16}" height="{h-16}" rx="{max(rx-5,5)}" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.28"/>'''
    if studs:
        out += f'''
  <g fill="#7FD8FF" opacity="0.75">
    <path d="M{x+24} {y+24} l5 -5 5 5 -5 5 z"/><path d="M{x+42} {y+24} l3.5 -3.5 3.5 3.5 -3.5 3.5 z" opacity="0.65"/>
    <path d="M{x+w-34} {y+24} l5 -5 5 5 -5 5 z"/><path d="M{x+w-52} {y+24} l3.5 -3.5 3.5 3.5 -3.5 3.5 z" opacity="0.65"/>
  </g>'''
    return out


def bar(x, y, w, h, pct, fill):
    inner = max((w - 6) * pct, 0)
    out = f'''
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2}" fill="#140C2C" stroke="url(#goldSoft)" stroke-width="1.4"/>'''
    if inner > 0:
        out += f'''
  <rect x="{x+3}" y="{y+3}" width="{inner}" height="{h-6}" rx="{(h-6)/2}" fill="url(#{fill})"/>'''
    return out


def pill(cx, cy, w, text, gem, fs=12.5, h=28):
    hh = h / 2
    return f'''
  <path d="M{cx-w/2} {cy-hh} h{w} l{hh} {hh} l{-hh} {hh} h{-w} l{-hh} {-hh} z" fill="#241645" stroke="url(#goldBar)" stroke-width="1.8"/>
  <path d="M{cx-w/2+12} {cy} l5 -5 5 5 -5 5 z" fill="url(#{gem})"/>
  <text x="{cx+8}" y="{cy+fs*0.36}" font-family="{SANS}" font-size="{fs}" font-weight="700" fill="#E9D9FF" text-anchor="middle">{text}</text>'''


def sparkle(x, y, s=0.6, fill="#FFF6D8", op=0.9):
    return f'  <use href="#sparkle" transform="translate({x},{y}) scale({s})" fill="{fill}" opacity="{op}"/>'


def advanced_link(cx, y, w, label, flourish=True, fs=16):
    out = f'''
  <rect x="{cx-w/2}" y="{y}" width="{w}" height="42" rx="21" fill="#2A1B4C" fill-opacity="0.55" stroke="url(#goldSoft)" stroke-width="1.6"/>
  <text x="{cx}" y="{y+27}" font-family="{SERIF}" font-size="{fs}" fill="#E9D9FF" text-anchor="middle">{label}  ✦</text>'''
    if flourish:
        out += f'''
  <use href="#flourish" transform="translate({cx-w/2-82},{y+21}) scale(0.42)"/>
  <use href="#flourish" transform="translate({cx+w/2+82},{y+21}) scale(0.42)"/>'''
    return out


# --------------------------------------------------------------------------
# item glyphs (drawn into a box centred on cx, cy)
# --------------------------------------------------------------------------
def glyph_wings(cx, cy, s=1.0, grad="facetC"):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})" filter="url(#arcGlow)">
    <g fill="url(#{grad})" stroke="#EAFBFF" stroke-width="2.4" stroke-linejoin="round">
      <path d="M-6 -6 C-34 -58 -92 -84 -152 -78 C-142 -54 -140 -34 -146 -14 C-130 -26 -110 -28 -98 -22 C-106 -6 -106 8 -102 20 C-86 8 -68 6 -54 10 C-58 24 -54 38 -46 48 C-32 30 -16 14 -2 8 Z"/>
      <path d="M6 -6 C34 -58 92 -84 152 -78 C142 -54 140 -34 146 -14 C130 -26 110 -28 98 -22 C106 -6 106 8 102 20 C86 8 68 6 54 10 C58 24 54 38 46 48 C32 30 16 14 2 8 Z"/>
    </g>
    <g stroke="#EAFBFF" stroke-width="1.2" opacity="0.7" fill="none">
      <path d="M-12 -2 L-120 -58 M-12 2 L-92 -18 M-12 6 L-62 12"/>
      <path d="M12 -2 L120 -58 M12 2 L92 -18 M12 6 L62 12"/>
    </g>
    <path d="M0 -18 l6 14 14 6 -14 6 -6 14 -6 -14 -14 -6 14 -6 z" fill="#FFF6D8"/>
  </g>'''


def glyph_crown(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <path d="M-70 26 L-78 -34 L-38 -4 L0 -46 L38 -4 L78 -34 L70 26 Z" fill="url(#gemGold)" stroke="#FFF3C4" stroke-width="2.6" stroke-linejoin="round"/>
    <path d="M-70 26 h140" stroke="#8A5A12" stroke-width="3"/>
    <path d="M-78 -34 L-38 -4 L0 -46 L38 -4 L78 -34" fill="none" stroke="#FFF7E0" stroke-width="1.4" opacity="0.7"/>
    <circle cx="0" cy="4" r="9" fill="url(#gemRuby)" stroke="#FFF3C4" stroke-width="2"/>
    <circle cx="-40" cy="8" r="6" fill="url(#gemCyan)" stroke="#FFF3C4" stroke-width="1.6"/>
    <circle cx="40" cy="8" r="6" fill="url(#gemMint)" stroke="#FFF3C4" stroke-width="1.6"/>
    <circle cx="-78" cy="-34" r="5" fill="#FFF6D8"/><circle cx="0" cy="-46" r="5.5" fill="#FFF6D8"/><circle cx="78" cy="-34" r="5" fill="#FFF6D8"/>
  </g>'''


def glyph_katana(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) rotate(-38) scale({s})" filter="url(#arcGlow)">
    <path d="M-6 -96 C6 -96 10 -88 10 -76 L10 26 L-10 26 L-10 -76 C-10 -88 -8 -96 -6 -96 Z" fill="url(#gemCyan)" stroke="#EAFBFF" stroke-width="2.2"/>
    <path d="M-2 -88 L-2 24" stroke="#FFFFFF" stroke-width="2" opacity="0.85"/>
    <rect x="-22" y="26" width="44" height="12" rx="5" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="1.6"/>
    <rect x="-8" y="38" width="16" height="52" rx="7" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="2"/>
    <path d="M-8 50 h16 M-8 62 h16 M-8 74 h16" stroke="url(#goldSoft)" stroke-width="1.6"/>
  </g>'''


def glyph_hat(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <ellipse cx="0" cy="34" rx="86" ry="20" fill="#3A2560" stroke="url(#goldBar)" stroke-width="2.6"/>
    <path d="M-46 34 L-42 -46 C-42 -56 42 -56 42 -46 L46 34 Z" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="2.6"/>
    <ellipse cx="0" cy="-46" rx="42" ry="11" fill="#3A2560" stroke="url(#goldBar)" stroke-width="2.2"/>
    <path d="M-45 14 L45 14 L44 -2 L-44 -2 Z" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="1.6"/>
    <circle cx="26" cy="6" r="7" fill="url(#gemRuby)" stroke="#FFF3C4" stroke-width="1.6"/>
    <g stroke="#C9A24A" stroke-width="1.4" opacity="0.8" fill="none">
      <path d="M-30 -34 c10 -6 22 -6 32 0"/><path d="M-24 -20 c8 -5 18 -5 26 0"/>
    </g>
  </g>'''


def glyph_butterfly(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <g fill="url(#gemAmethyst)" stroke="#F1E4FF" stroke-width="2.4" stroke-linejoin="round">
      <path d="M-6 0 C-40 -56 -92 -66 -110 -40 C-124 -18 -96 4 -66 6 C-96 16 -108 40 -92 56 C-72 74 -30 46 -6 12 Z"/>
      <path d="M6 0 C40 -56 92 -66 110 -40 C124 -18 96 4 66 6 C96 16 108 40 92 56 C72 74 30 46 6 12 Z"/>
    </g>
    <g fill="#FFF6D8" opacity="0.9">
      <circle cx="-72" cy="-28" r="6"/><circle cx="-52" cy="30" r="5"/>
      <circle cx="72" cy="-28" r="6"/><circle cx="52" cy="30" r="5"/>
    </g>
    <path d="M0 -18 C6 -6 6 22 0 34 C-6 22 -6 -6 0 -18 Z" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="1.6"/>
    <path d="M-2 -20 c-8 -12 -18 -16 -24 -14 M2 -20 c8 -12 18 -16 24 -14" fill="none" stroke="#F1E4FF" stroke-width="2" stroke-linecap="round"/>
  </g>'''


def glyph_halo(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})" filter="url(#goldGlow)">
    <ellipse cx="0" cy="0" rx="72" ry="24" fill="none" stroke="url(#goldBar)" stroke-width="13"/>
    <ellipse cx="0" cy="-4" rx="72" ry="24" fill="none" stroke="#FFF6D8" stroke-width="2.4" opacity="0.85"/>
  </g>'''


def glyph_horns(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <g fill="url(#gemRuby)" stroke="#FFE0E4" stroke-width="2.4" stroke-linejoin="round">
      <path d="M-10 40 C-46 26 -74 -10 -66 -50 C-44 -34 -30 -20 -14 4 Z"/>
      <path d="M10 40 C46 26 74 -10 66 -50 C44 -34 30 -20 14 4 Z"/>
    </g>
    <g fill="none" stroke="#FFE0E4" stroke-width="1.3" opacity="0.75">
      <path d="M-20 26 C-40 12 -54 -8 -54 -30"/><path d="M20 26 C40 12 54 -8 54 -30"/>
    </g>
  </g>'''


def glyph_visor(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})" filter="url(#arcGlow)">
    <path d="M-78 -14 C-78 -34 78 -34 78 -14 L78 8 C78 32 -78 32 -78 8 Z" fill="url(#gemCyan)" stroke="#EAFBFF" stroke-width="2.6"/>
    <path d="M-66 -12 C-66 -24 66 -24 66 -12" fill="none" stroke="#FFFFFF" stroke-width="3" opacity="0.8"/>
    <path d="M-78 -6 h156" stroke="#0E4E70" stroke-width="2" opacity="0.6"/>
  </g>'''


def glyph_backpack(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <rect x="-52" y="-46" width="104" height="94" rx="24" fill="url(#gemMint)" stroke="#DDFFF0" stroke-width="2.6"/>
    <path d="M-52 -6 h104" stroke="#0E5E42" stroke-width="3" opacity="0.7"/>
    <rect x="-24" y="4" width="48" height="30" rx="10" fill="#0E5E42" fill-opacity="0.45" stroke="#DDFFF0" stroke-width="2"/>
    <path d="M-30 -46 c0 -22 60 -22 60 0" fill="none" stroke="#DDFFF0" stroke-width="3"/>
    <circle cx="0" cy="-24" r="8" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="1.6"/>
  </g>'''


def glyph_avatar(cx, cy, s=1.0, outfit="gemAmethyst", edge="#F1E4FF"):
    """Blocky Roblox-style avatar bust."""
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <rect x="-30" y="-58" width="60" height="52" rx="10" fill="url(#gemGold)" stroke="#FFF3C4" stroke-width="2.4"/>
    <rect x="-17" y="-42" width="10" height="13" rx="3" fill="#2A1206"/>
    <rect x="7" y="-42" width="10" height="13" rx="3" fill="#2A1206"/>
    <path d="M-12 -20 q12 9 24 0" fill="none" stroke="#2A1206" stroke-width="3" stroke-linecap="round"/>
    <rect x="-26" y="0" width="52" height="46" rx="8" fill="url(#{outfit})" stroke="{edge}" stroke-width="2.4"/>
    <rect x="-46" y="2" width="16" height="40" rx="7" fill="url(#{outfit})" stroke="{edge}" stroke-width="2.2"/>
    <rect x="30" y="2" width="16" height="40" rx="7" fill="url(#{outfit})" stroke="{edge}" stroke-width="2.2"/>
  </g>'''


def glyph_picture(cx, cy, s=1.0, warm=True):
    """A framed portrait: sky, sun, ridge line and a small avatar silhouette."""
    sky = "gemGold" if warm else "gemCyan"
    ridge = "#5A2A18" if warm else "#14314F"
    sun = "#FFF6D8" if warm else "#BFF0FF"
    return f'''
  <g transform="translate({cx},{cy}) scale({s})">
    <rect x="-70" y="-52" width="140" height="104" rx="12" fill="#160E30" stroke="url(#goldBar)" stroke-width="3"/>
    <rect x="-60" y="-42" width="120" height="84" rx="8" fill="url(#{sky})" opacity="0.55"/>
    <circle cx="30" cy="-22" r="13" fill="{sun}" opacity="0.95"/>
    <circle cx="30" cy="-22" r="21" fill="{sun}" opacity="0.22"/>
    <path d="M-60 42 L-60 20 L-30 0 L-6 18 L16 4 L60 28 L60 42 Z" fill="{ridge}"/>
    <g fill="#150C2A">
      <rect x="-14" y="-6" width="21" height="19" rx="5"/>
      <rect x="-11" y="15" width="15" height="21" rx="4"/>
      <rect x="-19" y="16" width="6" height="14" rx="3"/>
      <rect x="5" y="16" width="6" height="14" rx="3"/>
    </g>
    <rect x="-60" y="-42" width="120" height="30" rx="8" fill="#FFFFFF" opacity="0.08"/>
  </g>'''


def glyph_wand(cx, cy, s=1.0):
    return f'''
  <g transform="translate({cx},{cy}) scale({s})" filter="url(#goldGlow)">
    <rect x="-7" y="-6" width="14" height="86" rx="6" transform="rotate(24)" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="2.4"/>
    <path d="M0 -66 l12 30 30 12 -30 12 -12 30 -12 -30 -30 -12 30 -12 z" fill="url(#gemGold)" stroke="#FFF3C4" stroke-width="2.4" stroke-linejoin="round"/>
    <circle cx="0" cy="-24" r="6" fill="#FFF6D8"/>
  </g>'''


ITEM_GLYPHS = {
    "wings": glyph_wings, "crown": glyph_crown, "katana": glyph_katana,
    "hat": glyph_hat, "butterfly": glyph_butterfly, "halo": glyph_halo,
    "horns": glyph_horns, "visor": glyph_visor, "backpack": glyph_backpack,
    "avatar": glyph_avatar, "picture": glyph_picture, "wand": glyph_wand,
}


# --------------------------------------------------------------------------
# shared chrome
# --------------------------------------------------------------------------
NAV = [
    ("Create", '<path d="M0 -10 l3.2 7.8 7.8 3.2 -7.8 3.2 -3.2 7.8 -3.2 -7.8 -7.8 -3.2 7.8 -3.2 z" fill="#8FE4FF"/>'),
    ("My Studio", '<g fill="none" stroke="#8FE4FF" stroke-width="1.9" stroke-linejoin="round"><path d="M0 -8 L7 -4 L7 4 L0 8 L-7 4 L-7 -4 Z"/><path d="M-7 -4 L0 0 L7 -4 M0 0 L0 8"/></g>'),
    ("Discover", '<g><circle r="7.5" fill="none" stroke="#FF9ED6" stroke-width="1.9"/><path d="M3.6 -3.6 L-1 1 L-3.6 3.6 L1 -1 Z" fill="#FF9ED6"/></g>'),
    ("Avatar Lab", '<g fill="none" stroke="#7FF0C0" stroke-width="1.9" stroke-linecap="round"><circle cx="0" cy="-3.5" r="3.6"/><path d="M-6.5 8 C-6.5 1.5 6.5 1.5 6.5 8"/></g>'),
    ("Avatar Art", '<g><rect x="-8" y="-6.5" width="16" height="13" rx="2.5" fill="none" stroke="#C6A6FF" stroke-width="1.9"/><path d="M-8 3 L-2.5 -2.5 L1.5 1.5 L4 -1 L8 3" fill="none" stroke="#C6A6FF" stroke-width="1.9" stroke-linejoin="round"/></g>'),
    ("Settings", '<g fill="none" stroke="#D8CBEF" stroke-width="1.9"><circle r="3.2"/><circle r="7.4" stroke-dasharray="3.4 2.8"/></g>'),
]

BADGES = [("LV 7", 112, "gemGold", "#FFE3A6"), ("5 DAY STREAK", 128, "gemRuby", "#FFC9C9"),
          ("2 SLOTS", 100, "gemCyan", "#BFEEFF"), ("PLUS", 72, "gemRose", "#FFD2EE")]


def chrome(active, title, subtitle, flourish_x=470):
    out = f'''
  <rect width="1920" height="1080" fill="url(#sky)"/>
  <ellipse cx="960" cy="1130" rx="1080" ry="430" fill="url(#emberGlow)"/>
  <ellipse cx="330" cy="150" rx="620" ry="420" fill="url(#arcaneGlow)"/>
  <g opacity="0.55">
    <path d="M700 -40 L860 -40 L560 620 L470 620 Z" fill="url(#rayFade)"/>
    <path d="M1010 -40 L1090 -40 L960 520 L890 520 Z" fill="url(#rayFade)"/>
    <path d="M1320 -40 L1440 -40 L1260 560 L1180 560 Z" fill="url(#rayFade)"/>
  </g>
  <g opacity="0.15" fill="none" stroke="#8FE4FF">
    <circle cx="900" cy="600" r="452" stroke-width="1.6"/>
    <circle cx="900" cy="600" r="430" stroke-width="0.9" stroke-dasharray="3 13"/>
    <circle cx="900" cy="600" r="372" stroke-width="1.1" stroke-dasharray="34 20"/>
    <circle cx="900" cy="600" r="300" stroke-width="0.9"/>
  </g>
  <g filter="url(#softBlur)">
    <circle cx="640" cy="250" r="5" fill="#FFC46A" opacity="0.7"/>
    <circle cx="1180" cy="330" r="4" fill="#FF9A5E" opacity="0.55"/>
    <circle cx="500" cy="760" r="6" fill="#FFB255" opacity="0.45"/>
    <circle cx="1620" cy="230" r="4.5" fill="#FFD08A" opacity="0.5"/>
    <circle cx="820" cy="1010" r="7" fill="#FF8F3C" opacity="0.5"/>
  </g>
{sparkle(1268,142,0.72,op=0.8)}
{sparkle(1786,206,0.95,op=0.65)}
{sparkle(276,700,0.66,op=0.55)}

  <path d="M0 0 H1920 V72 C1480 104, 440 104, 0 72 Z" fill="#150C2E" fill-opacity="0.82"/>
  <path d="M0 72 C440 104, 1480 104, 1920 72" fill="none" stroke="url(#goldBar)" stroke-width="3"/>
  <path d="M0 79 C440 111, 1480 111, 1920 79" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.35"/>

  <g transform="translate(66,46)">
    <g filter="url(#goldGlow)"><circle r="31" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="3.4"/></g>
    <circle r="24" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.45"/>
    <g stroke="url(#goldSoft)" stroke-width="2" stroke-linecap="round">
      <path d="M-38 0 c-6 -8 -12 -10 -18 -8"/><path d="M38 0 c6 -8 12 -10 18 -8"/>
    </g>
    <path d="M0 -17 l4.6 11.4 11.4 4.6 -11.4 4.6 -4.6 11.4 -4.6 -11.4 -11.4 -4.6 11.4 -4.6 z" fill="url(#gemGold)" stroke="#8A5A12" stroke-width="0.9"/>
    <circle r="3" fill="#FFF7E0"/>
  </g>
  <text x="112" y="45" font-family="{SERIF}" font-size="33" font-weight="700" fill="url(#goldEdge)" letter-spacing="5">FORGE</text>
  <text x="114" y="66" font-family="{SANS}" font-size="10.5" font-weight="700" fill="#E6C98A" letter-spacing="3.4" opacity="0.85">MAKE ANYTHING · WEAR IT</text>'''

    bx = 1888
    for label, w, gem, col in reversed(BADGES):
        bx -= w + 32
        out += f'''
  <g transform="translate({bx+w/2+16},44)">
    <path d="M{-w/2-16} -19 h{w} l16 19 -16 19 h{-w} l-16 -19 z" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="2.2"/>
    <path d="M{-w/2-4} -7 l7 -7 7 7 -7 7 z" fill="url(#{gem})"/>
    <text x="{14}" y="6" font-family="{SANS}" font-size="15" font-weight="800" fill="{col}" text-anchor="middle">{label}</text>
  </g>'''
        bx -= 12

    out += panel(16, 112, 232, 952, rx=28, sheen=300)
    out += f'''
  <g font-family="{SERIF}">'''
    for i, (name, icon) in enumerate(NAV):
        y = 150 + i * 68
        if name == active:
            out += f'''
    <g filter="url(#goldGlow)"><rect x="32" y="{y}" width="204" height="58" rx="18" fill="url(#molten)" stroke="url(#goldBar)" stroke-width="2.8"/></g>
    <rect x="38" y="{y+6}" width="192" height="20" rx="10" fill="url(#moltenSheen)" opacity="0.5"/>
    <circle cx="62" cy="{y+29}" r="17" fill="#2A1240" stroke="url(#goldBar)" stroke-width="2.2"/>
    <g transform="translate(62,{y+29})">{icon}</g>
    <text x="90" y="{y+36}" font-size="20" font-weight="700" fill="#3A1206">{name}</text>'''
        else:
            out += f'''
    <rect x="32" y="{y+2}" width="204" height="54" rx="17" fill="#3A2560" fill-opacity="0.42" stroke="#C9A24A" stroke-width="1.4" stroke-opacity="0.55"/>
    <circle cx="62" cy="{y+29}" r="16" fill="#1E1238" stroke="url(#goldSoft)" stroke-width="1.8"/>
    <g transform="translate(62,{y+29})">{icon}</g>
    <text x="90" y="{y+36}" font-size="18" fill="#EBDCFF">{name}</text>'''
    out += "\n  </g>"

    out += f'''
  <use href="#flourish" transform="translate(134,600) scale(0.62)"/>
  <g transform="translate(134,714)">
    <circle r="60" fill="#160E30" fill-opacity="0.7" stroke="url(#goldSoft)" stroke-width="1.4"/>
    <circle r="52" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="3"/>
    <circle r="44" fill="none" stroke="#3A2560" stroke-width="7"/>
    <circle r="44" fill="none" stroke="url(#fillGold)" stroke-width="7" stroke-linecap="round" stroke-dasharray="198 78" transform="rotate(-90)"/>
    <circle r="34" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.35"/>
    <text x="0" y="6" font-family="{SERIF}" font-size="34" font-weight="700" fill="url(#goldEdge)" text-anchor="middle">7</text>
    <text x="0" y="26" font-family="{SANS}" font-size="9.5" font-weight="700" fill="#C6AE7A" letter-spacing="2" text-anchor="middle">LEVEL</text>
    <path d="M0 -63 l6 -6 6 6 -6 6 z" transform="translate(-6,0)" fill="url(#gemGold)"/>
    <path d="M0 57 l6 -6 6 6 -6 6 z" transform="translate(-6,0)" fill="url(#gemGold)"/>
    <path d="M-66 0 l6 -6 6 6 -6 6 z" fill="url(#gemGold)" opacity="0.8"/>
    <path d="M54 0 l6 -6 6 6 -6 6 z" fill="url(#gemGold)" opacity="0.8"/>
  </g>
  <text x="134" y="806" font-family="{SERIF}" font-size="12.5" font-weight="700" fill="#E6C98A" letter-spacing="2.2" text-anchor="middle">CREATOR RANK</text>
  <text x="134" y="828" font-family="{SANS}" font-size="12" fill="#9C8CC0" text-anchor="middle">1,180 / 1,600 XP</text>
  <use href="#flourish" transform="translate(134,856) scale(0.5)"/>

  <rect x="32" y="900" width="204" height="140" rx="20" fill="#160E30" fill-opacity="0.75" stroke="url(#goldSoft)" stroke-width="1.8"/>
  <text x="134" y="932" font-family="{SERIF}" font-size="13" font-weight="700" fill="#E6C98A" letter-spacing="2.6" text-anchor="middle">MODE</text>
  <g filter="url(#popShadow)"><rect x="46" y="944" width="176" height="46" rx="15" fill="url(#gemMint)" stroke="url(#goldBar)" stroke-width="2.2"/></g>
  <rect x="52" y="949" width="164" height="15" rx="7.5" fill="#FFFFFF" opacity="0.3"/>
  <text x="134" y="974" font-family="{SERIF}" font-size="17" font-weight="700" fill="#08331F" text-anchor="middle">Simple</text>
  <rect x="46" y="998" width="176" height="30" rx="12" fill="#2A1B4C" stroke="#8E76B8" stroke-width="1.3" stroke-opacity="0.6"/>
  <text x="134" y="1019" font-family="{SERIF}" font-size="15" fill="#A594C4" text-anchor="middle">Advanced</text>

  <text x="296" y="172" font-family="{SERIF}" font-size="52" font-weight="700" fill="url(#goldEdge)" filter="url(#popShadow)">{title}</text>
  <use href="#flourish" transform="translate({flourish_x},196) scale(0.8)"/>
  <text x="296" y="228" font-family="{SANS}" font-size="17" fill="#D9C7F5">{subtitle}</text>'''
    return out


def document(title, body, extra_defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">\n'
            f'  <title>{title}</title>\n  <defs>{DEFS}{extra_defs}</defs>\n{body}\n</svg>\n')


MODAL_DEFS = '''
    <linearGradient id="rainbow" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#FF5B97"/>
      <stop offset="34%" stop-color="#FFC452"/>
      <stop offset="67%" stop-color="#37DCFF"/>
      <stop offset="100%" stop-color="#4CEFAF"/>
    </linearGradient>
    <radialGradient id="spotlight" cx="50%" cy="0%" r="80%">
      <stop offset="0%" stop-color="#FFE6B0" stop-opacity="0.30"/>
      <stop offset="100%" stop-color="#FFE6B0" stop-opacity="0"/>
    </radialGradient>
'''


def modal_backdrop(active="Create"):
    """The app behind, dimmed, so the panel reads as an overlay."""
    return chrome(active, "", "") + '''
  <rect width="1920" height="1080" fill="#0A0518" opacity="0.74"/>
  <ellipse cx="960" cy="540" rx="900" ry="620" fill="#7FD8FF" opacity="0.05"/>'''


def modal_panel(x, y, w, h, accent=True):
    out = panel(x, y, w, h, rx=30, s=1.0, sheen=110)
    if accent:
        out += f'''
  <rect x="{x+26}" y="{y+6}" width="{w-52}" height="7" rx="3.5" fill="url(#rainbow)" opacity="0.95"/>'''
    return out


def close_button(cx, cy):
    return f'''
  <g transform="translate({cx},{cy})">
    <circle r="24" fill="#241645" stroke="url(#goldBar)" stroke-width="2.6"/>
    <path d="M-8 -8 L8 8 M8 -8 L-8 8" stroke="#FFD98A" stroke-width="3.2" stroke-linecap="round"/>
  </g>'''


def portrait(x, y, s, tint="gemAmethyst", edge="#F1E4FF"):
    """Small framed avatar bust used in runway entries."""
    return f'''
  <rect x="{x}" y="{y}" width="{s}" height="{s}" rx="16" fill="#100A22" stroke="url(#goldBar)" stroke-width="2.2"/>
  <ellipse cx="{x+s/2}" cy="{y+s*0.86}" rx="{s*0.34}" ry="{s*0.08}" fill="#7FD8FF" opacity="0.12"/>''' + \
        glyph_avatar(x + s / 2, y + s * 0.52, s / 150, tint, edge)


# --------------------------------------------------------------------------
# 1. MY STUDIO
# --------------------------------------------------------------------------
def my_studio():
    b = chrome("My Studio", "My Studio",
               "Tap an item below, then equip it or publish it as a real Roblox wearable.", 400)

    # outfits strip
    b += panel(296, 256, 1584, 104, rx=24, s=0.8, sheen=44)
    b += f'''
  <text x="330" y="300" font-family="{SERIF}" font-size="15" font-weight="700" fill="#E6C98A" letter-spacing="2.4">OUTFITS</text>
  <text x="330" y="326" font-family="{SANS}" font-size="12.5" fill="#9C8CC0">Save your look</text>'''
    b += well(486, 282, 380, 52, rx=18, glow=False, studs=False)
    b += f'''
  <text x="512" y="315" font-family="{SANS}" font-size="16" fill="#8E7FB4">Name this look…</text>'''
    b += molten_hex(886, 282, 214, 52, "Save look", 17)
    for i, (nm, gem) in enumerate([("Neon Knight", "gemCyan"), ("Sky Pirate", "gemRose"), ("Ember Mage", "gemGold")]):
        b += gem_chip(1128 + i * 218, 287, 200, nm, gem, h=42, fs=15)

    # collection
    b += panel(296, 384, 560, 660, rx=26, s=0.9, sheen=70)
    b += banner(576, 372, 300, "COLLECTION · 6")
    items = [("Crystal Dragon Wings", "ORIGINAL", "wings", True),
             ("Sunspire Crown", "ORIGINAL", "crown", False),
             ("Neon Katana", "PERSONAL COPY", "katana", False),
             ("Aether Top Hat", "ORIGINAL", "hat", False),
             ("Moth Queen Wings", "ORIGINAL", "butterfly", False)]
    for i, (nm, lic, glyph, sel) in enumerate(items):
        y = 434 + i * 118
        if sel:
            b += f'''
  <g filter="url(#goldGlow)"><rect x="324" y="{y}" width="504" height="104" rx="18" fill="#3A1F52" stroke="url(#goldBar)" stroke-width="2.8"/></g>'''
        else:
            b += f'''
  <rect x="324" y="{y}" width="504" height="104" rx="18" fill="#241645" fill-opacity="0.72" stroke="#C9A24A" stroke-width="1.4" stroke-opacity="0.5"/>'''
        b += f'''
  <rect x="340" y="{y+12}" width="80" height="80" rx="14" fill="#160E30" stroke="url(#goldBar)" stroke-width="2"/>'''
        b += ITEM_GLYPHS[glyph](380, y + 52, 0.32)
        b += f'''
  <text x="438" y="{y+44}" font-family="{SERIF}" font-size="20" font-weight="700" fill="#FFE9BC">{nm}</text>
  <text x="438" y="{y+70}" font-family="{SANS}" font-size="12.5" font-weight="700" fill="{'#FFC85A' if lic!='ORIGINAL' else '#9C8CC0'}" letter-spacing="1.4">{lic}</text>
  <path d="M800 {y+44} l12 8 -12 8" fill="none" stroke="url(#goldSoft)" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'''
        if sel:
            b += f'''
  <path d="M814 {y+18} l5 -5 5 5 -5 5 z" fill="url(#gemGold)"/>'''

    # inspector
    b += panel(888, 384, 992, 660, rx=26, s=0.9, sheen=80)
    b += f'''
  <text x="924" y="440" font-family="{SERIF}" font-size="34" font-weight="700" fill="#FFE9BC">Crystal Dragon Wings</text>'''
    b += pill(996, 466, 116, "ORIGINAL", "gemMint")
    b += pill(1156, 466, 176, "FANTASY · BALANCED", "gemAmethyst")

    # viewport
    b += f'''
  <g filter="url(#deepShadow)"><rect x="924" y="496" width="920" height="300" rx="22" fill="#100A22" stroke="url(#goldBar)" stroke-width="3"/></g>
  <rect x="932" y="504" width="904" height="284" rx="16" fill="none" stroke="#7FD8FF" stroke-width="1" opacity="0.3"/>
  <ellipse cx="1384" cy="700" rx="250" ry="42" fill="#7FD8FF" opacity="0.1"/>
  <ellipse cx="1384" cy="700" rx="150" ry="24" fill="#7FD8FF" opacity="0.12"/>'''
    b += glyph_wings(1384, 636, 1.28)
    b += sparkle(1180, 566, 0.55, op=0.8) + sparkle(1596, 596, 0.42, "#BFF0FF", 0.8)
    b += pill(1024, 536, 152, "DRAG TO ORBIT", "gemCyan", fs=11.5, h=26)
    b += f'''
  <g transform="translate(1794,538)">
    <circle r="20" fill="#241645" stroke="url(#goldBar)" stroke-width="2.2"/>
    <path d="M-8 -2 a8 8 0 1 1 3 6" fill="none" stroke="#FFD98A" stroke-width="2.4" stroke-linecap="round"/>
    <path d="M-11 -8 l3 7 7 -3 z" fill="#FFD98A"/>
  </g>'''

    # readiness
    b += f'''
  <rect x="924" y="816" width="920" height="56" rx="18" fill="#160E30" fill-opacity="0.8" stroke="url(#goldSoft)" stroke-width="1.8"/>
  <circle cx="954" cy="844" r="11" fill="url(#gemMint)" stroke="#DDFFF0" stroke-width="2"/>
  <path d="M949 844 l4 4 8 -9" fill="none" stroke="#08331F" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
  <text x="978" y="838" font-family="{SERIF}" font-size="15" font-weight="700" fill="#9DF5CE" letter-spacing="1.6">READY TO WEAR</text>
  <text x="978" y="858" font-family="{SANS}" font-size="12.5" fill="#9C8CC0">Fits Roblox publishing limits · texture approved</text>'''

    b += molten_hex(924, 890, 450, 66, "Equip in game", 22)
    b += ghost_hex(1394, 890, 450, 66, "Publish wearable", 22)
    b += f'''
  <text x="1384" y="988" font-family="{SANS}" font-size="14" fill="#9C8CC0" text-anchor="middle">Equip wears it now · Publish sends it to Roblox as a real wearable.</text>'''
    b += advanced_link(1384, 1000, 560, "Switch to Advanced Mode for fit, pricing &amp; sharing")
    return document("Forge — My Studio", b)


# --------------------------------------------------------------------------
# 2. DISCOVER
# --------------------------------------------------------------------------
def discover():
    b = chrome("Discover", "Discover",
               "Try on things other players made. Tap Try on, then like the ones you love.", 396)

    # first look banner
    b += panel(296, 252, 1584, 150, rx=26, s=0.85, sheen=60)
    b += f'''
  <rect x="330" y="272" width="110" height="110" rx="18" fill="#160E30" stroke="url(#goldBar)" stroke-width="2.4"/>'''
    b += glyph_halo(385, 327, 0.5)
    b += pill(556, 296, 148, "STEP 2 OF 4", "gemCyan", fs=11.5, h=26)
    b += f'''
  <text x="470" y="336" font-family="{SERIF}" font-size="30" font-weight="700" fill="#FFE9BC">Your free First Look</text>
  <text x="470" y="368" font-family="{SANS}" font-size="15.5" fill="#CDBBEE">One tap puts a featured creator accessory on your avatar. No Robux, no catalog permission.</text>'''
    b += molten_rect(1554, 292, 292, 70, "Try this look · FREE", 21, rx=24, glow=False)

    # search row
    b += well(296, 430, 1244, 56, rx=20, studs=False)
    b += f'''
  <text x="330" y="466" font-family="{SANS}" font-size="17" fill="#8E7FB4">Search public designs…</text>
  <g transform="translate(1490,458)" opacity="0.85">
    <circle r="9" fill="none" stroke="#7FD8FF" stroke-width="2.4"/><path d="M7 7 l8 8" stroke="#7FD8FF" stroke-width="2.8" stroke-linecap="round"/>
  </g>'''
    b += molten_hex(1568, 430, 312, 56, "Search", 19)
    b += advanced_link(1088, 508, 620, "Switch to Advanced Mode for filters, sorting &amp; buying")

    # grid
    cards = [("Crystal Dragon Wings", "zaraBuilds", "wings", "gemCyan", "412", "96"),
             ("Sunspire Crown", "kit_9", "crown", "gemGold", "268", "71"),
             ("Neon Katana", "mossy", "katana", "gemMint", "934", "212"),
             ("Moth Queen Wings", "pix", "butterfly", "gemAmethyst", "155", "40")]
    for i, (nm, who, glyph, gem, likes, favs) in enumerate(cards):
        x = 296 + i * 402
        b += panel(x, 576, 378, 468, rx=24, s=0.8, sheen=70)
        b += f'''
  <rect x="{x+18}" y="{y_img_top(594)}" width="342" height="222" rx="18" fill="#100A22" stroke="url(#goldBar)" stroke-width="2.2"/>
  <ellipse cx="{x+189}" cy="{594+178}" rx="112" ry="20" fill="#7FD8FF" opacity="0.1"/>'''
        b += ITEM_GLYPHS[glyph](x + 189, 594 + 104, 0.72 if glyph in ("wings", "butterfly") else 0.86)
        b += f'''
  <text x="{x+189}" y="{860}" font-family="{SERIF}" font-size="20" font-weight="700" fill="#FFE9BC" text-anchor="middle">{nm}</text>
  <text x="{x+189}" y="{886}" font-family="{SANS}" font-size="13.5" fill="#9C8CC0" text-anchor="middle">by @{who}</text>'''
        b += molten_hex(x + 18, 906, 342, 56, "Try on", 19)
        b += f'''
  <path d="M{x+34} 984 h150 l14 21 -14 21 h-150 l-14 -21 z" fill="#241645" stroke="url(#goldBar)" stroke-width="2"/>
  <path d="M{x+56} 1000 c-6 -7 -16 -2 -16 5 c0 8 12 14 16 18 c4 -4 16 -10 16 -18 c0 -7 -10 -12 -16 -5 z" fill="url(#gemRuby)"/>
  <text x="{x+126}" y="{1011}" font-family="{SANS}" font-size="14.5" font-weight="700" fill="#EBDCFF" text-anchor="middle">{likes}</text>
  <path d="M{x+208} 984 h130 l14 21 -14 21 h-130 l-14 -21 z" fill="#241645" stroke="url(#goldBar)" stroke-width="2"/>
  <path d="M{x+228} 995 l4.6 9.4 10.4 1.6 -7.5 7.3 1.8 10.3 -9.3 -4.9 -9.3 4.9 1.8 -10.3 -7.5 -7.3 10.4 -1.6 z" fill="url(#gemGold)"/>
  <text x="{x+292}" y="{1011}" font-family="{SANS}" font-size="14.5" font-weight="700" fill="#EBDCFF" text-anchor="middle">{favs}</text>'''
    return document("Forge — Discover", b)


def y_img_top(v):
    return v


# --------------------------------------------------------------------------
# 3. AVATAR LAB
# --------------------------------------------------------------------------
def avatar_lab():
    b = chrome("Avatar Lab", "Avatar Lab",
               "Try on free Roblox items. Tap a category below, then Try on.", 400)

    b += panel(296, 252, 1584, 196, rx=26, s=0.85, sheen=76)
    b += well(330, 280, 900, 56, rx=20, studs=False)
    b += f'''
  <text x="364" y="316" font-family="{SANS}" font-size="17" fill="#8E7FB4">Search the Roblox avatar marketplace…</text>
  <g transform="translate(1180,308)" opacity="0.85">
    <circle r="9" fill="none" stroke="#7FD8FF" stroke-width="2.4"/><path d="M7 7 l8 8" stroke="#7FD8FF" stroke-width="2.8" stroke-linecap="round"/>
  </g>'''
    b += molten_hex(1252, 280, 190, 56, "Search", 18)
    b += ghost_hex(1458, 280, 190, 56, "Save avatar", 17)
    b += ghost_hex(1664, 280, 190, 56, "Reset look", 17)

    cats = [("Hats", "gemGold", True), ("Hair", "gemRose", False), ("Face", "gemCyan", False),
            ("Back", "gemMint", False), ("Front", "gemAmethyst", False), ("Neck", "gemRuby", False)]
    x = 330
    for nm, gem, act in cats:
        b += gem_chip(x, 358, 166, nm, gem, h=46, fs=16, active=act)
        x += 186
    b += advanced_link(1660, 358, 380, "Advanced Mode", flourish=False, fs=15)

    # catalog grid : 2 rows x 5
    grid = [("Golden Halo", "halo", 1.0), ("Demon Horns", "horns", 0.72),
            ("Cyber Visor", "visor", 0.78), ("Star Backpack", "backpack", 0.72),
            ("Sunspire Crown", "crown", 0.72), ("Moth Wings", "butterfly", 0.56),
            ("Aether Hat", "hat", 0.66), ("Neon Katana", "katana", 0.6),
            ("Frost Wings", "wings", 0.5), ("Star Wand", "wand", 0.62)]
    for i, (nm, glyph, gs) in enumerate(grid):
        col, row = i % 5, i // 5
        x = 296 + col * 320
        y = 480 + row * 292
        b += panel(x, y, 300, 268, rx=22, s=0.7, sheen=48)
        b += f'''
  <rect x="{x+16}" y="{y+16}" width="268" height="140" rx="14" fill="#100A22" stroke="url(#goldBar)" stroke-width="2"/>'''
        b += ITEM_GLYPHS[glyph](x + 150, y + 86, gs * 0.72)
        b += f'''
  <text x="{x+150}" y="{y+186}" font-family="{SERIF}" font-size="17" font-weight="700" fill="#FFE9BC" text-anchor="middle">{nm}</text>'''
        b += molten_hex(x + 16, y + 200, 268, 50, "Try on", 17)
    return document("Forge — Avatar Lab", b)


# --------------------------------------------------------------------------
# 4. AVATAR GRAPHICS
# --------------------------------------------------------------------------
def avatar_graphics():
    b = chrome("Avatar Art", "Avatar Graphics",
               "Turn a prompt or your avatar into a picture you can keep.", 440)

    # tabs
    b += gem_chip(296, 252, 208, "Create", "gemGold", h=48, fs=17, active=True)
    b += gem_chip(524, 252, 208, "Discover", "gemAmethyst", h=48, fs=17)

    # composer
    b += panel(296, 324, 1004, 606, rx=26, s=0.9, sheen=84)
    b += f'''
  <text x="332" y="372" font-family="{SERIF}" font-size="14" font-weight="700" fill="#E6C98A" letter-spacing="2.4">SOURCE</text>'''
    b += molten_hex(332, 386, 452, 58, "From My Avatar", 19)
    b += ghost_hex(812, 386, 452, 58, "Text Prompt", 19)

    b += f'''
  <text x="332" y="490" font-family="{SERIF}" font-size="15" font-weight="700" fill="#9DF5CE" letter-spacing="2">1 · CHOOSE YOUR AVATAR VIEW</text>'''
    for i, (nm, act) in enumerate([("Headshot", False), ("Bust", True), ("Full body", False)]):
        b += gem_chip(332 + i * 210, 504, 194, nm, "gemMint", h=44, fs=15.5, active=act)

    b += f'''
  <rect x="332" y="570" width="120" height="120" rx="20" fill="#100A22" stroke="url(#goldBar)" stroke-width="2.4"/>'''
    b += glyph_avatar(392, 634, 0.78)
    b += f'''
  <text x="474" y="612" font-family="{SANS}" font-size="15.5" fill="#CDBBEE">Fetched automatically from your current</text>
  <text x="474" y="638" font-family="{SANS}" font-size="15.5" fill="#CDBBEE">Roblox avatar — nothing to upload.</text>
  <text x="474" y="668" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">Style and quality use their defaults in Simple Mode.</text>'''

    b += f'''
  <text x="332" y="724" font-family="{SERIF}" font-size="15" font-weight="700" fill="#FF9ED6" letter-spacing="2">2 · DESCRIBE A SCENE OR THEME  (OPTIONAL)</text>'''
    b += well(332, 738, 932, 96, rx=20)
    b += f'''
  <text x="366" y="792" font-family="{SANS}" font-size="21" fill="#F4ECFF">standing on a cliff at sunset, cinematic</text>
  <rect x="760" y="772" width="2.6" height="26" rx="1.3" fill="#8FE4FF"/>
  <text x="1238" y="820" font-family="{SANS}" font-size="13" font-weight="700" fill="#8E7FB4" text-anchor="end">38 / 500</text>'''
    b += advanced_link(566, 852, 452, "Advanced Mode: style &amp; quality", flourish=False)
    b += molten_rect(1010, 848, 254, 62, "Create · R$ 29", 22, rx=22, glow=False)

    # right rail : in progress
    b += panel(1332, 324, 548, 208, rx=24, s=0.8, sheen=60)
    b += banner(1606, 312, 300, "IN PROGRESS", "#BFEEFF")
    b += f'''
  <circle cx="1388" cy="404" r="20" fill="#241645" stroke="url(#gemCyan)" stroke-width="2.4"/>
  <path d="M1388 394 l3 7 7 3 -7 3 -3 7 -3 -7 -7 -3 7 -3 z" fill="#8FE4FF"/>
  <text x="1424" y="398" font-family="{SANS}" font-size="15" font-weight="700" fill="#EBDCFF">“knight in a storm”</text>
  <text x="1848" y="398" font-family="{SANS}" font-size="13.5" font-weight="800" fill="#8FE4FF" text-anchor="end">64%</text>'''
    b += bar(1424, 410, 424, 12, 0.64, "fillCyan")
    b += f'''
  <text x="1424" y="452" font-family="{SANS}" font-size="13" fill="#9C8CC0">Painting your portrait — about 20 seconds left</text>
  <text x="1364" y="500" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">Images never become 3D models or accessories.</text>'''

    # gallery
    b += panel(1332, 564, 548, 366, rx=24, s=0.8, sheen=64)
    b += banner(1606, 552, 300, "YOUR GRAPHICS")
    for i in range(2):
        x = 1364 + i * 250
        b += f'''
  <rect x="{x}" y="612" width="226" height="176" rx="18" fill="#100A22" stroke="url(#goldBar)" stroke-width="2.2"/>'''
        b += glyph_picture(x + 113, 700, 1.32, warm=(i == 0))
        b += f'''
  <text x="{x+113}" y="{818}" font-family="{SANS}" font-size="13.5" font-weight="700" fill="#EBDCFF" text-anchor="middle">{"heroic golden light" if i==0 else "neon city rooftop"}</text>
  <text x="{x+113}" y="{840}" font-family="{SANS}" font-size="12" fill="#9C8CC0" text-anchor="middle">{"Bust" if i==0 else "Full body"}</text>'''
        b += ghost_hex(x, 856, 226, 44, "Copy link", 15)
    return document("Forge — Avatar Graphics", b)


# --------------------------------------------------------------------------
# 5. SETTINGS
# --------------------------------------------------------------------------
def toggle(x, y, on, label, note, tx=None):
    """Label + note on the left, a gold-knobbed track on the right."""
    tx = tx if tx is not None else x + 340
    knob = tx + (84 if on else 28)
    track = "url(#gemMint)" if on else "#2A1B4C"
    return f'''
  <text x="{x}" y="{y+8}" font-family="{SERIF}" font-size="19" font-weight="700" fill="#FFE9BC">{label}</text>
  <text x="{x}" y="{y+34}" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">{note}</text>
  <rect x="{tx}" y="{y-16}" width="112" height="46" rx="23" fill="{track}" stroke="url(#goldBar)" stroke-width="2.2"/>
  <text x="{tx+38 if on else tx+76}" y="{y+13}" font-family="{SANS}" font-size="12.5" font-weight="800" fill="{'#08331F' if on else '#A594C4'}" text-anchor="middle">{'ON' if on else 'OFF'}</text>
  <circle cx="{knob}" cy="{y+7}" r="17" fill="url(#goldBar)" stroke="#FFF3C4" stroke-width="1.8"/>'''


def settings():
    b = chrome("Settings", "Settings",
               "Create mode, accessibility, audio, what is equipped right now, and your achievements.", 386)

    # create mode
    b += panel(296, 252, 784, 262, rx=26, s=0.85, sheen=84)
    b += banner(688, 240, 300, "CREATE MODE")
    b += f'''
  <text x="332" y="332" font-family="{SERIF}" font-size="26" font-weight="700" fill="#FFE9BC">Simple Mode</text>
  <text x="332" y="364" font-family="{SANS}" font-size="14.5" fill="#CDBBEE">One way to make something, a text box, and a few ideas to tap.</text>
  <text x="332" y="388" font-family="{SANS}" font-size="14.5" fill="#CDBBEE">Turn it off to unlock every method, style, fit, pricing and sharing.</text>'''
    b += molten_hex(332, 414, 348, 64, "Simple Mode · ON", 20)
    b += ghost_hex(700, 414, 344, 64, "Advanced Mode", 20)

    # accessibility
    b += panel(296, 538, 784, 300, rx=26, s=0.85, sheen=84)
    b += banner(688, 526, 320, "ACCESSIBILITY")
    b += toggle(332, 610, False, "Reduce motion", "Turns off pulses, drifting embers and sweeps.")
    b += toggle(332, 700, False, "High contrast", "Darker panels, brighter text and borders.")
    b += f'''
  <text x="332" y="786" font-family="{SERIF}" font-size="19" font-weight="700" fill="#FFE9BC">Interface size</text>'''
    b += bar(672, 772, 372, 16, 0.5, "fillGold")
    b += f'''
  <circle cx="{672+186}" cy="780" r="15" fill="url(#goldBar)" stroke="#FFF3C4" stroke-width="1.8"/>
  <text x="332" y="812" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">100%</text>'''

    # audio
    b += panel(296, 862, 784, 182, rx=26, s=0.85, sheen=56)
    b += banner(688, 850, 240, "AUDIO")
    b += toggle(332, 946, True, "Sound effects", "Taps, forge chimes and reward stings.")

    # equipped
    b += panel(1112, 252, 768, 356, rx=26, s=0.85, sheen=84)
    b += banner(1496, 240, 300, "EQUIPPED NOW")
    eq = [("Crystal Dragon Wings", "Back", "wings", 0.42),
          ("Sunspire Crown", "Hat", "crown", 0.46),
          ("Cyber Visor", "Face", "visor", 0.46)]
    for i, (nm, slot, glyph, gs) in enumerate(eq):
        y = 316 + i * 88
        b += f'''
  <rect x="1146" y="{y}" width="700" height="76" rx="18" fill="#241645" fill-opacity="0.72" stroke="#C9A24A" stroke-width="1.4" stroke-opacity="0.5"/>
  <rect x="1160" y="{y+10}" width="56" height="56" rx="12" fill="#160E30" stroke="url(#goldBar)" stroke-width="1.8"/>'''
        b += ITEM_GLYPHS[glyph](1188, y + 38, gs * 0.5)
        b += f'''
  <text x="1236" y="{y+34}" font-family="{SERIF}" font-size="19" font-weight="700" fill="#FFE9BC">{nm}</text>
  <text x="1236" y="{y+58}" font-family="{SANS}" font-size="13" fill="#9C8CC0">{slot} accessory</text>'''
        b += ghost_hex(1690, y + 16, 140, 44, "Remove", 15, stroke="#C9A24A")

    # achievements
    b += panel(1112, 632, 768, 412, rx=26, s=0.85, sheen=84)
    b += banner(1496, 620, 320, "ACHIEVEMENTS")
    ach = [("First Forge", True, "gemGold"), ("Ten Made", True, "gemCyan"),
           ("Shared It", True, "gemMint"), ("Runway Win", False, "gemRose"),
           ("Big Spender", False, "gemRuby"), ("Week Streak", True, "gemAmethyst"),
           ("Collector", False, "gemCyan"), ("Legend", False, "gemGold")]
    for i, (nm, earned, gem) in enumerate(ach):
        col, row = i % 4, i // 4
        cx = 1216 + col * 186
        cy = 730 + row * 180
        if earned:
            b += f'''
  <g filter="url(#goldGlow)"><circle cx="{cx}" cy="{cy}" r="46" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="3.2"/></g>
  <circle cx="{cx}" cy="{cy}" r="37" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.45"/>
  <path d="M{cx} {cy-22} l6.4 15.6 15.6 6.4 -15.6 6.4 -6.4 15.6 -6.4 -15.6 -15.6 -6.4 15.6 -6.4 z" fill="url(#{gem})" stroke="#FFF3C4" stroke-width="1.2"/>
  <text x="{cx}" y="{cy+72}" font-family="{SANS}" font-size="13.5" font-weight="700" fill="#FFE9BC" text-anchor="middle">{nm}</text>'''
        else:
            b += f'''
  <circle cx="{cx}" cy="{cy}" r="46" fill="#1B1138" fill-opacity="0.8" stroke="#6B5B8A" stroke-width="2.4" stroke-dasharray="6 5"/>
  <rect x="{cx-13}" y="{cy-6}" width="26" height="22" rx="5" fill="none" stroke="#8E76B8" stroke-width="2.4"/>
  <path d="M{cx-7} {cy-6} v-7 a7 7 0 0 1 14 0 v7" fill="none" stroke="#8E76B8" stroke-width="2.4"/>
  <text x="{cx}" y="{cy+72}" font-family="{SANS}" font-size="13.5" font-weight="700" fill="#8E7FB4" text-anchor="middle">{nm}</text>'''
    return document("Forge — Settings", b)


# --------------------------------------------------------------------------
def arcade():
    b = modal_backdrop("Create")
    b += modal_panel(300, 108, 1440, 904)
    b += close_button(1692, 160)

    # header
    b += f'''
  <g transform="translate(376,178)">
    <circle r="38" fill="#FF5B97" fill-opacity="0.22" stroke="url(#goldBar)" stroke-width="3"/>
    <circle r="29" fill="none" stroke="#FF9ED6" stroke-width="1.2" opacity="0.6"/>
    <text x="0" y="13" font-size="34" text-anchor="middle">🕹️</text>
  </g>
  <text x="436" y="176" font-family="{SERIF}" font-size="42" font-weight="700" fill="url(#goldEdge)" letter-spacing="4">ARCADE</text>
  <text x="438" y="206" font-family="{SANS}" font-size="16" fill="#CDBBEE">11 games, one weekly leaderboard. Play free, earn Forge Tokens.</text>'''

    # weekly reward banner
    b += f'''
  <rect x="1064" y="146" width="580" height="64" rx="20" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="2.4"/>
  <rect x="1072" y="154" width="564" height="48" rx="15" fill="none" stroke="#FFD98A" stroke-width="1" opacity="0.3"/>
  <path d="M1104 168 l5.6 13.6 13.6 5.6 -13.6 5.6 -5.6 13.6 -5.6 -13.6 -13.6 -5.6 13.6 -5.6 z" fill="url(#gemGold)"/>
  <text x="1136" y="174" font-family="{SERIF}" font-size="15" font-weight="700" fill="#FFE3A6" letter-spacing="1.8">WEEKLY TOP 3, EVERY GAME</text>
  <text x="1136" y="196" font-family="{SANS}" font-size="13.5" fill="#C6AE7A">150 · 83 · 33 tokens, reset every Monday</text>'''
    b += f'''
  <path d="M340 250 h1360" stroke="url(#goldSoft)" stroke-width="1" opacity="0.3"/>
  <use href="#flourish" transform="translate(1020,250) scale(0.55)"/>'''

    games = [
        ("#37DCFF", "🐦", "Flappy Bird", "Flap through the gap.", "42"),
        ("#4CEFAF", "🦖", "Dino Runner", "Jump the cacti.", "318"),
        ("#FF5B97", "🎨", "Color Switch", "Bounce through the right colour.", "27"),
        ("#875EFF", "🐍", "Neon Snake", "Grow without biting yourself.", "96"),
        ("#FF5B6A", "🧱", "Block Stacker", "Stack it straight, don't miss.", "54"),
        ("#FF9542", "🏓", "Brick Breaker", "Steer the paddle, clear the bricks.", "1,204"),
        ("#2DCDC4", "🎯", "Reflex Tap", "Tap the lit tile before it's gone.", "63"),
        ("#745CFF", "🔷", "Prism Merge", "Merge prisms, chase huge chains.", "8,410"),
        ("#2CC4FF", "🚀", "Meteor Rush", "Dodge meteors, collect cores.", "742"),
        ("#78C8FF", "☁️", "Sky Hopper", "Bounce higher, don't fall behind.", "211"),
        ("#FFC452", "🔔", "Echo Match", "Watch the pattern, echo it back.", "19"),
    ]
    for i, (col, icon, name, blurb, best) in enumerate(games):
        gx = 340 + (i % 4) * 345
        gy = 288 + (i // 4) * 228
        b += f'''
  <rect x="{gx}" y="{gy}" width="325" height="206" rx="22" fill="url(#panelGlass)" stroke="url(#goldBar)" stroke-width="2.4"/>
  <rect x="{gx+8}" y="{gy+8}" width="309" height="190" rx="16" fill="none" stroke="{col}" stroke-width="1.2" opacity="0.35"/>
  <rect x="{gx+8}" y="{gy+8}" width="309" height="58" rx="16" fill="url(#panelSheen)"/>
  <g transform="translate({gx+58},{gy+58})">
    <circle r="32" fill="{col}" fill-opacity="0.2" stroke="{col}" stroke-width="2.6"/>
    <circle r="24" fill="none" stroke="#FFFFFF" stroke-width="1" opacity="0.25"/>
    <text x="0" y="11" font-size="28" text-anchor="middle">{icon}</text>
  </g>
  <text x="{gx+102}" y="{gy+52}" font-family="{SERIF}" font-size="21" font-weight="700" fill="#FFE9BC">{name}</text>
  <text x="{gx+102}" y="{gy+76}" font-family="{SANS}" font-size="12.5" fill="#9C8CC0">{blurb}</text>
  <path d="M{gx+20} {gy+108} h285" stroke="url(#goldSoft)" stroke-width="1" opacity="0.25"/>
  <text x="{gx+24}" y="{gy+134}" font-family="{SANS}" font-size="11.5" font-weight="700" fill="#8E7FB4" letter-spacing="1.6">YOUR BEST</text>
  <text x="{gx+24}" y="{gy+170}" font-family="{SERIF}" font-size="30" font-weight="700" fill="{col}">{best}</text>'''
        b += molten_hex(gx + 172, gy + 128, 134, 54, "▶ GO", 19)

    # leaderboard tile
    lx, ly = 340 + 3 * 345, 288 + 2 * 228
    b += f'''
  <g filter="url(#goldGlow)"><rect x="{lx}" y="{ly}" width="325" height="206" rx="22" fill="#2E1B54" stroke="url(#goldBar)" stroke-width="3"/></g>
  <rect x="{lx+8}" y="{ly+8}" width="309" height="190" rx="16" fill="none" stroke="#FFD98A" stroke-width="1.2" opacity="0.45"/>
  <g transform="translate({lx+58},{ly+58})">
    <circle r="32" fill="#FFC452" fill-opacity="0.22" stroke="url(#goldBar)" stroke-width="2.6"/>
    <text x="0" y="11" font-size="28" text-anchor="middle">🏆</text>
  </g>
  <text x="{lx+102}" y="{ly+52}" font-family="{SERIF}" font-size="21" font-weight="700" fill="#FFE9BC">Leaderboard</text>
  <text x="{lx+102}" y="{ly+76}" font-family="{SANS}" font-size="12.5" fill="#9C8CC0">Global and friends standings.</text>
  <path d="M{lx+20} {ly+108} h285" stroke="url(#goldSoft)" stroke-width="1" opacity="0.25"/>
  <text x="{lx+24}" y="{ly+134}" font-family="{SANS}" font-size="11.5" font-weight="700" fill="#8E7FB4" letter-spacing="1.6">YOUR BEST RANK</text>
  <text x="{lx+24}" y="{ly+170}" font-family="{SERIF}" font-size="30" font-weight="700" fill="#FFC452">#4</text>'''
    b += molten_hex(lx + 172, ly + 128, 134, 54, "OPEN", 19)
    return document("Forge — Arcade", b, MODAL_DEFS)


def runway():
    b = modal_backdrop("Create")
    b += modal_panel(300, 108, 1440, 904)
    b += f'''
  <ellipse cx="1020" cy="130" rx="520" ry="240" fill="url(#spotlight)"/>'''
    b += close_button(1692, 160)

    # header
    b += f'''
  <g transform="translate(376,180)">
    <circle r="38" fill="#FF5B97" fill-opacity="0.2" stroke="url(#goldBar)" stroke-width="3"/>
    <circle r="29" fill="none" stroke="#FF9ED6" stroke-width="1.2" opacity="0.6"/>
    <path d="M0 -17 l17 17 -17 17 -17 -17 z" fill="url(#gemRose)" stroke="#FFD3EC" stroke-width="1.6"/>
  </g>
  <text x="436" y="176" font-family="{SERIF}" font-size="42" font-weight="700" fill="url(#goldEdge)" letter-spacing="3">FORGE RUNWAY</text>
  <text x="438" y="208" font-family="{SANS}" font-size="16" fill="#CDBBEE">Tonight's theme · <tspan fill="#FF9ED6" font-weight="700">Neon Royalty</tspan> — lock a look, then vote.</text>'''

    # countdown
    b += f'''
  <g transform="translate(1592,182)">
    <circle r="54" fill="#160E30" stroke="url(#goldBar)" stroke-width="3"/>
    <circle r="44" fill="none" stroke="#3A2560" stroke-width="8"/>
    <circle r="44" fill="none" stroke="url(#fillGold)" stroke-width="8" stroke-linecap="round" stroke-dasharray="176 100" transform="rotate(-90)"/>
    <text x="0" y="2" font-family="{SERIF}" font-size="26" font-weight="700" fill="url(#goldEdge)" text-anchor="middle">4:12</text>
    <text x="0" y="22" font-family="{SANS}" font-size="9.5" font-weight="700" fill="#C6AE7A" letter-spacing="1.8" text-anchor="middle">LEFT</text>
  </g>'''
    b += ghost_hex(1180, 156, 232, 52, "↺ View activity", 16)
    b += f'''
  <path d="M340 254 h1360" stroke="url(#goldSoft)" stroke-width="1" opacity="0.3"/>
  <use href="#flourish" transform="translate(1020,254) scale(0.55)"/>'''

    # lineup
    b += panel(340, 292, 780, 692, rx=26, s=0.9, sheen=76)
    b += banner(730, 280, 340, "RUNWAY LINEUP · 6 JOINED", "#FF9ED6")
    entries = [("@zaraBuilds", "Crystal Dragon Wings", "24", True, "gemCyan", "#D9F6FF"),
               ("@kit_9", "Neon Jellyfish Backpack", "18", False, "gemMint", "#DDFFF0"),
               ("@mossy", "Tiny Mushroom Crown", "15", False, "gemRose", "#FFE0F2"),
               ("@pix", "Moth Queen Wings", "9", False, "gemAmethyst", "#F1E4FF"),
               ("@ember", "Molten Lava Horns", "6", False, "gemRuby", "#FFE0E4")]
    for i, (who, look, votes, leading, tint, edge) in enumerate(entries):
        y = 344 + i * 126
        stroke = "url(#goldBar)" if leading else "#C9A24A"
        b += f'''
  <rect x="368" y="{y}" width="724" height="110" rx="20" fill="{'#3A1F52' if leading else '#241645'}" fill-opacity="{1 if leading else 0.72}" stroke="{stroke}" stroke-width="{2.6 if leading else 1.4}" stroke-opacity="{1 if leading else 0.5}"/>'''
        b += portrait(384, y + 12, 86, tint, edge)
        b += f'''
  <text x="490" y="{y+46}" font-family="{SERIF}" font-size="21" font-weight="700" fill="#FFE9BC">{who}</text>
  <text x="490" y="{y+72}" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">{look}</text>'''
        if leading:
            b += f'''
  <path d="M{462} {y+22} l5 -5 5 5 -5 5 z" fill="url(#gemGold)"/>
  <text x="490" y="{y+94}" font-family="{SANS}" font-size="11.5" font-weight="700" fill="#FFC85A" letter-spacing="1.4">LEADING THE ROUND</text>'''
        b += molten_hex(902, y + 30, 174, 50, f"♥ Vote · {votes}", 17) if leading \
            else ghost_hex(902, y + 30, 174, 50, f"♥ Vote · {votes}", 17)

    # your look
    b += panel(1150, 292, 550, 320, rx=26, s=0.85, sheen=70)
    b += banner(1425, 280, 260, "YOUR LOOK", "#9DF5CE")
    b += portrait(1184, 336, 132)
    b += f'''
  <text x="1342" y="376" font-family="{SERIF}" font-size="22" font-weight="700" fill="#FFE9BC">Sunspire Crown</text>
  <text x="1342" y="402" font-family="{SANS}" font-size="13.5" fill="#9C8CC0">+ Crystal Dragon Wings</text>
  <text x="1342" y="432" font-family="{SANS}" font-size="13" fill="#8E7FB4">Change it in My Studio before you lock.</text>'''
    b += molten_rect(1184, 496, 484, 74, "Lock in my look", 24, rx=24, glow=False)
    b += f'''
  <text x="1426" y="596" font-family="{SANS}" font-size="13" fill="#9C8CC0" text-anchor="middle">Free to enter · one look per round</text>'''

    # weekly spotlight
    b += panel(1150, 638, 550, 346, rx=26, s=0.85, sheen=70)
    b += banner(1425, 626, 300, "WEEKLY SPOTLIGHT")
    b += f'''
  <text x="1425" y="692" font-family="{SANS}" font-size="12.5" fill="#9C8CC0" text-anchor="middle">Rounds, votes cast and received, placements</text>'''
    board = [("1", "@zaraBuilds", "1,240", "url(#gemGold)", "#3A1206"),
             ("2", "@mossy", "980", "url(#gemCyan)", "#0E3550"),
             ("3", "@kit_9", "845", "url(#gemRose)", "#4A0E2E"),
             ("4", "You", "612", "#2E1B54", "#FFE3A6"),
             ("5", "@pix", "430", "#2E1B54", "#FFE3A6")]
    for i, (rank, who, pts, medal, ink) in enumerate(board):
        y = 712 + i * 52
        me = who == "You"
        b += f'''
  <rect x="1184" y="{y}" width="484" height="44" rx="14" fill="{'#3A1F52' if me else '#241645'}" fill-opacity="{1 if me else 0.6}" stroke="{'url(#goldBar)' if me else '#C9A24A'}" stroke-width="{2.2 if me else 1.2}" stroke-opacity="{1 if me else 0.45}"/>
  <circle cx="1220" cy="{y+22}" r="15" fill="{medal}" stroke="url(#goldBar)" stroke-width="2"/>
  <text x="1220" y="{y+28}" font-family="{SERIF}" font-size="16" font-weight="700" fill="{ink}" text-anchor="middle">{rank}</text>
  <text x="1248" y="{y+28}" font-family="{SANS}" font-size="15" font-weight="700" fill="{'#FFE9BC' if me else '#EBDCFF'}">{who}</text>
  <text x="1648" y="{y+28}" font-family="{SERIF}" font-size="16" font-weight="700" fill="#FFC85A" text-anchor="end">{pts} pts</text>'''
    return document("Forge — Runway", b, MODAL_DEFS)


SCREENS = {
    "forge-my-studio.svg": my_studio,
    "forge-discover.svg": discover,
    "forge-avatar-lab.svg": avatar_lab,
    "forge-avatar-graphics.svg": avatar_graphics,
    "forge-settings.svg": settings,
    "forge-arcade.svg": arcade,
    "forge-runway.svg": runway,
}

if __name__ == "__main__":
    for name, fn in SCREENS.items():
        (HERE / name).write_text(fn())
        print("wrote", name)
