#!/usr/bin/env python3
"""Render each concept SVG to PNG (1x and 2x) with headless Chromium."""
import pathlib, subprocess, sys
from PIL import Image

HERE = pathlib.Path(__file__).parent
CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

def render(svg, scale=1):
    html = HERE / "_r.html"
    html.write_text('<!doctype html><meta charset="utf-8">'
                    '<style>html,body{margin:0;background:#000}img{display:block;width:1920px;height:1080px}</style>'
                    f'<img src="{svg.name}">')
    out = HERE / f"_raw{scale}.png"
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
                    f"--force-device-scale-factor={scale}", "--window-size=1920,1168",
                    f"--screenshot={out}", f"file://{html}"],
                   capture_output=True)
    png = svg.with_suffix("").with_name(svg.stem + ("@2x" if scale == 2 else "")).with_suffix(".png")
    Image.open(out).convert("RGB").crop((0, 0, 1920*scale, 1080*scale)).save(png)
    out.unlink(); html.unlink(missing_ok=True)
    return png

targets = sys.argv[1:] or [p.name for p in sorted(HERE.glob("forge-*.svg"))]
for name in targets:
    svg = HERE / name
    for s in (1, 2):
        print("rendered", render(svg, s).name)
