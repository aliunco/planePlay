#!/usr/bin/env python3
"""Generates the animated sprite sheets the game uses.

Everything here is drawn from parametric SVG. The sheets are written as SVG so
that Godot rasterises them itself at import time (crisp at any resolution) and
so the art stays editable text:

    python3 tools/build_art.py

Layout of every sheet is a horizontal strip. Frame sizes live next to the code
that slices them, see scripts/airplane/airplane.gd,
scripts/environment/cloud_controller.gd and scripts/effects/explosion.gd.

The airplanes and the infantry are NOT generated here: they are low-poly 3D
models rendered at runtime (see scripts/airplane/plane_model_3d.gd and
scripts/environment/soldier_model_3d.gd). Only the 2D muzzle flash is drawn by
this script.
"""

import math
import os


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def write_svg(path: str, width: int, height: int, defs: str, frames: list[str], frame_w: int) -> None:
    placed = []
    for index, body in enumerate(frames):
        placed.append(f'  <g transform="translate({index * frame_w}, 0)">\n{body}\n  </g>')
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">\n'
        f"  <defs>\n{defs}\n  </defs>\n" + "\n".join(placed) + "\n</svg>\n"
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(svg)
    print(f"wrote {os.path.relpath(path, ROOT)} ({len(frames)} frames of {frame_w}px)")


# --- Clouds ------------------------------------------------------------------

CLOUD_W = 320
CLOUD_H = 200
CLOUD_FRAMES = 6

CLOUD_DEFS = """    <linearGradient id="puff" gradientUnits="userSpaceOnUse" x1="0" y1="34" x2="0" y2="166">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="0.58" stop-color="#fcfdff"/>
      <stop offset="1" stop-color="#e3eefb"/>
    </linearGradient>
"""


def cloud_body(phase: float) -> str:
    """One soft cumulus: a rounded base with lobes breathing along the top, so a
    looping cycle reads as a slow churn instead of a sliding picture."""
    turn = phase * math.tau
    shapes = ['<rect x="58" y="104" width="204" height="50" rx="25"/>']

    # The lobes have to overlap the base slab generously: if their bottoms only
    # meet its top edge, the antialiased seam between the two shapes shows up as
    # a transparent slit across the cloud.
    lobes = 6
    for i in range(lobes):
        along = i / (lobes - 1.0)
        rise = math.sin(along * math.pi) ** 0.9
        radius = 24.0 + 20.0 * rise + 4.5 * math.sin(i * 2.1 + 0.6) + 3.0 * math.sin(turn + i * 1.55)
        cx = 76.0 + along * 168.0 + 7.0 * math.sin(turn * 0.75 + i * 0.8)
        cy = 114.0 - 18.0 * rise - 5.0 * math.sin(i * 1.7) - 3.0 * math.sin(turn + i * 1.2)
        shapes.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{radius:.1f}"/>')

    body = "\n".join(f"    {shape}" for shape in shapes)
    return (
        f'    <g fill="url(#puff)">\n{body}\n    </g>'
    )


# --- Fireball ----------------------------------------------------------------

FIRE_W = 200
FIRE_H = 200
FIRE_FRAMES = 10

FIRE_DEFS = """    <radialGradient id="flame">
      <stop offset="0" stop-color="#ffc34a" stop-opacity="0.98"/>
      <stop offset="0.3" stop-color="#ff9a24" stop-opacity="0.95"/>
      <stop offset="0.62" stop-color="#f2600f" stop-opacity="0.82"/>
      <stop offset="0.86" stop-color="#c2360a" stop-opacity="0.42"/>
      <stop offset="1" stop-color="#8f2506" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="hot">
      <stop offset="0" stop-color="#ffffff" stop-opacity="1"/>
      <stop offset="0.5" stop-color="#fff0a8" stop-opacity="0.95"/>
      <stop offset="1" stop-color="#ffbe3c" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="smoke">
      <stop offset="0" stop-color="#c9c6c2" stop-opacity="0.95"/>
      <stop offset="0.55" stop-color="#9d9a97" stop-opacity="0.6"/>
      <stop offset="1" stop-color="#6f6d6b" stop-opacity="0"/>
    </radialGradient>"""


