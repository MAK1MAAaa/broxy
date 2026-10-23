#!/usr/bin/env python3
"""Generate the project's original, redistributable vector art and synthesized audio.

Standard library only. All assets are authored here; no external images or samples.
"""
from __future__ import annotations

import json
import math
import random
import struct
import wave
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
MANIFEST: list[dict] = []
INK = "#080c16"
DEFS = '''<defs>
<linearGradient id="robe" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#49506e"/><stop offset=".42" stop-color="#293047"/><stop offset="1" stop-color="#121a2b"/></linearGradient>
<linearGradient id="violet" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#b78bd8"/><stop offset=".5" stop-color="#79538d"/><stop offset="1" stop-color="#463651"/></linearGradient>
<linearGradient id="bone" x1="0" y1="0" x2=".6" y2="1"><stop stop-color="#f1e6cb"/><stop offset=".55" stop-color="#c9ba98"/><stop offset="1" stop-color="#8b806a"/></linearGradient>
<linearGradient id="steel" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#9ca5b7"/><stop offset=".4" stop-color="#576378"/><stop offset="1" stop-color="#263044"/></linearGradient>
<linearGradient id="blood" x1="0" y1="0" x2=".5" y2="1"><stop stop-color="#be746e"/><stop offset=".55" stop-color="#783d48"/><stop offset="1" stop-color="#3d293b"/></linearGradient>
<linearGradient id="ghost" x1="0" y1="0" x2=".5" y2="1"><stop stop-color="#b4e4d8"/><stop offset=".45" stop-color="#6eacae"/><stop offset="1" stop-color="#345866" stop-opacity=".35"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#f6dea0"/><stop offset=".5" stop-color="#c49a5b"/><stop offset="1" stop-color="#7f5b3b"/></linearGradient>
<linearGradient id="flame" x1="0" y1="0" x2=".4" y2="1"><stop stop-color="#f6d9a0"/><stop offset=".4" stop-color="#e89a65"/><stop offset="1" stop-color="#9d4d57"/></linearGradient>
<radialGradient id="aura"><stop stop-color="#7b628c" stop-opacity=".23"/><stop offset="1" stop-color="#382b50" stop-opacity="0"/></radialGradient>
</defs>'''


def path(d: str, fill: str, stroke: str = INK, width: float = 2.5, extra: str = "") -> str:
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'


def circle(x: float, y: float, radius: float, fill: str, stroke: str = "none", width: float = 1, extra: str = "") -> str:
    return f'<circle cx="{x}" cy="{y}" r="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" {extra}/>'


def ellipse(x: float, y: float, rx: float, ry: float, fill: str, extra: str = "") -> str:
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" {extra}/>'


def line(x1: float, y1: float, x2: float, y2: float, color: str, width: float = 2, extra: str = "") -> str:
    return f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" {extra}/>'


def star(x: float, y: float, r: float, color: str, n: int = 4) -> str:
    pts = []
    for i in range(n * 2):
        a = i * math.pi / n - math.pi / 2
        q = r if i % 2 == 0 else r * .29
        pts.append(f"{x + math.cos(a) * q:.2f},{y + math.sin(a) * q:.2f}")
    return f'<polygon points="{" ".join(pts)}" fill="{color}"/>'


def save_svg(name: str, width: int, height: int, body: str, role: str) -> None:
    target = ASSETS / name
    target.parent.mkdir(parents=True, exist_ok=True)
    content = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n{DEFS}\n{body}\n</svg>\n'
    ElementTree.fromstring(content)
    target.write_text(content, encoding="utf-8", newline="\n")
    MANIFEST.append({"id": name.removesuffix(".svg").replace("/", "_"), "path": f"assets/{name}", "type": "vector", "size": [width, height], "pivot": [.5, .5], "role": role, "source": "tools/art_sprites.py" if name.startswith("sprites/") else "tools/art_environment.py" if name in {"arena.svg", "menu_art.svg"} else "tools/art_icons.py", "creator": "Project original procedural vector artwork", "license": "CC0-1.0", "status": "authored; engine visual QA pending"})


