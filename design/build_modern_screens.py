"""Editable SVG screens using the supplied forge-ugc.svg design language.

Each artwork component has an ID/bounds; text stays as SVG text so the
later Roblox export can remove it and recreate it with native controls.
This design-only tool never changes game scripts or uploads anything.
"""
from __future__ import annotations

import argparse
import copy
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
OUT = HERE / "screens"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
REFERENCE = ET.parse(HERE / "home" / "forge-ugc.svg").getroot()
REF_IDS = {e.get("id"): e for e in REFERENCE.iter() if e.get("id")}
WHITE, MUTED, CYAN, PURPLE, GOLD = "#f6faff", "#b0bed9", "#00caff", "#bf67ff", "#ffd04e"


def element(parent, tag, **attrs):
    return ET.SubElement(parent, f"{{{NS}}}{tag}", {k.replace("_", "-"): str(v) for k, v in attrs.items()})


def group(parent, name, bounds=None, **attrs):
    if bounds:
        attrs["data_bounds"] = " ".join(map(str, bounds))
    return element(parent, "g", id=name, **attrs)


def rect(parent, x, y, w, h, fill, radius=16, stroke=None, **attrs):
    if stroke:
        attrs.update(stroke=stroke, stroke_width=2)
    return element(parent, "rect", x=x, y=y, width=w, height=h, rx=radius, fill=fill, **attrs)


def text(parent, value, x, y, size=20, fill=WHITE, weight=400, anchor="start", **attrs):
    node = element(parent, "text", x=x, y=y, font_family="Arial, sans-serif", font_size=size,
                   font_weight=weight, fill=fill, text_anchor=anchor, **attrs)
    node.text = value
    return node


def lines(parent, values, x, y, size=20, fill=MUTED, gap=None, weight=400):
    for i, value in enumerate(values):
        text(parent, value, x, y + i * (gap or size * 1.4), size, fill, weight)


def icon(parent, ref, x, y, w=32, h=None, **attrs):
    return element(parent, "use", href=f"#{ref}", x=x, y=y, width=w, height=h or w, **attrs)


def panel(parent, name, x, y, w, h, theme="blue"):
    accent = {"blue": CYAN, "purple": PURPLE, "gold": GOLD}[theme]
    art = group(parent, name, (x - 8, y - 8, w + 16, h + 20), data_asset=name)
    rect(art, x, y, w, h, f"url(#screen-{theme})", 26, accent, filter="url(#small-shadow)")
    rect(art, x + 2, y + 2, w - 4, h - 4, "none", 25, "#ffffff", stroke_opacity=".08")
    rect(art, x + 9, y + 6, w - 18, 66, "url(#screen-sheen)", 20)
    element(art, "path", d=f"M{x+w*.52} {y+2}L{x+w*.88} {y+2}L{x+w*.52} {y+h-2}L{x+w*.16} {y+h-2}Z",
            fill="#ffffff", opacity=".025")
    return art


def button(parent, name, caption, x, y, w, h=54, theme="blue", size=21, quiet=False):
    accent = {"blue": CYAN, "purple": PURPLE, "gold": GOLD}[theme]
    art = group(parent, name, (x - 8, y - 8, w + 16, h + 20), data_asset=name)
    rect(art, x, y, w, h, "#14223b" if quiet else f"url(#{theme}-button)",
         min(20, h / 2), "#345278" if quiet else accent, filter="url(#small-shadow)")
    if not quiet:
        rect(art, x + 8, y + 5, w - 16, h * .37, "url(#screen-sheen)", 12)
        element(art, "path", d=f"M{x+18} {y+2}H{x+w-18}", stroke="#ffffff", stroke_opacity=".45")
    text(parent, caption, x + w / 2, y + h / 2 + size * .34, size, WHITE, 700, "middle",
         data_native="TextButton", filter="url(#text-shadow)" if not quiet else "none")
    return art


def small_symbols(defs):
    sym = element(defs, "symbol", id="screen-crown", viewBox="0 0 64 64")
    element(sym, "path", d="M9 45 4 18 22 31 31 10 42 31 60 18 54 45Z", fill="url(#purple-icon)", stroke="#e2bdff", stroke_width=2.5)
    element(sym, "path", d="M10 45H54V55Q31 62 10 55Z", fill="url(#purple-dark)", stroke="#c47aff", stroke_width=2)
    for x, y in [(8, 19), (31, 11), (58, 19)]:
        element(sym, "circle", cx=x, cy=y, r=3, fill="#f4ddff")
    element(sym, "path", d="m31 35 6 7-6 7-6-7Z", fill="url(#cyan-icon)", stroke="#c2ffff")
    sym = element(defs, "symbol", id="screen-wings", viewBox="0 0 64 64")
    element(sym, "path", d="M30 51Q10 51 3 13Q22 18 30 35L32 18 34 35Q45 18 61 13Q57 48 34 51L32 59Z",
            fill="url(#cyan-dark)", stroke="#66efff", stroke_width=2)
    element(sym, "path", d="m6 17 21 22-15-1 16 9M58 17 37 39l15-1-16 9M32 24V56", fill="none", stroke="#a4ffff", stroke_width=1.7)
    sym = element(defs, "symbol", id="screen-sword", viewBox="0 0 64 64")
    element(sym, "path", d="M13 44 45 5 58 4 57 17 21 51Z", fill="url(#cyan-icon)", stroke="#a1ffff", stroke_width=2)
    element(sym, "path", d="M13 42 27 54M7 54l9-9 9 8-9 9Z", fill="#163359", stroke="#70cbff", stroke_width=3)
    element(sym, "path", d="M20 43 49 11", stroke="#e3ffff", stroke_width=2)
    sym = element(defs, "symbol", id="screen-hat", viewBox="0 0 64 64")
    element(sym, "path", d="M15 39 13 12Q31 4 49 12L47 39Z", fill="url(#gold)", stroke="#ffe9a3", stroke_width=2)
    element(sym, "ellipse", cx=32, cy=42, rx=29, ry=9, fill="url(#gold)", stroke="#ffe9a3", stroke_width=2)
    element(sym, "path", d="M15 30Q31 37 49 30V37Q31 44 15 37Z", fill="#6a3218")
    element(sym, "circle", cx=35, cy=34, r=6, fill="#ffe4a1", stroke="#9c4a13", stroke_width=2)
    sym = element(defs, "symbol", id="screen-fairy", viewBox="0 0 64 64")
    element(sym, "path", d="M30 30Q10 -2 4 17Q1 29 24 35Q1 42 11 55Q23 65 31 38Q42 65 53 54Q63 41 39 34Q62 26 59 13Q49 -1 34 30Z",
            fill="url(#purple-icon)", stroke="#ffd4ff", stroke_width=2)
    element(sym, "path", d="M32 22V49M14 17 27 32 14 48M50 15 38 32 50 47", fill="none", stroke="#e4aaff", stroke_width=1.7)


def screen(title, selected="Create"):
    root = ET.Element(f"{{{NS}}}svg", {"width": "1672", "height": "941", "viewBox": "0 0 1672 941",
        "role": "img", "aria-labelledby": "screen-title screen-description"})
    element(root, "title", id="screen-title").text = f"Forge UGC — {title}"
    element(root, "desc", id="screen-description").text = (
        "Editable screen design matching the supplied Home SVG. Artwork and text are separate. "
        "Sample balances, items and prices are design placeholders; the game uses live player data.")
    defs = copy.deepcopy(REFERENCE.find(f"{{{NS}}}defs"))
    root.append(defs)
    for name, stops in {"blue": ["#06355c", "#082443", "#111b32"],
                        "purple": ["#322052", "#23183c", "#141a30"],
                        "gold": ["#553514", "#352718", "#172033"]}.items():
        grad = element(defs, "linearGradient", id=f"screen-{name}", x1="0", y1="0", x2=".3", y2="1")
        for offset, color in zip(["0", ".55", "1"], stops):
            element(grad, "stop", offset=offset, stop_color=color)
    sheen = element(defs, "linearGradient", id="screen-sheen", x1="0", y1="0", x2="0", y2="1")
    element(sheen, "stop", stop_color="#ffffff", stop_opacity=".16")
    element(sheen, "stop", offset="1", stop_color="#ffffff", stop_opacity="0")
    small_symbols(defs)
    art = element(defs, "symbol", id="screen-create-art", viewBox="77 244 505 490")
    art.append(copy.deepcopy(REF_IDS["left-art"]))
    for name in ["blurred-city-backdrop", "main-dashboard", "currency-and-settings", "forge-ugc-logo"]:
        part = copy.deepcopy(REF_IDS[name])
        if name == "currency-and-settings":
            for node in part.iter(f"{{{NS}}}text"):
                node.text = "0"
                node.set("data-native", "BalanceLabel")
        root.append(part)
    nav = group(root, "screen-navigation", (375, 126, 1005, 98))
    rect(nav, 385, 136, 984, 77, "url(#nav-bg)", 19, "#27334f")
    for i, (name, ref, ix, tx) in enumerate([
        ("Home", "home-icon", 445, 496), ("Create", "cube-icon", 692, 742),
        ("Market", "bag-icon", 931, 984), ("Games", "pad-icon", 1176, 1232),
    ]):
        if name == selected:
            rect(nav, 386 + i * 246, 137, 243, 75, "url(#home-button)", 17, CYAN, filter="url(#cyan-glow)")
        icon(nav, ref, ix, 154, 38)
        text(nav, name, tx, 184, 27, WHITE if name == selected else "#c3cfe8", 700, data_native="NavButton")
    if selected == "My Items":
        rect(root, 1399, 144, 154, 62, "url(#home-button)", 17, CYAN, filter="url(#cyan-glow)")
    text(root, "My Items", 1475, 181, 21, WHITE if selected == "My Items" else MUTED, 700, "middle", data_native="NavButton")
    text(root, "×", 1590, 186, 34, MUTED, 700, "middle", data_native="CloseButton")
    return root, defs


