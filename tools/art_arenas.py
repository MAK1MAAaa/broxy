#!/usr/bin/env python3
"""Original terrain backgrounds. Gameplay ellipses come from data/arenas.json.

Flat floor marks never imply solid obstacles. All upright decoration stays outside
the existing combat rectangle. SVGs are rasterized once by Godot's import pipeline.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path
from typing import Callable

from art_environment import circle, ellipse, line, p, rect, wear_patch

SaveSVG = Callable[[str, int, int, str, str], None]
ROOT = Path(__file__).resolve().parents[1]


def polygon(points: list[tuple[float, float]], fill: str, stroke: str = "none", sw: float = 1, opacity: float = 1) -> str:
    return p("M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points) + "Z", fill, stroke, sw, opacity)


def framing(id: str, floor: str, dark: str, light: str) -> str:
    return f'''<defs>
<linearGradient id="{id}_floor" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="{floor}"/><stop offset="1" stop-color="{dark}"/></linearGradient>
<radialGradient id="{id}_light"><stop stop-color="{light}" stop-opacity=".10"/><stop offset="1" stop-color="{light}" stop-opacity="0"/></radialGradient>
<radialGradient id="{id}_edge" cx="50%" cy="48%" r="67%"><stop offset=".45" stop-color="#070e16" stop-opacity="0"/><stop offset=".8" stop-color="#070e16" stop-opacity=".18"/><stop offset="1" stop-color="#070e16" stop-opacity=".8"/></radialGradient>
</defs>''' + rect(0, 0, 1280, 720, dark) + rect(62, 134, 1156, 462, f"url(#{id}_floor)")


def rim(id: str, color: str, accent: str) -> str:
    # Centerline exactly follows the movement rectangle; no decorative wall inside it.
    b = rect(64, 138, 1152, 454, "none", "#070f17", 4, 5, .8)
    b += rect(66, 140, 1148, 450, "none", color, 1, 3, .45)
    b += ellipse(640, 365, 580, 250, f"url(#{id}_light)")
    b += rect(0, 0, 1280, 720, f"url(#{id}_edge)")
    # A small, quiet inlaid compass preserves the altar's ritual identity.
    b += circle(640, 365, 34, stroke=accent, sw=.8, opacity=.15)
    b += p("M640 343 L647 365 640 387 633 365Z M618 365 H662", stroke=accent, sw=.9, opacity=.15)
    return b


def in_zone(x: float, y: float, zone: dict, margin: float = 0) -> bool:
    cx, cy = zone["center"]
    rx, ry = zone["radius"]
    return ((x - cx) / max(1, rx - margin)) ** 2 + ((y - cy) / max(1, ry - margin)) ** 2 <= 1


def zone_shape(zone: dict, fill: str, edge: str) -> str:
    x, y = zone["center"]
    rx, ry = zone["radius"]
    # The visible outside edge is the exact simulation boundary, not an approximate
    # irregular silhouette. Interior accents are scattered only within this ellipse.
    return ellipse(x, y, rx, ry, fill, edge, 1.3, .97)


def reed(x: float, y: float, scale: float, tone: str) -> str:
    b = f'<g transform="translate({x:.1f} {y:.1f}) scale({scale:.2f})">'
    b += p("M-11 0 Q-10 -12 -18 -22 M-4 1 Q-2 -17 -6 -32 M1 0 Q7 -19 16 -27 M8 1 Q15 -6 20 -15", stroke="#0b181d", sw=3)
    b += p("M-11 0 Q-10 -12 -18 -22 M-4 1 Q-2 -17 -6 -32 M1 0 Q7 -19 16 -27 M8 1 Q15 -6 20 -15", stroke=tone, sw=1.2, opacity=.65)
    b += p("M-7 -30 L-7 -39 M15 -26 L19 -33", stroke="#6f7153", sw=2.3, opacity=.5)
    return b + '</g>'


def mire_body(definition: dict) -> str:
    rng = random.Random(0xBAD6E)
    b = framing("mire", "#223632", "#101e21", "#829779")
    # Broad sediment bands bend around an old diagonal pilgrim causeway.
    for index in range(20):
        x = rng.uniform(75, 1200)
        y = rng.uniform(153, 573)
        b += wear_patch(x, y, rng.uniform(40, 100), rng.uniform(8, 23), rng.choice(["#31443a", "#172c2b", "#405044"]), .2, 4100 + index)
    for index in range(15):
        stone_rng = random.Random(0x5700+index)
        x = max(110, 109 + index * 75 + stone_rng.uniform(-5,5))
        y = 482 - index * 18 + math.sin(index * .6) * 10 + stone_rng.uniform(-5,5)
        w, h = stone_rng.uniform(30,43), stone_rng.uniform(20,27)
        # Flush, weathered stepping stones are decorative flat ground.
        b += polygon([(x-w,y-h+6),(x-w+8,y-h),(x+w-11,y-h-2),(x+w,y-h+10),(x+w-3,y+h-8),(x+w-15,y+h),(x-w+9,y+h-3),(x-w+1,y+4)], "#35443d", "#182b2a", 1.8, .7)
        b += p(f"M{x-w+9:.1f} {y-h+2:.1f} l{w*1.3:.1f} -1 M{x-w+4:.1f} {y-h+10:.1f} l1 12", stroke="#7c8972", sw=1, opacity=.22)
        b += p(f"M{x+w-13:.1f} {y-h:.1f} l-5 8 3 6 -6 4", stroke="#172b2a", sw=1, opacity=.8)
        b += wear_patch(x+5, y+h-4, 24, 6, "#253d30", .65, 5000+index)
    for index in range(50):
        x, y = rng.uniform(83, 1198), rng.uniform(153, 576)
        b += p(f"M{x:.1f} {y:.1f} q12 -4 27 0 t23 1", stroke="#4b6455", sw=.8, opacity=.18)
    for zi, zone in enumerate(definition["zones"]):
        x, y = zone["center"]
        rx, ry = zone["radius"]
        b += zone_shape(zone, "#142d2c", "#52654e")
        b += ellipse(x, y, rx-3, ry-3, "none", "#0c2326", 3, .75)
        b += ellipse(x-5, y+5, rx*.72, ry*.62, "#183330", opacity=.5)
        for index in range(28):
            px, py = rng.uniform(x-rx+10, x+rx-10), rng.uniform(y-ry+8, y+ry-8)
            if not in_zone(px, py, zone, 10):
                continue
            b += p(f"M{px:.1f} {py:.1f} q10 -3 22 0", stroke="#63826a", sw=.9, opacity=.24)
            if index % 5 == 0:
                b += ellipse(px, py-2, 4, 1.5, "#65775a", opacity=.6)
        # Short flat reeds are inboard of the mathematically exact edge.
        for angle in [0.45, 1.9, 3.6, 5.35]:
            px = x+math.cos(angle)*(rx-16)
            py = y+math.sin(angle)*(ry-12)
            b += p(f"M{px:.1f} {py:.1f} l-5 -3 m5 3 l3 -5 m-3 5 l8 -1", stroke="#707959", sw=.9, opacity=.7)
    # Snapped trees, root silhouettes and tall reeds are restricted to the rim.
    for x, y, mirror in [(95,130,1),(456,128,-1),(835,128,1),(1170,128,-1),(107,702,-1),(1110,702,1)]:
        b += f'<g transform="translate({x} {y}) scale({mirror} 1)">'
        b += p("M-25 0 L-14 -19 -15 -61 -21 -90 -5 -80 3 -94 10 -73 7 -43 19 -58 36 -64 27 -49 12 -31 14 -13 31 0Z", "#263b35", "#0a1d20", 2)
        b += p("M-10 -17 L-9 -65 -14 -77 M-5 -67 L-2 -23 M2 -35 L17 -50", stroke="#5e6f56", sw=1.3, opacity=.55)
        b += '</g>'
    for index in range(34):
        x = 70+index*34
        b += reed(x, 130-rng.uniform(0,15), rng.uniform(.5,.9), "#65745a")
        b += reed(x+8, 635+rng.uniform(0,23), rng.uniform(.7,1.1), "#5b6b52")
    for y in [211, 362, 535]:
        b += reed(43,y,1.0,"#718068") + reed(1244,y+20,1.1,"#718068")
    b += rim("mire", "#66806b", "#8f987b")
    return b


def ice_spire(x: float, y: float, h: float, width: float) -> str:
    b = polygon([(x-width/2,y),(x-width*.42,y-h*.55),(x+width*.08,y-h),(x+width*.45,y-h*.64),(x+width/2,y)], "#263e4a", "#142635", 2)
    b += polygon([(x-width*.42,y-h*.55),(x+width*.08,y-h),(x-width*.05,y-8)], "#66818b", opacity=.5)
    b += polygon([(x+width*.08,y-h),(x+width*.45,y-h*.64),(x+width/2,y),(x+width*.05,y-6)], "#203847", opacity=.8)
    b += p(f"M{x+width*.08:.1f} {y-h:.1f} L{x-width*.05:.1f} {y-8:.1f}", stroke="#94aab0", sw=.8, opacity=.5)
    return b


def glacier_body(definition: dict) -> str:
    rng = random.Random(0xF2057)
    b = framing("glacier", "#263a46", "#121f2d", "#91b7c2")
    # Long intersecting, hairline fracture plates replace the original tile grid.
    for index in range(18):
        x = 65+index*69
        fracture_rng = random.Random(0x1CE0+index)
        points = [(max(68,x+fracture_rng.uniform(-14,14)),142)]
        for step in range(1,8):
            points.append((min(1212,max(68,x+fracture_rng.uniform(-26,26))),142+step*64))
        d = "M"+" L".join(f"{px:.1f} {py:.1f}" for px,py in points)
        b += p(d, stroke="#122732", sw=2, opacity=.65)
        b += p("M"+" L".join(f"{px+1.6:.1f} {py-1:.1f}" for px,py in points[:4]), stroke="#73939d", sw=.6, opacity=.19)
        if index%3==0:
            px,py=points[3]
            b += p(f"M{px:.1f} {py:.1f} l34 -17 19 4 12 -14",stroke="#122732",sw=1.1,opacity=.5)
    for points in [[(70,144),(398,144),(542,219),(300,285)],[(1031,145),(1211,144),(1211,398),(1080,312)],[(487,589),(655,496),(863,589)]]:
        b += polygon(points,"#7c9ba6",opacity=.035)
    for index in range(7):
        y = 176+index*61
        b += p(f"M68 {y} Q330 {y-24} 626 {y+18} T1212 {y-4}", stroke="#172d3a", sw=1.5, opacity=.65)
        b += p(f"M102 {y-2} Q290 {y-24} 419 {y+3}", stroke="#76919d", sw=.7, opacity=.18)
    for index in range(22):
        x, y = rng.uniform(96, 1187), rng.uniform(156, 577)
        b += wear_patch(x,y,rng.uniform(28,70),rng.uniform(7,14),"#97b6b9",.055,6100+index)
    # A shattered, flush circular stone inlay keeps the arena legible without
    # suggesting a raised platform or an impassable fracture.
    b += ellipse(640,365,226,151,"none","#122936",4,.48)
    b += ellipse(640,365,223,148,"none","#6c8792",.9,.21)
    b += p("M490 262 L536 311 517 370 584 398 570 453 M681 222 L686 281 726 305 703 364 747 409 751 491", stroke="#112a38", sw=2, opacity=.55)
    for zone in definition["zones"]:
        x, y = zone["center"]
        rx, ry = zone["radius"]
        b += zone_shape(zone,"#3c505b","#718c94")
        b += ellipse(x,y,rx-3,ry-3,"none","#1e3744",1.5,.45)
        for index in range(54):
            px, py = rng.uniform(x-rx+8,x+rx-8), rng.uniform(y-ry+7,y+ry-7)
            if not in_zone(px,py,zone,8):
                continue
            length = rng.uniform(3,11)
            b += p(f"M{px:.1f} {py:.1f} l{length:.1f} -1.4",stroke="#a7bcc0",sw=.7,opacity=.28)
            if index % 9 == 0:
                b += p(f"M{px:.1f} {py-3:.1f} l3 4 -4 1 -2 -3Z","#94adb6",opacity=.3)
    for x in range(72,1230,65):
        b += ice_spire(x,129,rng.uniform(32,96),rng.uniform(24,47))
        b += ice_spire(x+17,681,rng.uniform(30,72),rng.uniform(22,42))
    for y in [214,345,482,574]:
        b += ice_spire(33,y,rng.uniform(36,64),43)
        b += ice_spire(1248,y+10,rng.uniform(38,70),42)
    b += rim("glacier","#6c8795","#a0bcc2")
    return b


def ashland_body(definition: dict) -> str:
    rng = random.Random(0xA51A)
    b = framing("ashland", "#352e2c", "#1f2024", "#b59e77")
    # Cooling basalt forms staggered hexagonal plates rather than laid bricks.
    # Vertex jitter and interrupted mineral edges keep the columns weathered.
    for column in range(13):
        for row in range(-1,6):
            x = 69+column*99
            y = 150+row*86+(column%2)*43
            if y+40<142 or y-40>588:
                continue
            offsets=[(-63,0),(-31,-40),(31,-40),(63,0),(31,40),(-31,40)]
            pts=[(min(1212,max(68,x+dx+rng.uniform(-1.8,1.8))),min(588,max(142,y+dy+rng.uniform(-1.5,1.5)))) for dx,dy in offsets]
            b += polygon(pts,rng.choice(["#38322e","#332e2c","#3b342e","#302d2c"]),"#1b2023",1.6)
            if 182<y<548 and 110<x<1165:
                b += p(f"M{x-52:.1f} {y-8:.1f} l23 -27 45 -1",stroke="#a29171",sw=.8,opacity=.16)
                b += wear_patch(x+3,y+12,32,9,"#82715a",.055,0xBA50+column*17+row)
                if column%3==row%3:
                    b += p(f"M{x-21:.1f} {y+5:.1f} l14 -8 11 13 19 -3",stroke="#131b21",sw=1.6,opacity=.8)
                    b += p(f"M{x-20:.1f} {y+7:.1f} l13 -8 11 13 14 -2",stroke="#86735b",sw=.7,opacity=.22)
    # Cold, buried fissures avoid the coral hue reserved for hostile telegraphs.
    b += p("M74 390 L175 355 231 369 308 333 380 349 461 313 511 329 M770 443 L825 414 890 430 961 397 1050 417 1132 380 1210 398",stroke="#151d22",sw=8,opacity=.7)
    b += p("M75 390 L175 355 231 369 308 333 380 349 461 313 M826 414 L890 430 961 397 1050 417 1132 380",stroke="#7b6546",sw=1,opacity=.35)
    for zone in definition["zones"]:
        x,y=zone["center"]
        rx,ry=zone["radius"]
        b += zone_shape(zone,"#53473a","#8c795b")
        b += ellipse(x,y,rx-3,ry-3,"none","#302b28",1.4,.65)
        for index in range(18):
            dy = -ry+8+index*(2*ry-16)/18
            span = math.sqrt(max(0,1-(dy/ry)**2))*rx-8
            if span<6:
                continue
            b += p(f"M{x-span:.1f} {y+dy:.1f} Q{x-span*.2:.1f} {y+dy-5:.1f} {x+span:.1f} {y+dy-1:.1f}",stroke="#9b896b",sw=.8,opacity=.17)
        for index in range(25):
            px,py=rng.uniform(x-rx+8,x+rx-8),rng.uniform(y-ry+6,y+ry-6)
            if in_zone(px,py,zone,7):
                b += line(px,py,px+2,py,"#c0ad87",.75,.24)
    # Ragged volcanic outcrops frame the arena from beyond its north/south edge.
    for index in range(22):
        x=52+index*56
        h=rng.uniform(34,78)
        b += polygon([(x-33,131),(x-21,131-h*.6),(x+4,131-h),(x+30,131-h*.55),(x+32,131)],"#353432","#141e24",2)
        b += polygon([(x-21,131-h*.6),(x+4,131-h),(x-3,130),(x-28,130)],"#575047",opacity=.4)
        b += p(f"M{x+4:.1f} {131-h:.1f} l-3 {h*.6:.1f}",stroke="#95836a",sw=.8,opacity=.32)
        y=646+rng.uniform(0,15)
        b += polygon([(x-31,y+43),(x-21,y-4),(x+7,y-28),(x+31,y+6),(x+33,y+43)],"#33312e","#162027",2)
        b += p(f"M{x-21:.1f} {y-4:.1f} L{x+7:.1f} {y-28:.1f} {x+1:.1f} {y+30:.1f}",stroke="#80715b",sw=1,opacity=.4)
    for index in range(18):
        y=160+index*23
        b += polygon([(16,y),(47,y-8),(58,y+8),(40,y+22),(13,y+19)],"#383630","#1b2327",2)
        b += polygon([(1224,y+7),(1248,y-3),(1274,y+3),(1267,y+24),(1232,y+22)],"#383630","#1b2327",2)
    b += rim("ashland","#86775f","#ad9975")
    return b


def generate(save_svg: SaveSVG) -> None:
    definitions = json.loads((ROOT / "data" / "arenas.json").read_text(encoding="utf-8"))
    builders = {"mire": mire_body, "glacier": glacier_body, "ashland": ashland_body}
    roles = {
        "mire": "green-black wetland, flush mossy causeway, reeds and snapped perimeter trees; exact mud ellipses shared with data/arenas.json",
        "glacier": "blue-grey fractured ice floor, inset broken ring and perimeter ice spires; exact frost-sand ellipses shared with data/arenas.json",
        "ashland": "brown charcoal basalt plates, dormant fissures and perimeter outcrops; exact loose-ash ellipses shared with data/arenas.json",
    }
    for definition in definitions:
        definition = dict(definition)
        definition["zones"] = definition["zones"][:definition.get("legacy_zone_count", len(definition["zones"]))]
        id = definition["id"]
        if id in builders:
            save_svg(f"maps/{id}.svg",1280,720,builders[id](definition),roles[id] + "; fixed unobstructed combat Rect2(66,140,1148,450), quiet center spawn, no baked typography")
