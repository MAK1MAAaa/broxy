"""Original projectile heads, sampled at two SVG pixels per world pixel."""
from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Callable

SOURCES: tuple[str, ...] = (
    "bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring",
)
FRAME_SIZE = 64
WORLD_SIZE = 32
ROOT = Path(__file__).resolve().parents[1]


def default_radii() -> dict[str, float]:
    radii: dict[str, float] = {}
    for source in SOURCES:
        text = (ROOT / "data" / "weapons" / f"{source}.tres").read_text(encoding="utf-8")
        match = re.search(r"^projectile_radius\s*=\s*([0-9.]+)\s*$", text, re.MULTILINE)
        if match is None or float(match.group(1)) <= 0:
            raise ValueError(f"Missing positive projectile radius: {source}")
        radii[source] = float(match.group(1))
    return radii


def _number(value: float) -> str:
    return f"{value:.8f}".rstrip("0").rstrip(".") or "0"


def _point(x: float, y: float) -> str:
    return f"{_number(x)},{_number(y)}"


def local_segments(source: str, radius: float) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    if source == "crescent":
        for index in range(8):
            angle_a = -math.pi * .5 + index * math.pi / 8
            angle_b = -math.pi * .5 + (index + 1) * math.pi / 8
            for depth in (12., 6.):
                segments.append(((-5 + math.cos(angle_a) * depth, -math.sin(angle_a) * 10),
                                 (-5 + math.cos(angle_b) * depth, -math.sin(angle_b) * 10)))
    elif source == "storm":
        for sign in (-1., 1.):
            offsets = [(-11., sign * 3), (-4., sign * 6), (-6., sign), (5., 0.)]
            for index in range(3):
                a, b = offsets[index], offsets[index + 1]
                segments.append(((a[0], -a[1]), (b[0], -b[1])))
    elif source == "comet":
        for index in range(5):
            angle_a = index * math.tau / 5
            angle_b = (index + .5) * math.tau / 5
            angle_c = (index + 1) * math.tau / 5
            r = radius + 3
            a = (math.cos(angle_a) * r, math.sin(angle_a) * r)
            b = (math.cos(angle_b) * r * .43, math.sin(angle_b) * r * .43)
            c = (math.cos(angle_c) * r, math.sin(angle_c) * r)
            segments.extend(((a, b), (b, c)))
    elif source == "return_ring":
        for blade in range(3):
            base = blade * math.tau / 3
            outline = [
                (math.cos(base + math.radians(angle)) * r, math.sin(base + math.radians(angle)) * r)
                for angle, r in ((-50, 9), (-10, 10), (35, 9.5), (55, 6), (15, 6), (-40, 5.5))
            ]
            for edge, a in enumerate(outline):
                segments.append((a, outline[(edge + 1) % len(outline)]))
    return segments


def generate(save_svg: Callable[[str, int, int, str, str], None]) -> dict:
    radii = default_radii()
    body: list[str] = []
    frames: list[dict] = []
    for frame, source in enumerate(SOURCES):
        radius = radii[source]
        body.append(f'<g transform="translate({frame * FRAME_SIZE + 32} 32) scale(2)">')
        if source != "return_ring":
            scale = .4 if source == "ember" else .18 if source == "crescent" else .35 if source == "comet" else .55
            points = " ".join(_point(math.cos(index * math.tau / 16) * radius * scale,
                                     math.sin(index * math.tau / 16) * radius * scale) for index in range(16))
            color = "#f8efe2" if source == "ember" else "#f5efe0"
            body.append(f'<polygon points="{points}" fill="{color}"/>')
        color = "#e7dba8" if source == "storm" else "#d5c1e8" if source == "comet" else "#d3e8de"
        for a, b in local_segments(source, radius):
            body.append(f'<path d="M{_point(*a)} L{_point(*b)}" fill="none" stroke="{color}" stroke-width="1.3" stroke-opacity=".85" stroke-linecap="butt"/>')
        body.append('</g>')
        frames.append({"source": source, "frame": frame, "base_radius": radius})
    save_svg("fx/projectile_heads.svg", FRAME_SIZE * len(SOURCES), FRAME_SIZE, "\n".join(body),
             "eight projectile-head frames; two pixels per world pixel; baked sixteen-sided white cores and authored sigil segments; return ring has no core")
    return {"frame_size": [FRAME_SIZE, FRAME_SIZE], "world_size": [WORLD_SIZE, WORLD_SIZE],
            "columns": len(SOURCES), "rows": 1, "sampling_scale": 2, "frames": frames}