def create():
    root, _ = screen("Create UGC")
    title = group(root, "create-heading")
    text(title, "Create UGC", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(title, "Describe it. Wear it.", 80, 313, 21, MUTED)
    mode = group(root, "create-mode-switch", (1257, 247, 350, 61))
    rect(mode, 1257, 251, 350, 53, "#101b30", 17, "#30415f")
    button(mode, "CreateSimpleMode", "Simple", 1262, 256, 163, 43, size=18)
    text(mode, "Advanced", 1515, 284, 18, MUTED, 700, "middle", data_native="ModeButton")
    panel(root, "CreatePromptPanel", 77, 337, 976, 516)
    icon(root, "cube-icon", 109, 367, 32)
    text(root, "Tell us your idea", 155, 392, 28, WHITE, 700)
    text(root, "Describe one accessory. We'll turn it into 3D.", 110, 422, 20, MUTED)
    well = group(root, "CreatePromptField", (107, 441, 917, 131), data_asset="CreatePromptField")
    rect(well, 111, 445, 908, 123, "#0b1930", 18, "#22d3f2")
    rect(well, 117, 451, 896, 111, "none", 13, "#82eaff", stroke_opacity=".1")
    text(root, "Try: a crystal crown with glowing blue gems...", 133, 490, 23, "#8297b5", data_native="PromptPlaceholder")
    text(root, "0 / 500", 995, 546, 17, "#8297b5", anchor="end", data_native="CharacterCount")
    text(root, "Need an idea? Tap one.", 111, 606, 19, "#d3e9ff", 700)
    element(root, "path", d="M349 600H1018", stroke="#386285", stroke_opacity=".65")
    for i, (name, ref) in enumerate([("Dragon Wings", "screen-wings"), ("Crystal Crown", "screen-crown"),
                                   ("Neon Katana", "screen-sword"), ("Steampunk Hat", "screen-hat"), ("Fairy Wings", "screen-fairy")]):
        x = 111 + i * 183
        chip = group(root, f"CreateIdea{i+1}", (x - 3, 622, 179, 61), data_asset=f"CreateIdea{i+1}")
        rect(chip, x, 626, 176, 52, "url(#footer-card)", 14, "#345578")
        icon(chip, ref, x + 10, 637, 29)
        text(root, name, x + 46, 658, 15, "#dbeeff", 700, data_native="IdeaButton")
    button(root, "CreateGenerateButton", "Make My Item  ·  R$ 159   ›", 111, 711, 908, 76, size=29)
    text(root, "Confirm the price in Roblox before paying.", 565, 823, 18, MUTED, anchor="middle", data_native="PaymentNote")
    panel(root, "CreatePreviewPanel", 1078, 337, 529, 516)
    text(root, "Your next creation starts here", 1342, 391, 23, WHITE, 700, "middle")
    hero = group(root, "CreatePreviewArtwork", (1090, 407, 505, 382), data_asset="CreatePreviewArtwork")
    icon(hero, "screen-create-art", 1090, 366, 505, 454)
    rect(root, 1120, 792, 445, 35, "#0c213d", 13, "#305d86")
    text(root, "AI creates it. You make it yours.", 1342, 816, 17, "#c1eaff", 700, "middle")
    text(root, "How it works  ›", 1558, 883, 18, CYAN, 700, "end", data_native="HelpButton")
    return root


def my_items():
    root, defs = screen("My Items", "My Items")
    # Reuse Home's foreground object, excluding its floor, floating gems and
    # ambient particles. The real game uses the selected item's live viewport.
    hair = element(defs, "symbol", id="screen-item-hair", viewBox="245 378 315 300")
    for index, part in enumerate(list(REF_IDS["left-art"])[10:], start=10):
        if index != 80:
            hair.append(copy.deepcopy(part))
    title = group(root, "items-heading")
    text(title, "My Items", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    rect(title, 294, 255, 116, 34, "#18344b", 12, "#315771")
    text(title, "5 items", 352, 278, 17, "#bceaff", 700, "middle", data_native="CollectionCount")
    text(title, "Your creations. Ready for your next look.", 80, 313, 21, MUTED)
    button(root, "ItemsCreateButton", "Create New  ›", 1342, 251, 265, 53, size=21)
    panel(root, "ItemsCollectionPanel", 77, 337, 523, 516, "purple")
    text(root, "My collection", 110, 384, 26, WHITE, 700)
    text(root, "Select an item to preview", 111, 412, 18, MUTED)
    examples = [
        ("Cyber Frost Hair", "screen-item-hair", "Original · Private", "blue"),
        ("Void Crystal Crown", "screen-crown", "Original · Public", "purple"),
        ("Neon Katana", "screen-sword", "Personal copy · No resale", "blue"),
        ("Aether Top Hat", "screen-hat", "Original · Private", "gold"),
        ("Fairy Wings", "screen-fairy", "Original · Private", "purple"),
    ]
    for i, (name, ref, caption, theme) in enumerate(examples):
        x, y, w, h = 105, 433 + i * 78, 467, 72
        row = group(root, f"ItemsCollectionRow{i+1}", (x - 5, y - 5, w + 10, h + 10), data_asset=f"ItemsCollectionRow{i+1}")
        rect(row, x, y, w, h, "#103454" if i == 0 else "#152039", 16,
             CYAN if i == 0 else "#394768", filter="url(#small-shadow)" if i == 0 else "none")
        if i == 0:
            rect(row, x + 2, y + 17, 3, 38, CYAN, 1)
        rect(row, x + 12, y + 8, 56, 56, f"url(#screen-{theme})", 12, "#355677")
        icon(row, ref, x + 16, y + 12, 48)
        text(root, name, x + 86, y + 29, 20, WHITE, 700, data_native="ItemName")
        text(root, caption, x + 86, y + 54, 14, "#a6bcd7", data_native="ItemMetadata")
        text(root, "›", x + w - 23, y + 46, 30, CYAN if i == 0 else "#8599b9", 700, "middle", data_native="SelectItemButton")
    text(root, "Saved to your collection automatically.", 111, 839, 15, "#92a3c4")
    panel(root, "ItemsInspectorPanel", 624, 337, 983, 516)
    text(root, "Cyber Frost Hair", 657, 384, 29, WHITE, 700, data_native="SelectedItemName")
    badges = group(root, "ItemsMetadataPills", (657, 402, 300, 34))
    rect(badges, 657, 402, 108, 31, "#153e4c", 11, "#276877")
    rect(badges, 778, 402, 165, 31, "#282247", 11, "#554578")
    text(root, "ORIGINAL", 711, 423, 13, "#93f3ee", 700, "middle", data_native="LicenseBadge")
    text(root, "AUTO · BALANCED", 860, 423, 13, "#d3b6ff", 700, "middle", data_native="StyleBadge")
    viewport = group(root, "ItemsPreviewWell", (648, 447, 935, 250), data_asset="ItemsPreviewWell")
    rect(viewport, 652, 451, 927, 242, "#0a1830", 18, "#2c6284")
    rect(viewport, 659, 458, 913, 228, "none", 13, "#c5f7ff", stroke_opacity=".05")
    glow = element(defs, "radialGradient", id="items-preview-glow")
    element(glow, "stop", stop_color="#057efc", stop_opacity=".38")
    element(glow, "stop", offset="1", stop_color="#057efc", stop_opacity="0")
    element(viewport, "ellipse", cx=1115, cy=599, rx=360, ry=89, fill="url(#items-preview-glow)")
    for yy, rx in [(656, 201), (672, 269)]:
        element(viewport, "ellipse", cx=1115, cy=yy, rx=rx, ry=10, fill="none", stroke="#0d82c2", stroke_opacity=".33")
    for xx in [836, 944, 1115, 1286, 1394]:
        element(viewport, "path", d=f"M1115 602L{xx} 686", stroke="#175587", stroke_opacity=".4")
    sample = group(root, "ItemsSamplePreview", (931, 455, 368, 228), data_role="ReplaceWithLiveViewport")
    icon(sample, "screen-item-hair", 931, 455, 368, 228)
    hint = group(root, "ItemsOrbitHint", (670, 467, 141, 30), data_asset="ItemsOrbitHint")
    rect(hint, 671, 468, 139, 28, "#172b44", 9, "#2a4965")
    text(root, "Drag to orbit", 740, 487, 14, "#b3d9f6", 700, "middle", data_native="OrbitHint")
    reset = group(root, "ItemsResetCamera", (1522, 460, 43, 43), data_asset="ItemsResetCamera")
    element(reset, "circle", cx=1543, cy=481, r=18, fill="#162b46", stroke="#3c6486", stroke_width=1.5)
    element(reset, "path", d="M1535 480a8 8 0 1 1 4 8M1532 474l3 7 7-3", fill="none", stroke="#b5e6ff", stroke_width=2.2, stroke_linecap="round", stroke_linejoin="round")
    status = group(root, "ItemsReadyStrip", (650, 710, 931, 43), data_asset="ItemsReadyStrip")
    rect(status, 652, 712, 927, 39, "#102f3d", 12, "#287277")
    element(status, "circle", cx=677, cy=731, r=10, fill="#80f0c3")
    element(status, "path", d="m672 731 4 4 7-8", fill="none", stroke="#103e37", stroke_width=2.4, stroke_linecap="round", stroke_linejoin="round")
    text(root, "Ready to wear", 699, 739, 20, "#a1ffdc", 700, data_native="ReadinessStatus")
    text(root, "3D model ready", 1557, 738, 16, "#a7c8cc", anchor="end", data_native="ReadinessDetail")
    button(root, "ItemsEquipButton", "Equip in Game  ›", 652, 766, 452, 55, size=23)
    button(root, "ItemsPublishButton", "Publish Wearable", 1127, 766, 452, 55, theme="purple", size=22, quiet=True)
    text(root, "Publishing opens Roblox's purchase prompt.", 1115, 845, 16, MUTED, anchor="middle", data_native="PublishNote")
    text(root, "Advanced fit & sharing  ›", 1568, 883, 18, CYAN, 700, "end", data_native="AdvancedModeButton")
    return root


def market_symbols(defs):
    shop = REF_IDS["shop-art"]
    for definition in shop[0]:
        defs.append(copy.deepcopy(definition))
    for name, index, viewbox in [
        ("market-crown", 18, "645 418 250 195"),
        ("market-butterfly-hair", 19, "880 374 220 196"),
    ]:
        symbol = element(defs, "symbol", id=name, viewBox=viewbox)
        symbol.append(copy.deepcopy(shop[index]))
    # Retain the old item's vector geometry while using the new Home palette.
    sword = element(defs, "symbol", id="market-katana", viewBox="55 45 200 205")
    old = ET.parse(HERE / "assets" / "item_katana.svg").getroot()
    palette = {"arcGlow": "cyan-glow", "gemCyan": "cyan-icon", "gemGold": "gold",
               "goldBar": "gold", "goldSoft": "gold"}
    for part in old:
        if part.tag == f"{{{NS}}}defs":
            continue
        part = copy.deepcopy(part)
        for node in part.iter():
            for attr, value in list(node.attrib.items()):
                for previous, current in palette.items():
                    value = value.replace(f"url(#{previous})", f"url(#{current})")
                node.set(attr, value)
        sword.append(part)
    skin = element(defs, "linearGradient", id="market-avatar-skin", x1="0", y1="0", x2=".7", y2="1")
    for offset, color in [("0", "#fff0d6"), (".55", "#f4c79f"), ("1", "#c98964")]:
        element(skin, "stop", offset=offset, stop_color=color)
    body = element(defs, "linearGradient", id="market-avatar-shirt", x1="0", y1="0", x2=".6", y2="1")
    for offset, color in [("0", "#169fe7"), (".45", "#0d4f8b"), ("1", "#082c50")]:
        element(body, "stop", offset=offset, stop_color=color)
    avatar = element(defs, "symbol", id="market-avatar", viewBox="0 0 300 340")
    element(avatar, "ellipse", cx=150, cy=324, rx=91, ry=11, fill="#0acfff", opacity=".12")
    for x in [103, 156]:
        rect(avatar, x, 226, 43, 91, "url(#screen-blue)", 12, "#23496a")
        rect(avatar, x + 4, 269, 35, 5, "#1d7499", 2)
        rect(avatar, x - 2, 300, 49, 23, "#092742", 9, "#276485")
        element(avatar, "path", d=f"M{x+2} 311H{x+40}", stroke="#35d8f2", stroke_width=3)
    for x, angle in [(63, 8), (199, -8)]:
        arm = element(avatar, "g", transform=f"rotate({angle} {x+20} 145)")
        rect(arm, x, 138, 39, 92, "url(#market-avatar-shirt)", 13, "#22638d")
        rect(arm, x + 4, 210, 33, 33, "url(#market-avatar-skin)", 10, "#c28e73")
        element(arm, "path", d=f"M{x+7} 151V203", stroke="#77dcff", stroke_width=2, opacity=".5")
    rect(avatar, 97, 126, 106, 116, "url(#market-avatar-shirt)", 18, "#3778a0")
    element(avatar, "path", d="M184 130 200 142V225L185 237Z", fill="#05264c", opacity=".7")
    rect(avatar, 122, 153, 58, 7, "url(#cyan-icon)", 3)
    rect(avatar, 133, 176, 37, 37, "#0a2a49", 10, "#2d7197")
    element(avatar, "path", d="m152 185 10 10-10 10-10-10Z", fill="url(#cyan-icon)")
    element(avatar, "path", d="M103 223H196", stroke="#81b7d3", stroke_width=3, opacity=".4")
    rect(avatar, 135, 107, 29, 31, "url(#market-avatar-skin)", 9)
    rect(avatar, 107, 42, 87, 82, "url(#market-avatar-skin)", 22, "#ebc29e")
    element(avatar, "path", d="M181 48Q194 53 194 67V106Q190 120 179 122V52Z", fill="#bd865f", opacity=".45")
    element(avatar, "path", d="M118 53Q139 46 173 52", fill="none", stroke="#fff4e3", stroke_width=4, opacity=".8", stroke_linecap="round")
    for x in [132, 165]:
        element(avatar, "ellipse", cx=x, cy=79, rx=3.3, ry=4.5, fill="#272634")
    element(avatar, "path", d="M133 97Q149 110 165 97", fill="none", stroke="#66433c", stroke_width=3, stroke_linecap="round")


def market():
    root, defs = screen("Market", "Market")
    market_symbols(defs)
    title = group(root, "market-heading")
    text(title, "Market", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(title, "Find your next look. Try community creations for free.", 80, 313, 21, MUTED)
    badge = group(root, "MarketFreeTryOnBadge", (1371, 256, 236, 38), data_asset="MarketFreeTryOnBadge")
    rect(badge, 1371, 256, 236, 38, "#25213f", 13, "#715093")
    text(root, "FREE TO TRY ON", 1489, 282, 17, "#dfbeff", 700, "middle")
    search = group(root, "MarketSearchField", (72, 332, 862, 64), data_asset="MarketSearchField")
    rect(search, 77, 337, 852, 54, "#0d1b32", 17, CYAN)
    element(search, "circle", cx=107, cy=362, r=9, fill="none", stroke="#87e9ff", stroke_width=2.5)
    element(search, "path", d="m114 369 7 7", stroke="#87e9ff", stroke_width=2.5, stroke_linecap="round")
    text(root, "Search public designs...", 138, 372, 21, "#8ca4c3", data_native="SearchPlaceholder")
    button(root, "MarketSearchButton", "Search", 951, 337, 167, 54, size=21)
    text(root, "Community creations", 79, 425, 22, WHITE, 700)
    cards = [
        ("Void Crystal Crown", "market-crown", "@nova", "128", "42"),
        ("Butterfly Bob", "market-butterfly-hair", "@lumi", "96", "31"),
        ("Neon Katana", "market-katana", "@mossy", "74", "19"),
    ]
    for i, (name, ref, creator, likes, favorites) in enumerate(cards):
        x, y, w, h = 77 + i * 354, 445, 333, 408
        prefix = f"MarketCard{i+1}"
        panel(root, prefix + "Panel", x, y, w, h, "purple")
        well = group(root, prefix + "PreviewWell", (x + 12, y + 12, w - 24, 194), data_asset=prefix + "PreviewWell")
        rect(well, x + 16, y + 16, w - 32, 186, "#11172c", 16, "#75569c")
        element(well, "ellipse", cx=x+w/2, cy=y+136, rx=122, ry=46, fill="url(#shop-aura)", opacity=".58")
        element(well, "ellipse", cx=x+w/2, cy=y+180, rx=100, ry=11, fill="#8a27d2", opacity=".16")
        sample = group(root, prefix + "SampleModel", (x + 24, y + 21, w - 48, 174), data_role="ReplaceWithLiveItemThumbnail")
        icon(sample, ref, x + 24, y + 21, w - 48, 174)
        text(root, name, x + w/2, y + 238, 21, WHITE, 700, "middle", data_native="ItemTitle")
        text(root, "by " + creator, x + w/2, y + 266, 17, MUTED, anchor="middle", data_native="CreatorName")
        button(root, prefix + "TryOnButton", "Try On  ›", x + 16, y + 289, w - 32, 54, theme="purple", size=23)
        for j, (count, kind) in enumerate([(likes, "Like"), (favorites, "Favorite")]):
            bx, by, bw = x + 16 + j * 157, y + 357, 144
            social = group(root, prefix + kind + "Button", (bx, by, bw, 35), data_asset=prefix + kind + "Button")
            rect(social, bx, by, bw, 35, "#181e37", 11, "#4b4566")
            if kind == "Like":
                element(social, "path", d=f"M{bx+25} {by+12}c-5-6-13-2-13 4 0 6 9 12 13 15 4-3 13-9 13-15 0-6-8-10-13-4Z",
                        fill="none", stroke="#ff87b4", stroke_width=2.1, transform=f"translate(0 -3)")
            else:
                element(social, "path", d=f"m{bx+25} {by+7} 3.3 6.7 7.4 1.1-5.4 5.2 1.3 7.4-6.6-3.5-6.6 3.5 1.3-7.4-5.4-5.2 7.4-1.1Z",
                        fill="none", stroke=GOLD, stroke_width=1.8, stroke_linejoin="round")
            text(root, count, bx + 83, by + 24, 17, "#dfdcf2", 700, "middle", data_native=kind + "Count")
    panel(root, "MarketAvatarPanel", 1142, 337, 465, 516)
    text(root, "Your Avatar", 1174, 384, 26, WHITE, 700)
    text(root, "Try an item. See it on you.", 1174, 413, 18, MUTED)
    avatar_well = group(root, "MarketAvatarWell", (1164, 428, 421, 250), data_asset="MarketAvatarWell")
    rect(avatar_well, 1168, 432, 413, 242, "#0a1a31", 18, "#2e6183")
    element(avatar_well, "ellipse", cx=1374, cy=652, rx=119, ry=13, fill="#0787ba", opacity=".21")
    element(avatar_well, "ellipse", cx=1374, cy=652, rx=141, ry=18, fill="none", stroke="#0b80ab", stroke_opacity=".3")
    avatar = group(root, "MarketSampleAvatar", (1230, 437, 284, 230), data_role="ReplaceWithLiveAvatarViewport")
    icon(avatar, "market-avatar", 1230, 437, 284, 230)
    reset = group(root, "MarketResetCamera", (1525, 440, 43, 43), data_asset="MarketResetCamera")
    element(reset, "circle", cx=1546, cy=461, r=18, fill="#162b46", stroke="#3c6486", stroke_width=1.5)
    element(reset, "path", d="M1538 460a8 8 0 1 1 4 8M1535 454l3 7 7-3", fill="none", stroke="#b5e6ff", stroke_width=2.2, stroke_linecap="round", stroke_linejoin="round")
    text(root, "Worn now", 1174, 711, 21, WHITE, 700)
    element(root, "path", d="M1174 729H1574", stroke="#2d4b67", stroke_width=1.3)
    text(root, "No accessories equipped.", 1174, 761, 18, MUTED, data_native="WornItemsEmptyState")
    lines(root, ["Tap Try On to preview a design.", "Your saved items stay in My Items."], 1174, 800, 17, "#9cb9d6", gap=25)
    text(root, "Advanced filters, sorting & buying  ›", 1568, 883, 18, CYAN, 700, "end", data_native="AdvancedModeButton")
    return root


def avatar_lab_symbols(defs):
    market_symbols(defs)
    metal = element(defs, "linearGradient", id="avatar-lab-hat-metal", x1="0", y1="0", x2=".7", y2="1")
    for offset, color in [("0", "#8bdfff"), (".16", "#1b89cb"), (".43", "#0b376b"),
                          (".72", "#08284e"), ("1", "#03182c")]:
        element(metal, "stop", offset=offset, stop_color=color)
    halo_metal = element(defs, "linearGradient", id="avatar-lab-halo-metal", x1="0", y1="0", x2="0", y2="1")
    for offset, color in [("0", "#fffbdc"), (".23", "#fff7a4"), (".47", "#f8bf37"),
                          (".75", "#b96b0b"), ("1", "#ffdc72")]:
        element(halo_metal, "stop", offset=offset, stop_color=color)
    hat = element(defs, "symbol", id="avatar-lab-hat", viewBox="0 0 300 190")
    element(hat, "ellipse", cx=150, cy=164, rx=102, ry=9, fill="#061121", opacity=".65")
    element(hat, "path", d="M35 142Q42 118 150 116Q258 118 265 142V151Q254 173 150 172Q46 172 35 151Z",
            fill="url(#avatar-lab-hat-metal)", stroke="#459ec8", stroke_width=1.8)
    element(hat, "ellipse", cx=150, cy=141, rx=115, ry=28, fill="url(#avatar-lab-hat-metal)", stroke="#99eaff", stroke_width=2)
    element(hat, "path", d="M44 143Q59 163 151 165Q238 166 257 143", fill="none", stroke="#23bfff", stroke_width=2.3, opacity=".65")
    element(hat, "path", d="M87 137 91 41Q91 25 151 25Q212 25 212 41L216 137Q159 160 87 137Z",
            fill="url(#avatar-lab-hat-metal)", stroke="#71d6ff", stroke_width=2)
    element(hat, "path", d="M188 38 210 40 215 133Q204 139 189 141Z", fill="#032041", opacity=".75")
    element(hat, "path", d="M98 49Q107 46 116 49L113 112Q104 112 96 109Z", fill="#95ecff", opacity=".13")
    element(hat, "ellipse", cx=151, cy=40, rx=60, ry=15, fill="#14568b", stroke="#a1eaff", stroke_width=2)
    element(hat, "ellipse", cx=151, cy=39, rx=53, ry=10, fill="#0b305c", stroke="#377da7", stroke_width=1.3)
    element(hat, "path", d="M93 36Q148 15 207 36", fill="none", stroke="#d7f7ff", stroke_width=2.4, opacity=".65")
    element(hat, "path", d="M89 113Q155 135 215 112L216 136Q155 159 87 136Z",
            fill="url(#gold)", stroke="#ffe28a", stroke_width=1.5)
    element(hat, "path", d="M91 119Q158 141 212 120M90 134Q154 153 213 134", fill="none", stroke="#fff0b0", stroke_width=1.8, opacity=".7")
    element(hat, "path", d="m157 115 5 10 12 2-8 8 2 12-11-6-11 6 2-12-9-8 12-2Z",
            fill="url(#cyan-icon)", stroke="#dcffff", stroke_width=1.5, filter="url(#cyan-glow)")
    for x, y, r in [(75, 62, 4), (234, 70, 5), (61, 124, 3), (240, 127, 3)]:
        element(hat, "path", d=f"M{x-r} {y}H{x+r}M{x} {y-r}V{y+r}", stroke="#b6f6ff", stroke_width=1.5, stroke_linecap="round")
    halo = element(defs, "symbol", id="avatar-lab-halo", viewBox="0 0 300 190")
    element(halo, "ellipse", cx=150, cy=159, rx=94, ry=11, fill="#051224", opacity=".55")
    element(halo, "ellipse", cx=150, cy=88, rx=113, ry=34, fill="none", stroke="#ffd453", stroke_width=11,
            opacity=".21", filter="url(#gold-glow)")
    element(halo, "path", d="M36 86C36 58 87 41 150 41S264 58 264 86V100C264 129 213 146 150 146S36 129 36 100ZM61 86C61 103 101 115 150 115S239 103 239 86C239 68 199 57 150 57S61 68 61 86Z",
            fill="url(#avatar-lab-halo-metal)", fill_rule="evenodd", stroke="#ffdc75", stroke_width=1.4,
            filter="url(#small-shadow)")
    element(halo, "path", d="M36 86C36 57 87 40 150 40S264 57 264 86S213 132 150 132S36 114 36 86ZM60 86C60 104 100 115 150 115S240 104 240 86S200 57 150 57S60 68 60 86Z",
            fill="url(#avatar-lab-halo-metal)", fill_rule="evenodd", stroke="#fff4b3", stroke_width=1.5)
    element(halo, "path", d="M42 88C42 62 90 47 150 47S258 62 258 88", fill="none", stroke="#fffce4", stroke_width=2.7, opacity=".85")
    element(halo, "path", d="M42 108Q78 140 151 140Q222 140 257 108", fill="none", stroke="#ffec9a", stroke_width=2, opacity=".7")
    element(halo, "path", d="M64 83Q88 67 115 67M178 115Q211 113 235 94", fill="none", stroke="#ffedb0", stroke_width=1.7)
    for x, y, r in [(52, 41, 8), (246, 129, 8), (243, 46, 5), (92, 154, 4), (179, 26, 3)]:
        element(halo, "path", d=f"M{x-r} {y}Q{x} {y-2} {x} {y-r}Q{x+2} {y} {x+r} {y}Q{x} {y+2} {x} {y+r}Q{x-2} {y} {x-r} {y}Z",
                fill="#fff6c6", filter="url(#gold-glow)")


def avatar_lab():
    root, defs = screen("Avatar Lab — Style My Avatar", "Avatar Lab")
    avatar_lab_symbols(defs)
    title = group(root, "avatar-lab-heading")
    text(title, "Style My Avatar", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(title, "Try items for free. Buy only when you want to own one.", 80, 313, 21, MUTED)
    tabs = group(root, "AvatarLabTabs", (1138, 255, 473, 64), data_asset="AvatarLabTabs")
    rect(tabs, 1142, 259, 465, 52, "#101c31", 17, "#345173")
    rect(tabs, 1145, 262, 180, 46, "url(#blue-button)", 14, CYAN, filter="url(#small-shadow)")
    text(root, "Find items", 1235, 293, 20, WHITE, 700, "middle", data_native="BrowseTabButton")
    text(root, "My avatar", 1418, 293, 20, MUTED, 700, "middle", data_native="LookTabButton")
    text(root, "More", 1555, 293, 18, MUTED, 700, "middle", data_native="MoreTabsButton")
    element(tabs, "path", d="M1508 270V300", stroke="#324762", stroke_width=1.2)
    search = group(root, "AvatarLabSearchField", (72, 332, 862, 64), data_asset="AvatarLabSearchField")
    rect(search, 77, 337, 852, 54, "#0d1b32", 17, CYAN)
    element(search, "circle", cx=107, cy=362, r=9, fill="none", stroke="#87e9ff", stroke_width=2.5)
    element(search, "path", d="m114 369 7 7", stroke="#87e9ff", stroke_width=2.5, stroke_linecap="round")
    text(root, "Search hair, clothes, accessories…", 138, 372, 21, "#8ca4c3", data_native="SearchPlaceholder")
    button(root, "AvatarLabSearchButton", "Search", 951, 337, 167, 54, size=21)
    x = 77
    for name, w in [("Hair", 95), ("Hats", 95), ("Face", 95), ("Shirts", 112),
                    ("Pants", 105), ("Jackets", 121), ("Back", 100)]:
        selected = name == "Hats"
        chip = group(root, "AvatarLabCategory" + name, (x - 3, 408, w + 6, 48), data_asset="AvatarLabCategory" + name)
        rect(chip, x, 411, w, 42, "url(#blue-button)" if selected else "#14223a", 13,
             CYAN if selected else "#355171", filter="url(#small-shadow)" if selected else "none")
        text(root, name, x+w/2, 439, 18, WHITE if selected else MUTED, 700, "middle", data_native="CategoryButton")
        x += w + 12
    filters = group(root, "AvatarLabMoreFiltersButton", (892, 407, 230, 50), data_asset="AvatarLabMoreFiltersButton")
    rect(filters, 896, 411, 222, 42, "#14223a", 13, "#456887")
    for yy, sx in [(423, 913), (431, 922), (439, 916)]:
        element(filters, "path", d=f"M908 {yy}H932", stroke="#9acfe6", stroke_width=1.6, stroke_linecap="round")
        element(filters, "circle", cx=sx, cy=yy, r=2.6, fill="#b5ebff")
    text(root, "More filters", 1029, 439, 18, "#c4e5f7", 700, "middle", data_native="MoreFiltersButton")
    text(root, "3 items loaded · all free to try", 79, 486, 18, "#b9d7e9", 700, data_native="ResultsCountLabel")
    text(root, "Prices are for ownership", 1115, 486, 17, MUTED, anchor="end", data_native="OwnershipPriceNote")
    cards = [
        ("Void Crystal Crown", "market-crown", "R$ 95 to own · free to try"),
        ("Starlight Top Hat", "avatar-lab-hat", "R$ 75 to own · free to try"),
        ("Golden Halo", "avatar-lab-halo", "R$ 50 to own · free to try"),
    ]
    for i, (name, ref, price) in enumerate(cards):
        x, y, w, h = 77 + i * 354, 509, 333, 344
        prefix = f"AvatarLabCard{i+1}"
        panel(root, prefix + "Panel", x, y, w, h)
        well = group(root, prefix + "PreviewWell", (x + 12, y + 12, w - 24, 150), data_asset=prefix + "PreviewWell")
        rect(well, x + 16, y + 16, w - 32, 142, "#0c1b31", 16, "#306886")
        element(well, "ellipse", cx=x+w/2, cy=y+96, rx=117, ry=39, fill="url(#shop-aura)", opacity=".35")
        element(well, "ellipse", cx=x+w/2, cy=y+142, rx=101, ry=9, fill="#128cc7", opacity=".11")
        sample = group(root, prefix + "SampleModel", (x + 34, y + 19, w - 68, 136), data_role="ReplaceWithLiveItemThumbnail")
        icon(sample, ref, x + 34, y + 19, w - 68, 136)
        save = group(root, prefix + "SaveButton", (x+w-89, y+22, 64, 34), data_asset=prefix + "SaveButton")
        rect(save, x+w-85, y+26, 58, 28, "#12273e", 8, "#487c96")
        text(root, "Save", x+w-56, y+45, 13, "#bde7f5", 700, "middle", data_native="BookmarkButton")
        text(root, name, x+w/2, y+187, 21, WHITE, 700, "middle", data_native="ItemTitle")
        text(root, price, x+w/2, y+215, 17, MUTED, anchor="middle", data_native="OwnershipPriceLabel")
        button(root, prefix + "TryOnButton", "Try on · free", x+16, y+237, w-32, 50, size=23)
        element(root, "path", d=f"M{x+23} {y+303}H{x+w-23}", stroke="#2e536e", stroke_width=1.2)
        text(root, "Buy / view in Roblox  ↗", x+w/2, y+326, 17, "#b5d0e5", 700, "middle", data_native="BuyViewButton")
    panel(root, "AvatarLabPreviewPanel", 1142, 337, 465, 516)
    text(root, "Your Avatar", 1174, 384, 26, WHITE, 700)
    text(root, "Preview items on your look.", 1174, 413, 18, MUTED)
    well = group(root, "AvatarLabPreviewWell", (1164, 428, 421, 250), data_asset="AvatarLabPreviewWell")
    rect(well, 1168, 432, 413, 242, "#0a1a31", 18, "#2e6183")
    element(well, "ellipse", cx=1374, cy=652, rx=119, ry=13, fill="#0787ba", opacity=".21")
    element(well, "ellipse", cx=1374, cy=652, rx=141, ry=18, fill="none", stroke="#0b80ab", stroke_opacity=".3")
    avatar = group(root, "AvatarLabSampleAvatar", (1230, 437, 284, 230), data_role="ReplaceWithLiveAvatarViewport")
    icon(avatar, "market-avatar", 1230, 437, 284, 230)
    hint = group(root, "AvatarLabOrbitHint", (1177, 443, 109, 27), data_asset="AvatarLabOrbitHint")
    rect(hint, 1178, 444, 107, 25, "#172b44", 8, "#2a4965")
    text(root, "Drag to orbit", 1231, 461, 12, "#b3d9f6", 700, "middle", data_native="OrbitHint")
    reset = group(root, "AvatarLabResetCamera", (1525, 440, 43, 43), data_asset="AvatarLabResetCamera")
    element(reset, "circle", cx=1546, cy=461, r=18, fill="#162b46", stroke="#3c6486", stroke_width=1.5)
    element(reset, "path", d="M1538 460a8 8 0 1 1 4 8M1535 454l3 7 7-3", fill="none", stroke="#b5e6ff", stroke_width=2.2, stroke_linecap="round", stroke_linejoin="round")
    text(root, "Worn now", 1174, 711, 21, WHITE, 700)
    element(root, "path", d="M1174 729H1574", stroke="#2d4b67", stroke_width=1.3)
    text(root, "No accessories equipped.", 1174, 763, 18, MUTED, data_native="WornItemsEmptyState")
    lines(root, ["Try on an item to see it here.", "Open My avatar to save your outfit."], 1174, 804, 17, "#9cb9d6", gap=24)
    text(root, "✦  Try today's 90-second style challenge  ›", 79, 883, 18, "#edcf81", 700, data_native="StyleChallengeButton")
    text(root, "Load more items  ↓", 1116, 883, 18, CYAN, 700, "end", data_native="LoadMoreButton")
    return root


def graphics_symbols(defs):
    market_symbols(defs)
    headshot = element(defs, "symbol", id="graphics-avatar-headshot", viewBox="87 30 126 145")
    icon(headshot, "market-avatar", 0, 0, 300, 340)
    for name, colors in [("sunset", ["#412455", "#d47774", "#ffc47c"]),
                         ("city", ["#101735", "#2c265d", "#185788"])]:
        gradient = element(defs, "linearGradient", id="graphics-" + name, x1="0", y1="0", x2="0", y2="1")
        for offset, color in zip(["0", ".6", "1"], colors):
            element(gradient, "stop", offset=offset, stop_color=color)
    sunset = element(defs, "symbol", id="graphics-sunset-picture", viewBox="0 0 260 164")
    rect(sunset, 0, 0, 260, 164, "url(#graphics-sunset)", 0)
    element(sunset, "circle", cx=212, cy=44, r=35, fill="#ffd99a", opacity=".16")
    element(sunset, "circle", cx=212, cy=44, r=25, fill="#fff0bf", opacity=".9")
    for d in ["M25 1 113 164", "M68 1 151 164", "M207 3 57 164", "M246 4 94 164"]:
        element(sunset, "path", d=d, stroke="#ffe5b3", stroke_width=13, opacity=".055")
    element(sunset, "path", d="M-4 114 41 76 85 112 117 91 156 130 216 91 265 119V164H-4Z", fill="#794f69", opacity=".7")
    element(sunset, "path", d="M-4 146 49 108 94 129 123 114 166 139 216 111 265 132V164H-4Z", fill="#3e3151")
    element(sunset, "path", d="M-4 162 39 143 72 149 124 136 174 152 223 137 265 155V164H-4Z", fill="#1c2941")
    for x, y, w in [(10, 32, 50), (135, 70, 31), (184, 15, 28), (15, 69, 28)]:
        element(sunset, "path", d=f"M{x} {y}Q{x+w*.4} {y-7} {x+w} {y}", fill="none", stroke="#fcd5b9", stroke_width=2.2, opacity=".22")
    icon(sunset, "graphics-avatar-headshot", 61, 24, 143, 165)
    element(sunset, "path", d="M80 55Q92 44 102 41", fill="none", stroke="#fff0bd", stroke_width=2.7, opacity=".7", stroke_linecap="round")
    for x, y, r in [(35, 92, 2), (218, 111, 2.5), (225, 72, 1.5), (64, 38, 1.3)]:
        element(sunset, "circle", cx=x, cy=y, r=r, fill="#ffe3a1", opacity=".8")
    city = element(defs, "symbol", id="graphics-city-picture", viewBox="0 0 260 164")
    rect(city, 0, 0, 260, 164, "url(#graphics-city)", 0)
    element(city, "circle", cx=206, cy=28, r=19, fill="#a9e6ff", opacity=".12")
    element(city, "circle", cx=206, cy=28, r=11, fill="#c9eeff", opacity=".85")
    for x, y, w, color in [(0, 40, 30, "#123d5d"), (31, 21, 34, "#18294b"),
                           (69, 62, 22, "#0e2a4b"), (169, 49, 22, "#122e4e"),
                           (194, 60, 27, "#1c3359"), (225, 35, 37, "#132c4e")]:
        rect(city, x, y, w, 145-y, color, 2, "#3c527e")
        element(city, "path", d=f"M{x+3} {y+4}V134", stroke="#9c68ff", stroke_width=1.6, opacity=".6")
        for yy in range(y+10, 133, 13):
            for xx in range(x+9, x+w-4, 10):
                rect(city, xx, yy, 4, 5, "#4dccf2" if yy % 2 else "#ad7eff", 1, opacity=".55")
    element(city, "path", d="M0 139 121 113 260 138V164H0Z", fill="#071b32", stroke="#227cac", stroke_width=1)
    for xx in [0, 48, 100, 160, 211, 260]:
        element(city, "path", d=f"M130 118 {xx} 164", stroke="#126485", stroke_width=1, opacity=".5")
    for yy in [144, 155]:
        element(city, "path", d=f"M0 {yy}H260", stroke="#165780", stroke_width=1, opacity=".4")
    element(city, "ellipse", cx=130, cy=147, rx=49, ry=6, fill="#16b6ed", opacity=".25")
    icon(city, "market-avatar", 69, 8, 126, 143)
    for x, y in [(81, 22), (149, 12), (104, 37), (23, 14)]:
        element(city, "circle", cx=x, cy=y, r=1, fill="#b5eaff", opacity=".7")


def avatar_graphics():
    root, defs = screen("Avatar Graphics", "Avatar Graphics")
    graphics_symbols(defs)
    title = group(root, "avatar-graphics-heading")
    text(title, "Avatar Graphics", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(title, "Turn a prompt or your avatar into a picture you can keep.", 80, 313, 21, MUTED)
    tabs = group(root, "GraphicsTabs", (1267, 255, 344, 64), data_asset="GraphicsTabs")
    rect(tabs, 1271, 259, 336, 52, "#101c31", 17, "#345173")
    rect(tabs, 1274, 262, 160, 46, "url(#purple-button)", 14, PURPLE, filter="url(#small-shadow)")
    text(root, "Create", 1354, 293, 20, WHITE, 700, "middle", data_native="CreateTabButton")
    text(root, "Discover", 1520, 293, 20, MUTED, 700, "middle", data_native="DiscoverTabButton")
    panel(root, "GraphicsComposerPanel", 77, 337, 976, 516, "purple")
    text(root, "SOURCE", 104, 374, 16, "#d6b4ff", 700)
    button(root, "GraphicsAvatarSourceButton", "From My Avatar", 104, 389, 449, 48, theme="purple", size=22)
    button(root, "GraphicsTextSourceButton", "Text Prompt", 577, 389, 449, 48, theme="purple", size=22, quiet=True)
    text(root, "1 · CHOOSE YOUR AVATAR VIEW", 104, 472, 18, "#b8eeff", 700)
    for name, x, w in [("Headshot", 104, 178), ("Bust", 297, 154), ("Full body", 466, 178)]:
        selected = name == "Headshot"
        chip = group(root, "GraphicsView" + name.replace(" ", ""), (x-4, 481, w+8, 48), data_asset="GraphicsView" + name.replace(" ", ""))
        rect(chip, x, 485, w, 40, "url(#blue-button)" if selected else "#17243e", 13, CYAN if selected else "#42637f")
        element(chip, "path", d=f"m{x+20} 500 6 6-6 6-6-6Z", fill="#a2e8ff" if selected else "#507b9a")
        text(root, name, x+w/2+9, 512, 18, WHITE if selected else MUTED, 700, "middle", data_native="AvatarViewButton")
    well = group(root, "GraphicsSourceAvatarWell", (100, 537, 106, 90), data_asset="GraphicsSourceAvatarWell")
    rect(well, 104, 541, 98, 82, "#101b31", 15, "#776193")
    avatar = group(root, "GraphicsSampleSourceAvatar", (107, 544, 92, 76), data_role="ReplaceWithLiveAvatarThumbnail")
    icon(avatar, "graphics-avatar-headshot", 107, 544, 92, 76)
    lines(root, ["Fetched automatically from your current Roblox avatar.", "Ready to turn your look into art."], 222, 563, 20, "#c7d0e3", gap=27)
    text(root, "Simple Mode uses automatic style and default quality.", 222, 619, 16, MUTED, data_native="DefaultStyleQualityNote")
    text(root, "2 · DESCRIBE A SCENE OR THEME  (OPTIONAL)", 104, 654, 18, "#efb7ed", 700)
    prompt = group(root, "GraphicsPromptField", (100, 666, 930, 78), data_asset="GraphicsPromptField")
    rect(prompt, 104, 670, 922, 70, "#12182d", 17, "#a777d4")
    rect(prompt, 110, 676, 910, 58, "none", 12, "#edceff", stroke_opacity=".07")
    prompt_value = "a heroic portrait in golden sunset light"
    text(root, prompt_value, 124, 704, 22, WHITE, data_native="PromptTextBox")
    text(root, f"{len(prompt_value)} / 500", 1007, 727, 14, "#a39dbb", anchor="end", data_native="PromptCounter")
    text(root, "Your finished graphic is a picture you can keep.", 104, 765, 17, MUTED)
    button(root, "GraphicsAdvancedButton", "Advanced Mode: style & quality  ✦", 104, 782, 425, 46, theme="purple", size=19, quiet=True)
    button(root, "GraphicsCreateButton", "Create · R$ 29", 736, 777, 290, 54, theme="purple", size=24)
    text(root, "Creation starts after Roblox confirms your purchase.", 565, 847, 16, MUTED, anchor="middle", data_native="PurchaseConfirmationNote")
    panel(root, "GraphicsActivityPanel", 1078, 337, 529, 156)
    text(root, "In Progress", 1107, 377, 24, WHITE, 700)
    activity = group(root, "GraphicsActivityIcon", (1106, 398, 32, 32), data_asset="GraphicsActivityIcon")
    rect(activity, 1107, 399, 30, 30, "#123653", 10, "#3a98bd")
    rect(activity, 1113, 406, 18, 15, "none", 3, "#9eeaff")
    element(activity, "circle", cx=1126, cy=410, r=2, fill="#9eeaff")
    element(activity, "path", d="m1115 419 5-5 4 4 3-2 3 3", fill="none", stroke="#9eeaff", stroke_width=1.5)
    text(root, "Heroic golden light", 1151, 419, 20, WHITE, 700, data_native="GenerationTitle")
    text(root, "64%", 1578, 419, 21, CYAN, 700, "end", data_native="GenerationProgressLabel")
    progress = group(root, "GraphicsProgressTrack", (1147, 434, 435, 18), data_asset="GraphicsProgressTrack")
    rect(progress, 1151, 438, 427, 10, "#0c1830", 5, "#335878")
    rect(progress, 1153, 440, 271, 6, "url(#blue-button)", 3, data_native="GenerationProgressFill")
    text(root, "Painting your portrait…", 1151, 474, 17, MUTED, data_native="GenerationStageLabel")
    panel(root, "GraphicsGalleryPanel", 1078, 516, 529, 337, "gold")
    text(root, "Your Graphics", 1107, 558, 24, WHITE, 700)
    text(root, "2 saved", 1578, 557, 16, "#d7c6a4", anchor="end", data_native="GalleryCountLabel")
    for i, (name, ref, kind) in enumerate([
        ("Heroic golden light", "graphics-sunset-picture", "Headshot"),
        ("Neon city rooftop", "graphics-city-picture", "Full body"),
    ]):
        x, y, w = 1098+i*250, 574, 239
        prefix = f"GraphicsGalleryCard{i+1}"
        sample = group(root, prefix + "SamplePicture", (x, y, w, 132), data_role="ReplaceWithGraphicPreview")
        crop_id = prefix + "Clip"
        clip = element(defs, "clipPath", id=crop_id)
        rect(clip, x, y, w, 132, "#fff", 13)
        icon(sample, ref, x, y, w, 151, clip_path=f"url(#{crop_id})")
        well = group(root, prefix + "PreviewFrame", (x-3, y-3, w+6, 138), data_asset=prefix + "PreviewFrame")
        rect(well, x, y, w, 132, "none", 13, "#be9b57")
        text(root, name, x+w/2, y+155, 17, WHITE, 700, "middle", data_native="GraphicCaption")
        text(root, kind, x+w/2, y+177, 14, "#cebfa7", anchor="middle", data_native="GraphicKindLabel")
        text(root, "FULL-RES LINK · COPY INTO BROWSER", x+w/2, y+197, 10, "#b9b0a9", 700, "middle", data_native="DownloadLinkHint")
        link = group(root, prefix + "DownloadLinkField", (x-2, y+202, w+4, 30), data_asset=prefix + "DownloadLinkField")
        rect(link, x, y+204, w, 26, "#171e30", 8, "#605542")
        text(root, "https://…/image", x+11, y+222, 13, "#d4ddeb", data_native="DownloadLinkTextBox")
        delete = group(root, prefix + "DeleteButton", (x-2, y+238, w+4, 32), data_asset=prefix + "DeleteButton")
        rect(delete, x, y+240, w, 28, "#24232e", 10, "#695351")
        text(root, "Delete", x+w/2, y+259, 14, "#e8bec0", 700, "middle", data_native="DeleteGraphicButton")
    text(root, "Images stay in Your Graphics. Share & sell in Advanced Mode.", 1568, 883, 18, CYAN, 700, "end", data_native="AdvancedModeHint")
    return root


def play_symbols(defs):
    market_symbols(defs)
    controller = element(defs, "symbol", id="games-controller-art", viewBox="1130 390 477 245")
    controller.append(copy.deepcopy(REF_IDS["game-art"]))
    stage = element(defs, "symbol", id="games-runway-art", viewBox="0 0 400 244")
    element(stage, "path", d="M-15 0H415V244H-15Z", fill="#131d38")
    for x in [36, 118, 200, 282, 364]:
        element(stage, "path", d=f"M{x} 12 {x-73} 226 {x+73} 226Z", fill="#9758e2", opacity=".07")
        element(stage, "circle", cx=x, cy=16, r=5, fill="#d3adff", filter="url(#purple-glow)")
    element(stage, "path", d="M144 142H257L400 244H0Z", fill="#101a30", stroke="#8260c8", stroke_width=2)
    for yy in [158, 178, 205, 235]:
        element(stage, "path", d=f"M{144-(yy-142)*1.4} {yy}H{257+(yy-142)*1.4}", stroke="#8760d8", stroke_width=1.2, opacity=".5")
    element(stage, "ellipse", cx=202, cy=224, rx=83, ry=10, fill="#a55fff", opacity=".24")
    icon(stage, "market-avatar", 127, 7, 149, 210)
    icon(stage, "market-crown", 166, 12, 70, 56)
    for x, y in [(62, 65), (327, 99), (286, 38), (105, 147)]:
        element(stage, "path", d=f"M{x-5} {y} {x} {y-8} {x+5} {y} {x} {y+8}Z", fill="#e1b7ff", opacity=".8")
    lounge = element(defs, "symbol", id="games-lounge-art", viewBox="0 0 400 244")
    element(lounge, "ellipse", cx=205, cy=199, rx=172, ry=29, fill="#76501c", opacity=".18")
    element(lounge, "ellipse", cx=205, cy=199, rx=148, ry=20, fill="none", stroke="#e2b044", stroke_opacity=".25")
    rect(lounge, 85, 75, 230, 92, "url(#screen-gold)", 29, "#c89844", filter="url(#small-shadow)")
    rect(lounge, 90, 105, 220, 61, "#4c301b", 19, "#a87635")
    for x in [99, 171, 243]:
        rect(lounge, x, 107, 58, 51, "url(#gold)", 13, "#f7cb63")
    rect(lounge, 69, 99, 34, 79, "url(#screen-gold)", 15, "#d3a456")
    rect(lounge, 295, 99, 34, 79, "url(#screen-gold)", 15, "#d3a456")
    rect(lounge, 85, 170, 230, 14, "#8b622c", 7, "#dbac59")
    for x in [104, 279]:
        rect(lounge, x, 184, 18, 17, "#211e25", 5, "#776245")
    for x, y, r in [(42, 61, 19), (346, 100, 24), (257, 30, 17)]:
        element(lounge, "circle", cx=x, cy=y, r=r, fill="url(#coin)", stroke="#ffeb9a", stroke_width=2, filter="url(#gold-glow)")
        element(lounge, "circle", cx=x, cy=y, r=r*.72, fill="none", stroke="#b4771b", stroke_width=2)
        element(lounge, "path", d=f"M{x-r*.27} {y} {x} {y-r*.4} {x+r*.27} {y} {x} {y+r*.4}Z", fill="#f7d87a")
    for x, y in [(50, 169), (355, 42), (185, 30)]:
        element(lounge, "path", d=f"M{x-6} {y} {x} {y-9} {x+6} {y} {x} {y+9}Z", fill="#ffe6a8", filter="url(#gold-glow)")


def games():
    root, defs = screen("Games — Pick a way to play", "Games")
    play_symbols(defs)
    text(root, "Pick a way to play", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(root, "All three are free. Your creations keep building while you play.", 80, 313, 21, MUTED)
    badge = group(root, "GamesFreeBadge", (1372, 254, 235, 52), data_asset="GamesFreeBadge")
    rect(badge, 1376, 258, 231, 44, "#193b3b", 14, "#4ebcae")
    text(root, "FREE TO PLAY", 1491, 287, 19, "#a0f8e2", 700, "middle")
    cards = [
        ("Arcade", "11 quick mini-games", ["Play for weekly leaderboard prizes.", "A new personal best starts here."], "games-controller-art", "gold", "Open Arcade  ›"),
        ("Forge Runway", "Your look. Your spotlight.", ["Build a look, vote for other players,", "and compete in live style rounds."], "games-runway-art", "purple", "Open Runway  ›"),
        ("AFK Token Lounge", "Kick back. Keep earning.", ["Stay in the lounge for passive tokens.", "Rewarded ads are always optional."], "games-lounge-art", "blue", "Enter Lounge  ›"),
    ]
    for i, (title, caption, body, ref, theme, action) in enumerate(cards):
        x, y, w, h = 77 + i*517, 337, 496, 516
        prefix = f"GamesChoice{i+1}"
        panel(root, prefix + "Panel", x, y, w, h, theme)
        text(root, title, x+27, y+50, 29, WHITE, 700)
        text(root, caption, x+28, y+81, 20, {"gold": "#edcf81", "purple": "#d5b3ff", "blue": "#a0e5fa"}[theme], 700)
        well = group(root, prefix + "ArtworkWell", (x+20, y+101, w-40, 238), data_asset=prefix + "ArtworkWell")
        rect(well, x+24, y+105, w-48, 230, "#111e33", 19, "#546384")
        hero = group(root, prefix + "Artwork", (x+26, y+107, w-52, 226), data_asset=prefix + "Artwork")
        clip = element(defs, "clipPath", id=prefix + "ArtClip")
        rect(clip, x+25, y+106, w-50, 228, "#fff", 18)
        icon(hero, ref, x+25, y+106, w-50, 228, clip_path=f"url(#{prefix}ArtClip)")
        lines(root, body, x+28, y+374, 19, MUTED, gap=27)
        button(root, prefix + "OpenButton", action, x+25, y+432, w-50, 58, theme=theme, size=25)
    text(root, "Pick any activity. Your Forge jobs continue in the background.", 842, 883, 18, "#bcd6e9", anchor="middle")
    return root


def runway():
    root, defs = screen("Forge Runway", "Games")
    market_symbols(defs)
    text(root, "Forge Runway", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(root, "Tonight's theme · Neon Royalty", 80, 313, 21, MUTED, data_native="RoundThemeLabel")
    phase = group(root, "RunwayPhasePill", (1244, 254, 234, 51), data_asset="RunwayPhasePill")
    rect(phase, 1248, 258, 226, 43, "#10354b", 14, CYAN)
    text(root, "STYLING ROUND", 1361, 286, 18, "#b0f4ff", 700, "middle", data_native="PhaseLabel")
    timer = group(root, "RunwayTimerRing", (1501, 237, 96, 96), data_asset="RunwayTimerRing")
    element(timer, "circle", cx=1549, cy=285, r=43, fill="#132239", stroke="#474360", stroke_width=5)
    element(timer, "circle", cx=1549, cy=285, r=43, fill="none", stroke=GOLD, stroke_width=5, stroke_dasharray="200 271", transform="rotate(-90 1549 285)")
    text(root, "1:24", 1549, 286, 23, CYAN, 700, "middle", data_native="RoundTimerLabel")
    text(root, "LEFT", 1549, 306, 11, MUTED, 700, "middle")
    panel(root, "RunwayLineupPanel", 77, 337, 560, 516, "purple")
    text(root, "Runway Lineup", 105, 383, 26, WHITE, 700)
    text(root, "4 joined", 607, 380, 17, "#c9b0e9", 700, "end", data_native="LineupCountLabel")
    text(root, "Select a player to inspect their look.", 105, 414, 18, MUTED)
    for i, (name, locked) in enumerate([("You", False), ("nova", True), ("lumi", True), ("mossy", False)]):
        x, y, w = 102, 438+i*78, 509
        row = group(root, f"RunwayLineupRow{i+1}", (x-4, y-4, w+8, 76), data_asset=f"RunwayLineupRow{i+1}")
        rect(row, x, y, w, 68, "#2f2654" if i == 0 else "#17203b", 14, PURPLE if i == 0 else "#494664")
        rect(row, x+9, y+8, 51, 51, "#122a42", 11, "#4b617e")
        sample = group(root, f"RunwayLineupSampleAvatar{i+1}", (x+10, y+8, 49, 50), data_role="ReplaceWithLivePlayerThumbnail")
        icon(sample, "market-avatar", x+10, y+8, 49, 58)
        text(root, name, x+75, y+29, 22, WHITE, 700, data_native="EntrantName")
        text(root, "LOOK LOCKED" if locked else "STYLING", x+75, y+52, 13, "#8aecd4" if locked else MUTED, 700, data_native="EntrantStatus")
        button(root, f"RunwayLineupAction{i+1}", "Leave" if i == 0 else "View look", x+w-137, y+15, 122, 38, theme="purple", size=16, quiet=True)
    lines(root, ["Lock your look before the timer ends.", "Voting begins when styling is complete."], 105, 790, 18, "#baa9d6", gap=28)
    panel(root, "RunwayYourLookPanel", 659, 337, 518, 516)
    text(root, "Your Look", 687, 383, 26, WHITE, 700)
    well = group(root, "RunwayLookViewportWell", (681, 400, 474, 226), data_asset="RunwayLookViewportWell")
    rect(well, 685, 404, 466, 218, "#10203a", 18, "#3486ac")
    element(well, "path", d="M774 408 714 616H896L907 408ZM960 408 958 616H1126L1055 408Z", fill="#347aaf", opacity=".08")
    element(well, "ellipse", cx=918, cy=607, rx=109, ry=11, fill="#079cda", opacity=".24")
    model = group(root, "RunwaySampleLook", (814, 410, 205, 200), data_role="ReplaceWithLiveAvatarViewport")
    icon(model, "market-avatar", 814, 410, 205, 200)
    icon(model, "market-crown", 885, 410, 65, 49)
    text(root, "Drag to orbit", 703, 432, 13, "#a8d7f1", 700, data_native="OrbitHint")
    reset = group(root, "RunwayResetCameraButton", (1106, 410, 35, 34), data_asset="RunwayResetCameraButton")
    element(reset, "circle", cx=1123, cy=427, r=15, fill="#172c47", stroke="#548cb1", stroke_width=1.5)
    text(root, "↺", 1123, 435, 23, "#bcecff", 700, "middle", data_native="ResetCameraButton")
    text(root, "LEVEL 3", 687, 650, 14, GOLD, 700, data_native="CreatorLevelLabel")
    text(root, "Forge Apprentice", 770, 650, 20, WHITE, 700, data_native="CreatorTitleLabel")
    progress = group(root, "RunwayXPTrack", (681, 659, 474, 14), data_asset="RunwayXPTrack")
    rect(progress, 685, 663, 466, 6, "#111b2e", 3)
    rect(progress, 685, 663, 183, 6, "url(#gold)", 3, data_native="XPFill")
    text(root, "240 XP · 4 rounds · 1 win · 3 votes cast", 687, 692, 16, MUTED, data_native="CreatorStatsLabel")
    text(root, "DAILY ENCORE · 1/2 ROUNDS", 687, 719, 15, "#eccb80", 700, data_native="DailyEncoreLabel")
    button(root, "RunwayLockLookButton", "Lock in my look  ›", 685, 737, 466, 51, size=25)
    button(root, "RunwayAvatarLabButton", "Open Avatar Lab", 685, 803, 226, 32, size=16, quiet=True)
    button(root, "RunwayInviteButton", "Invite friend", 925, 803, 226, 32, size=16, quiet=True)
    panel(root, "RunwayWeeklyPanel", 1199, 337, 408, 516, "gold")
    text(root, "Weekly Spotlight", 1226, 383, 25, WHITE, 700)
    text(root, "Points earned in live style rounds", 1226, 412, 16, "#cfbb9b")
    for i, (name, score) in enumerate([("nova", "1,280"), ("lumi", "960"), ("You", "740"), ("mossy", "650"), ("sage", "420")]):
        x, y = 1223, 439+i*65
        row = group(root, f"RunwayWeeklyRow{i+1}", (x-3, y-3, 361, 61), data_asset=f"RunwayWeeklyRow{i+1}")
        rect(row, x, y, 357, 55, "#303142" if i == 2 else "#252538", 12, "#b59964" if i == 2 else "#5c5144")
        element(row, "circle", cx=x+27, cy=y+27, r=16, fill="url(#gold)" if i == 0 else "#4c4555", stroke="#c5a364", stroke_width=1)
        text(root, str(i+1), x+27, y+33, 17, "#2c210d" if i == 0 else "#e3cf9d", 700, "middle")
        text(root, name, x+58, y+34, 21, WHITE, 700, data_native="WeeklyPlayerLabel")
        text(root, score + " pts", x+342, y+33, 17, "#e5c986", 700, "end", data_native="WeeklyPointsLabel")
    text(root, "Your week · 740 pts · #3", 1226, 801, 17, "#a9e8ff", 700, data_native="OwnWeeklyRankLabel")
    text(root, "Refresh  ↻", 1577, 830, 16, "#e7c786", 700, "end", data_native="RefreshLeaderboardButton")
    text(root, "Avatar Lab, Market and your own Forge items all count toward your look.", 842, 883, 18, MUTED, anchor="middle")
    return root


def arcade_symbols(defs):
    for name in ["bird", "dino", "color", "snake", "stack", "bricks", "target", "prism", "rocket", "cloud", "echo", "trophy"]:
        sym = element(defs, "symbol", id="arcade-icon-" + name, viewBox="0 0 64 64")
        color = PURPLE if name in ["snake", "color", "prism"] else GOLD if name in ["bricks", "echo", "trophy"] else CYAN
        fill = "url(#purple-icon)" if color == PURPLE else "url(#gold)" if color == GOLD else "url(#cyan-icon)"
        if name == "bird":
            element(sym, "path", d="M48 30 59 35 48 40Q48 52 33 54Q13 52 12 36Q13 19 32 18Q48 18 48 30Z", fill=fill, stroke="#bdffff", stroke_width=2)
            element(sym, "path", d="M32 38Q12 23 6 35Q11 50 30 48Z", fill="#0c648d", stroke="#72eaff", stroke_width=2)
            element(sym, "circle", cx=40, cy=29, r=4, fill="#efffff")
            element(sym, "circle", cx=41, cy=29, r=2, fill="#123347")
        elif name == "dino":
            element(sym, "path", d="M10 52V31L18 43 29 38V12H56V29H43V34H50V41H40V54H33V45H22V54Z", fill=fill, stroke="#bdffff", stroke_width=2)
            element(sym, "circle", cx=46, cy=18, r=2, fill="#193953")
            element(sym, "path", d="M43 27H54M28 52H35", stroke="#e0ffff", stroke_width=2)
        elif name == "color":
            for d, c in [("M32 9A23 23 0 0 1 55 32", "#ec70a8"), ("M55 32A23 23 0 0 1 32 55", "#ffd052"), ("M32 55A23 23 0 0 1 9 32", "#62e2ff"), ("M9 32A23 23 0 0 1 32 9", "#bd79ff")]:
                element(sym, "path", d=d, fill="none", stroke=c, stroke_width=9)
            element(sym, "circle", cx=32, cy=32, r=6, fill="#fff", filter="url(#small-shadow)")
        elif name == "snake":
            element(sym, "path", d="M12 51H42Q51 51 51 42Q51 33 42 33H23Q13 33 13 23Q13 13 25 13H43", fill="none", stroke="#8d3fd0", stroke_width=14, stroke_linecap="round")
            element(sym, "path", d="M12 48H41Q48 48 48 41Q48 35 41 35H23Q14 35 14 23Q14 15 25 15H42", fill="none", stroke="#bd83ff", stroke_width=10, stroke_linecap="round")
            element(sym, "ellipse", cx=47, cy=15, rx=12, ry=9, fill=fill, stroke="#eed1ff", stroke_width=1.5)
            element(sym, "circle", cx=51, cy=12, r=2, fill="#fff")
        elif name == "stack":
            for x, y, w in [(8, 44, 48), (13, 29, 43), (9, 14, 35)]:
                rect(sym, x, y, w, 12, fill, 3, "#d0ffff")
                element(sym, "path", d=f"M{x+3} {y+3}H{x+w-3}", stroke="#fff", stroke_opacity=".6", stroke_width=1)
        elif name == "bricks":
            for yy in [8, 21]:
                for xx in [5, 24, 43]:
                    rect(sym, xx, yy, 16, 10, fill, 2, "#fff0bd")
            rect(sym, 16, 52, 33, 6, fill, 3, "#fff0bd")
            element(sym, "circle", cx=36, cy=42, r=5, fill="#fff5bc", filter="url(#gold-glow)")
            element(sym, "path", d="M35 44 29 48", stroke="#d2a348", stroke_width=2)
        elif name == "target":
            for r in [25, 16, 7]:
                element(sym, "circle", cx=30, cy=33, r=r, fill="none", stroke=color, stroke_width=4)
            element(sym, "path", d="M28 35 54 9M43 10l11-1-1 11", fill="none", stroke="#b9ffff", stroke_width=3, stroke_linecap="round")
        elif name == "prism":
            element(sym, "path", d="M32 6 57 26 41 56H23L7 26Z", fill=fill, stroke="#edc9ff", stroke_width=2)
            element(sym, "path", d="M7 26H57M32 6 22 26 32 56 42 26Z", fill="none", stroke="#e3adff", stroke_width=1.5)
            element(sym, "path", d="M12 25 23 15", stroke="#fff", stroke_width=2, opacity=".7")
        elif name == "rocket":
            element(sym, "path", d="M21 34Q24 11 48 7Q57 32 36 45Z", fill=fill, stroke="#cfffff", stroke_width=2)
            element(sym, "path", d="M23 28 10 31 8 49 24 43M41 38 43 54 56 46 51 32", fill="#145680", stroke="#a1e9ff", stroke_width=2)
            element(sym, "circle", cx=40, cy=23, r=6, fill="#122a47", stroke="#e6ffff", stroke_width=2)
            element(sym, "path", d="M24 44 13 57 29 48", fill="#ffcc4c", stroke="#fff0a6", stroke_width=2)
        elif name == "cloud":
            element(sym, "path", d="M12 44Q1 40 7 29Q10 24 18 25Q18 9 34 11Q48 11 49 27Q61 26 61 36Q61 45 51 46H12Z", fill=fill, stroke="#d7ffff", stroke_width=2)
            element(sym, "path", d="M22 55 22 51M34 57V50M46 55V51", stroke="#baf8ff", stroke_width=3, stroke_linecap="round")
        elif name == "echo":
            element(sym, "path", d="M12 46Q20 40 20 27Q20 14 32 14Q44 14 44 27Q44 40 52 46Z", fill=fill, stroke="#ffefb8", stroke_width=2)
            element(sym, "path", d="M27 51Q32 58 37 51M29 10Q32 5 35 10", fill="none", stroke="#ffe6a3", stroke_width=3, stroke_linecap="round")
            element(sym, "path", d="M9 20Q4 28 8 36M55 20Q60 28 56 36", fill="none", stroke="#e5b854", stroke_width=2)
        else:
            element(sym, "path", d="M18 10H46V24Q45 39 32 40Q19 39 18 24Z", fill=fill, stroke="#fff2b7", stroke_width=2)
            element(sym, "path", d="M18 14H8Q6 32 22 31M46 14H56Q58 32 42 31M32 40V51M21 55H43", fill="none", stroke="#ffd878", stroke_width=4, stroke_linecap="round")


def arcade():
    root, defs = screen("Arcade", "Games")
    arcade_symbols(defs)
    text(root, "Arcade", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(root, "11 free games · weekly prizes · scores save", 80, 313, 21, MUTED)
    rewards = group(root, "ArcadeWeeklyPrizeBanner", (73, 333, 1538, 57), data_asset="ArcadeWeeklyPrizeBanner")
    rect(rewards, 77, 337, 1530, 49, "url(#screen-gold)", 16, GOLD)
    icon(rewards, "star-icon", 97, 348, 27)
    text(root, "WEEKLY TOP 3 · EVERY GAME", 140, 369, 20, "#ffde8b", 700)
    text(root, "150 · 83 · 33 tokens   |   Resets every Monday", 1578, 368, 19, "#edcf96", 700, "end")
    options = [
        ("Flappy Bird", "Flap through the gap.", "bird", "blue"),
        ("Dino Runner", "Jump the cacti.", "dino", "blue"),
        ("Color Switch", "Find the right color.", "color", "purple"),
        ("Neon Snake", "Grow without biting yourself.", "snake", "purple"),
        ("Block Stacker", "Stack it straight, don't miss.", "stack", "blue"),
        ("Brick Breaker", "Clear the bricks.", "bricks", "gold"),
        ("Reflex Tap", "Tap the lit tile.", "target", "blue"),
        ("Prism Merge", "Merge prisms. Chain combos.", "prism", "purple"),
        ("Meteor Rush", "Dodge meteors. Collect cores.", "rocket", "blue"),
        ("Sky Hopper", "Bounce ever higher.", "cloud", "blue"),
        ("Echo Match", "Watch. Remember. Repeat.", "echo", "gold"),
        ("Leaderboards", "Global and friends standings.", "trophy", "gold"),
    ]
    for i, (name, blurb, ref, theme) in enumerate(options):
        x, y, w, h = 77+(i%4)*388, 406+(i//4)*154, 366, 139
        prefix = f"ArcadeGame{i+1}"
        panel(root, prefix + "Panel", x, y, w, h, theme)
        artwork = group(root, prefix + "Icon", (x+13, y+14, 75, 75), data_asset=prefix + "Icon")
        rect(artwork, x+16, y+17, 69, 69, "#14223a", 17, "#4c6181")
        icon(artwork, "arcade-icon-" + ref, x+23, y+24, 55)
        text(root, name, x+101, y+39, 21, WHITE, 700, data_native="GameTitleLabel")
        text(root, blurb, x+101, y+65, 13, MUTED, data_native="GameDescriptionLabel")
        text(root, "YOUR BEST" if i != 11 else "YOUR BEST RANK", x+19, y+105, 11, "#9db4d0", 700)
        text(root, "—", x+(170 if i == 11 else 111), y+107, 20, "#e1eeff", 700, data_native="PersonalBestLabel")
        button(root, prefix + "PlayButton", "Play  ›" if i != 11 else "View ranks  ›", x+189, y+94, 158, 30, theme=theme, size=17)
    text(root, "Clear today's challenge for +5 bonus tokens. Each game's target appears on its tile.", 79, 883, 18, MUTED, data_native="DailyChallengeHint")
    return root


def settings_switch(parent, name, x, y, on):
    art = group(parent, name, (x-3, y-3, 77, 38), data_asset=name)
    rect(art, x, y, 71, 32, "#205069" if on else "#18263f", 16, CYAN if on else "#51617c")
    element(art, "circle", cx=x+(54 if on else 17), cy=y+16, r=11, fill="url(#cyan-icon)" if on else "#7686a2", stroke="#bdedff" if on else "#9ca9c0", stroke_width=1)
    return art


def settings():
    root, defs = screen("Settings", "Settings")
    market_symbols(defs)
    text(root, "Settings", 79, 284, 39, WHITE, 900, filter="url(#text-shadow)")
    text(root, "Make Forge feel right for you.", 80, 313, 21, MUTED)
    badge = group(root, "SettingsSavedBadge", (1324, 253, 287, 53), data_asset="SettingsSavedBadge")
    rect(badge, 1328, 257, 279, 45, "#1a373e", 14, "#4daca8")
    text(root, "Changes save automatically", 1467, 286, 18, "#a4eddf", 700, "middle")
    panel(root, "SettingsCreateModePanel", 77, 337, 753, 143)
    text(root, "Create Mode", 105, 379, 25, WHITE, 700)
    text(root, "A simple prompt, or the full creative toolkit.", 105, 410, 18, MUTED)
    button(root, "SettingsSimpleModeButton", "Simple Mode · ON", 105, 430, 333, 33, size=18)
    button(root, "SettingsAdvancedModeButton", "Advanced Mode", 465, 430, 337, 33, size=18, quiet=True)
    panel(root, "SettingsAccessibilityPanel", 77, 500, 753, 235, "purple")
    text(root, "Accessibility", 105, 539, 25, WHITE, 700)
    text(root, "Reduce motion", 105, 576, 20, WHITE, 700)
    text(root, "Turn off pulses, drifting embers and sweeps.", 105, 600, 16, MUTED)
    settings_switch(root, "SettingsReduceMotionSwitch", 730, 566, False)
    text(root, "High contrast", 105, 633, 20, WHITE, 700)
    text(root, "Darker panels, brighter text and borders.", 105, 657, 16, MUTED)
    settings_switch(root, "SettingsHighContrastSwitch", 730, 623, False)
    text(root, "Interface size", 105, 697, 20, WHITE, 700)
    text(root, "100%", 795, 697, 18, "#d1b8ef", 700, "end", data_native="UIScaleValueLabel")
    slider = group(root, "SettingsUIScaleTrack", (302, 682, 415, 24), data_asset="SettingsUIScaleTrack")
    rect(slider, 306, 690, 406, 7, "#151e34", 4, "#69558c")
    rect(slider, 306, 690, 136, 7, "url(#purple-button)", 4, data_native="UIScaleFill")
    element(slider, "circle", cx=442, cy=693, r=9, fill="#ddc1ff", stroke="#a76cf3", stroke_width=2, data_native="UIScaleKnob")
    text(root, "Tab or gamepad Y opens navigation. Use arrows or the D-pad to move.", 105, 723, 14, MUTED)
    panel(root, "SettingsAudioPanel", 77, 755, 753, 98, "gold")
    text(root, "Sound effects", 105, 794, 22, WHITE, 700)
    text(root, "Taps, forge chimes and reward stings.", 105, 822, 18, MUTED)
    settings_switch(root, "SettingsSoundSwitch", 730, 785, True)
    panel(root, "SettingsEquippedPanel", 852, 337, 755, 143)
    text(root, "Equipped Now", 880, 379, 25, WHITE, 700)
    text(root, "1 item", 1576, 377, 17, "#9bccdf", 700, "end", data_native="EquippedCountLabel")
    row = group(root, "SettingsEquippedRow", (876, 394, 707, 66), data_asset="SettingsEquippedRow")
    rect(row, 880, 398, 699, 58, "#10213b", 13, "#355b7c")
    sample = group(root, "SettingsSampleEquippedItem", (888, 403, 60, 48), data_role="ReplaceWithLiveItemThumbnail")
    icon(sample, "market-crown", 888, 403, 60, 48)
    text(root, "Void Crystal Crown", 963, 424, 22, WHITE, 700, data_native="EquippedItemNameLabel")
    text(root, "Hat accessory", 963, 446, 14, MUTED, data_native="EquippedItemTypeLabel")
    button(root, "SettingsRemoveItemButton", "Remove", 1438, 409, 123, 35, size=17, quiet=True)
    panel(root, "SettingsAchievementsPanel", 852, 500, 755, 235, "gold")
    text(root, "Achievements", 880, 540, 25, WHITE, 700)
    text(root, "4 / 14 unlocked", 1577, 538, 16, "#ddc897", 700, "end", data_native="AchievementCountLabel")
    for i, (name, description, reward, on) in enumerate([
        ("First Spark", ["Complete your", "first accessory."], 5, True),
        ("Suit Up", ["Equip a generated", "item on your avatar."], 3, True),
        ("Dialed In", ["Save your first", "fit preset."], 3, True),
        ("Prolific", ["Complete five", "accessories."], 10, False),
    ]):
        x = 960+i*178
        medal = group(root, f"SettingsAchievementMedal{i+1}", (x-34, 554, 68, 70), data_asset=f"SettingsAchievementMedal{i+1}")
        element(medal, "circle", cx=x, cy=589, r=29, fill="#24223c", stroke=GOLD if on else "#8b759e", stroke_width=2, stroke_dasharray="none" if on else "4 4")
        element(medal, "circle", cx=x, cy=589, r=23, fill="none", stroke="#bdad8c" if on else "#736584", stroke_width=1, opacity=".45")
        if on:
            element(medal, "path", d=f"M{x-13} 589 {x-5} 584 {x} 571 {x+5} 584 {x+13} 589 {x+5} 594 {x} 607 {x-5} 594Z", fill=[CYAN, PURPLE, GOLD][i], filter="url(#small-shadow)")
        else:
            rect(medal, x-9, 586, 18, 15, "#9e8bb4", 4)
            element(medal, "path", d=f"M{x-6} 586V581A6 6 0 0 1 {x+6} 581V586", fill="none", stroke="#9e8bb4", stroke_width=3)
        text(root, name, x, 637, 17, "#e5d3aa" if on else "#ad9ac1", 700, "middle", data_native="AchievementNameLabel")
        for j, value in enumerate(description):
            text(root, value, x, 661+j*21, 14, MUTED, anchor="middle", data_native="AchievementDescriptionLabel")
        text(root, "+" + str(reward) + " tokens", x, 709, 15, "#d3b876", 700, "middle", data_native="AchievementRewardLabel")
    panel(root, "SettingsCommunityPanel", 852, 755, 755, 98, "purple")
    text(root, "Create with friends", 880, 788, 22, WHITE, 700)
    text(root, "Invite a friend or join the creator community.", 880, 816, 17, MUTED)
    button(root, "SettingsInviteFriendButton", "Invite a friend", 1296, 772, 283, 29, theme="purple", size=16)
    button(root, "SettingsJoinGroupButton", "Join group · +1 queue slot", 1296, 811, 283, 29, theme="purple", size=16, quiet=True)
    text(root, "Scroll for every achievement and full creator group benefits.", 1559, 883, 18, CYAN, 700, "end", data_native="SettingsScrollHint")
    return root


DESIGNS = {"create": create, "my-items": my_items, "market": market,
           "avatar-lab": avatar_lab, "avatar-graphics": avatar_graphics,
           "games": games, "arcade": arcade, "runway": runway, "settings": settings}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=list(DESIGNS))
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name in [args.only] if args.only else DESIGNS:
        root = DESIGNS[name]()
        ids = [node.get("id") for node in root.iter() if node.get("id")]
        assert len(ids) == len(set(ids)), f"Duplicate SVG IDs in {name}"
        ET.indent(root, space="  ")
        ET.ElementTree(root).write(OUT / f"{name}.svg", encoding="utf-8", xml_declaration=True)
        print(f"Created {OUT / (name + '.svg')}")


if __name__ == "__main__":
    main()