def audio() -> None:
    sr = 22050
    rng = random.Random(7761)
    sounds = {"shoot": .14, "hit": .13, "hurt": .33, "death": .38, "buy": .28, "rune": .46, "level": .65, "victory": .78, "defeat": .75, "ambience": 8.0}
    for name, duration in sounds.items():
        values = []
        for i in range(round(sr * duration)):
            t = i / sr
            p = t / duration
            attack = min(1.0, t / .008)
            tail = (1 - p) ** 2
            if name == "ambience":
                # Integer loop periods and a periodic amplitude shape give a seamless loop.
                v = .035 * math.sin(math.tau * 55 * t) + .021 * math.sin(math.tau * 82.5 * t) + .015 * math.sin(math.tau * 110 * t)
                v += .011 * math.sin(math.tau * 165 * t) * (.5 + .5 * math.sin(math.tau * .125 * t))
            elif name == "shoot":
                v = attack * tail * (.15 * math.sin(math.tau * (750 * t - 1050 * t*t)) + .035 * rng.uniform(-1, 1))
            elif name == "hit":
                v = attack * tail * (.13 * rng.uniform(-1, 1) + .12 * math.sin(math.tau * (180*t - 260*t*t)))
            elif name in {"hurt", "death"}:
                frequency = 155 if name == "hurt" else 95
                v = attack * tail * (.13 * math.sin(math.tau * (frequency*t - 45*t*t)) + .06 * rng.uniform(-1, 1))
            elif name == "buy":
                v = attack * math.exp(-t * 15) * (.16 * math.sin(math.tau * 1046.5*t) + .08 * math.sin(math.tau * 1568*t))
            elif name == "rune":
                v = attack * tail * (.10 * math.sin(math.tau * (330*t + 500*t*t)) + .07 * math.sin(math.tau * (495*t + 750*t*t)))
            elif name in {"level", "victory"}:
                notes = [440, 554.37, 659.25, 880] if name == "level" else [392, 493.88, 587.33, 783.99]
                step = min(3, int(p * 4))
                local = t - step * duration / 4
                v = attack * tail * .19 * math.exp(-local * 8) * (math.sin(math.tau * notes[step] * local) + .25 * math.sin(math.tau * notes[step] * 2 * local))
            else:
                v = attack * tail * (.12 * math.sin(math.tau * (196*t - 50*t*t)) + .08 * math.sin(math.tau * (233.08*t - 60*t*t)))
            values.append(struct.pack("<h", int(max(-.95, min(.95, v)) * 32767)))
        target = ASSETS / "audio" / f"{name}.wav"
        target.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(target), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(sr)
            stream.writeframes(b"".join(values))
        MANIFEST.append({"id": f"audio_{name}", "path": f"assets/audio/{name}.wav", "type": "audio", "duration_seconds": duration, "sample_rate": sr, "loop": name == "ambience", "source": "tools/generate_assets.py", "creator": "Project original deterministic synthesis", "license": "CC0-1.0", "status": "authored; in-game mix QA pending"})


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    from art_sprites import generate as generate_sprites
    from art_environment import generate as generate_environment
    from art_icons import generate as generate_icons
    generate_sprites(save_svg)
    generate_environment(save_svg)
    generate_icons(save_svg)
    audio()
    (ASSETS / "manifest.json").write_text(json.dumps({"schema_version": 1, "style": "Eclipse reliquary: engraved occult vector art", "art_revision": "engraved-04", "license": "CC0-1.0", "generator": "python3 tools/generate_assets.py", "external_sources": [], "assets": MANIFEST}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (ASSETS / "PROVENANCE.md").write_text("# Asset provenance\n\nAll SVG geometry and WAV audio in this directory are original project assets authored through `tools/generate_assets.py` and its `art_sprites.py`, `art_environment.py`, and `art_icons.py` modules. The current visual revision is **engraved-04**. Revision 04 refines the player's matte cloth planes; the other 34 assets retain their previous geometry or audio bytes. No downloaded artwork, stock samples, fonts, trained image generation models, or third-party references are embedded. The generator uses Python's standard library and a fixed random seed.\n\nThe project dedicates these generated assets to the public domain under **CC0 1.0 Universal (CC0-1.0)**. Commercial use, modification, source redistribution, and bundling in the application are permitted; attribution is not required. License text: https://creativecommons.org/publicdomain/zero/1.0/legalcode\n\nAsset dimensions, purposes, and pending engine review are recorded in `manifest.json`. Shadows and lighting are decorative and do not define collision geometry. No brands, existing game characters, or external music melodies were used.\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(MANIFEST)} original assets in {ASSETS}")


if __name__ == "__main__":
    main()