def fireball_body(step: int) -> str:
    total = FIRE_FRAMES - 1.0
    t = step / total
    cx = FIRE_W * 0.5
    cy = FIRE_H * 0.5

    if t <= 0.6:
        grow = 0.35 + 0.65 * smoothstep(0.0, 1.0, t / 0.7)
        core_r = 16.0 + 62.0 * grow
        lobes = []
        for k in range(5):
            angle = k * (math.tau / 5.0) + 0.4 * math.sin(t * 9.0 + k)
            reach = core_r * (0.26 + 0.26 * math.sin(k * 2.3 + t * 7.0))
            radius = core_r * (0.60 + 0.34 * math.sin(k * 1.7 + t * 5.0))
            lx = cx + math.cos(angle) * reach
            ly = cy + math.sin(angle) * reach * 0.92
            lobes.append(f'      <circle cx="{lx:.1f}" cy="{ly:.1f}" r="{radius:.1f}"/>')
        body = "\n".join(lobes)
        # A single hot core keeps the white centre in one place instead of every
        # lobe glowing on its own (which reads as rings, not fire).
        core_fade = 1.0 - smoothstep(0.48, 0.62, t) * 0.55
        return (
            '    <g fill="url(#flame)" opacity="0.92">\n' + body + "\n    </g>\n"
            f'    <circle cx="{cx:.1f}" cy="{cy:.1f}" r="{core_r * 0.66:.1f}" '
            f'fill="url(#hot)" opacity="{0.95 * core_fade:.2f}"/>'
        )

    smoke_t = (t - 0.6) / 0.4
    spread = 0.85 + 0.55 * smoke_t
    fade = (1.0 - smoothstep(0.5, 1.0, smoke_t)) * 0.95
    puffs = []
    for k in range(6):
        angle = k * (math.tau / 6.0) + 0.5
        px = cx + math.cos(angle) * 40.0 * spread
        py = cy + math.sin(angle) * 30.0 * spread - 26.0 * smoke_t
        radius = (30.0 + 14.0 * math.sin(k * 1.9) + 10.0 * smoke_t) * spread
        puffs.append(f'      <circle cx="{px:.1f}" cy="{py:.1f}" r="{radius:.1f}"/>')
    body = "\n".join(puffs)
    return f'    <g fill="url(#smoke)" opacity="{fade:.2f}">\n{body}\n    </g>'

# --- Muzzle flash ------------------------------------------------------------
#
# A single 2D texture that pops at the nose when the guns fire. The propeller
# lives inside the 3D model now, so it is not generated here.


def muzzle_svg() -> str:
    return """<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 72 72">
  <defs>
    <radialGradient id="glow">
      <stop offset="0" stop-color="#fffdf0" stop-opacity="1"/>
      <stop offset="0.45" stop-color="#ffd75a" stop-opacity="0.85"/>
      <stop offset="1" stop-color="#ff9a24" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <circle cx="36" cy="36" r="34" fill="url(#glow)"/>
  <path d="M36 35 L54 30 L38 36 L54 42 Z" fill="#fff6c0"/>
  <path d="M36 37 L18 42 L34 36 L18 30 Z" fill="#ffe08a"/>
  <circle cx="36" cy="36" r="7" fill="#ffffff" fill-opacity="0.9"/>
</svg>
"""


def write_texture(name: str, text: str) -> None:
    path = os.path.join(ASSETS, name)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print(f"wrote {os.path.relpath(path, ROOT)}")


def main() -> None:
    write_svg(
        os.path.join(ASSETS, "environment", "cloud_sheet.svg"),
        CLOUD_W * CLOUD_FRAMES,
        CLOUD_H,
        CLOUD_DEFS,
        [cloud_body(i / CLOUD_FRAMES) for i in range(CLOUD_FRAMES)],
        CLOUD_W,
    )

    write_texture(os.path.join("effects", "muzzle.svg"), muzzle_svg())

    write_svg(
        os.path.join(ASSETS, "effects", "fireball_sheet.svg"),
        FIRE_W * FIRE_FRAMES,
        FIRE_H,
        FIRE_DEFS,
        [fireball_body(i) for i in range(FIRE_FRAMES)],
        FIRE_W,
    )



if __name__ == "__main__":
    main()
