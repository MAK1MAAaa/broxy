#!/usr/bin/env python3
"""Original environment artwork for the Eclipse Reliquary vector family.

Only paths, shapes and gradients are used: no SVG filters, masks,
external images or fonts. All procedural variation is deterministically seeded.
"""
from __future__ import annotations

import math
import random
from typing import Callable

SaveSVG = Callable[[str, int, int, str, str], None]


def p(d: str, fill: str = "none", stroke: str = "none", sw: float = 1, opacity: float = 1) -> str:
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" opacity="{opacity}"/>'


def rect(x: float, y: float, w: float, h: float, fill: str, stroke: str = "none", sw: float = 1, rx: float = 0, opacity: float = 1) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>'


def circle(x: float, y: float, r: float, fill: str = "none", stroke: str = "none", sw: float = 1, opacity: float = 1) -> str:
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>'


def ellipse(x: float, y: float, rx: float, ry: float, fill: str = "none", stroke: str = "none", sw: float = 1, opacity: float = 1) -> str:
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{opacity}"/>'


def line(x1: float, y1: float, x2: float, y2: float, stroke: str, sw: float = 1, opacity: float = 1) -> str:
    return p(f"M{x1:g} {y1:g} L{x2:g} {y2:g}", stroke=stroke, sw=sw, opacity=opacity)


def star(x: float, y: float, radius: float, fill: str, opacity: float = 1) -> str:
    return p(f"M{x:g} {y-radius:g} L{x+radius*.22:g} {y-radius*.22:g} L{x+radius:g} {y:g} L{x+radius*.22:g} {y+radius*.22:g} L{x:g} {y+radius:g} L{x-radius*.22:g} {y+radius*.22:g} L{x-radius:g} {y:g} L{x-radius*.22:g} {y-radius*.22:g}Z", fill=fill, opacity=opacity)


def glyph(x: float, y: float, size: float, angle: float, color: str, opacity: float) -> str:
    return f'<g transform="translate({x:g} {y:g}) rotate({angle:g}) scale({size:g})">' + p("M-3 -4 L0 4 3 -4 M-3 -1 H3 M0 -5 V5", stroke=color, sw=1, opacity=opacity) + '</g>'


def wear_patch(x: float, y: float, rx: float, ry: float, fill: str, opacity: float, seed: int) -> str:
    """Broad, soft-edged mineral wear rather than repeated oval spots."""
    rng = random.Random(seed)
    points = []
    for index in range(9):
        angle = index * math.tau / 9
        radius = rng.uniform(.55, 1.0)
        points.append((x + math.cos(angle) * rx * radius, y + math.sin(angle) * ry * radius))
    middle = lambda a, b: ((a[0] + b[0]) * .5, (a[1] + b[1]) * .5)
    start = middle(points[-1], points[0])
    d = f"M{start[0]:.1f} {start[1]:.1f}"
    for index, point in enumerate(points):
        end = middle(point, points[(index + 1) % len(points)])
        d += f" Q{point[0]:.1f} {point[1]:.1f} {end[0]:.1f} {end[1]:.1f}"
    return p(d + "Z", fill, opacity=opacity)


def slab_edges(x: float, y: float, right: float, bottom: float, seed: int) -> str:
    """Shallow facets stay inside each existing slab; no raised obstacle shapes."""
    rng = random.Random(seed)
    # Broken, narrow lips avoid making every slab look like a raised bevelled panel.
    edge_width = rng.uniform(1.3, 2.5)
    edge_end = x + (right - x) * rng.uniform(.62, .91)
    b = p(f"M{x+7:.1f} {y+4:.1f} L{edge_end:.1f} {y+4:.1f} {edge_end-5:.1f} {y+4+edge_width:.1f} {x+11:.1f} {y+5+edge_width:.1f}Z", "#8f9b92", opacity=.09)
    b += line(x+4,y+11,x+4,bottom-13,"#829289",.8,.09)
    b += p(f"M{right-4:.1f} {y+9:.1f} L{right-4:.1f} {bottom-6:.1f} {right-8:.1f} {bottom-4:.1f} {x+10:.1f} {bottom-4:.1f} {x+14:.1f} {bottom-6:.1f} {right-7:.1f} {bottom-7:.1f}Z", "#0b1925", opacity=.22)
    # Chisel scratches follow the top-left illumination, with generous quiet gaps.
    if right - x > 60 and rng.random() < .65:
        px = rng.uniform(x + 13, right - 22)
        py = rng.uniform(y + 12, bottom - 12)
        length = min(rng.uniform(8, 23), right - px - 8)
        b += p(f"M{px:.1f} {py:.1f} l{length*.6:.1f} -1.5 {length*.4:.1f} 1", stroke="#9aa294", sw=.65, opacity=.10)
    if right - x > 64 and rng.random() < .48:
        chip = rng.uniform(x + 17, right - 17)
        b += p(f"M{chip-5:.1f} {y+3:.1f} l4 5 5 -2 3 -3Z", "#152430", opacity=.85)
        b += p(f"M{chip-1:.1f} {y+8:.1f} l5 -2 3 -2", stroke="#889489", sw=.7, opacity=.22)
        b += p(f"M{chip+1:.1f} {y+8:.1f} l-3 7 4 4 -2 5", stroke="#0e1e2a", sw=.8, opacity=.6)
    return b


def candle(x: float, y: float, scale: float, prefix: str) -> str:
    # The y coordinate is the foot of a tall candle, not its flame.
    b = f'<g transform="translate({x:g} {y:g}) scale({scale:g})">'
    b += ellipse(0, -21, 57, 82, f"url(#{prefix}_candlelight)")
    b += ellipse(1, 8, 15, 4, "#050d17", opacity=.8)
    b += p("M-12 7 L-10 3 -5 1 -3 -7 H3 L5 1 10 3 12 7Z", f"url(#{prefix}_brass)", "#101622", 1.4)
    b += p("M-4 -9 L-4 -37 Q-1 -40 4 -37 V-9Z", f"url(#{prefix}_wax)", "#4f453a", .8)
    b += p("M-4 -34 Q-2 -30 -1 -34 V-23 Q1 -20 1 -27 V-33 Q3 -29 4 -34", stroke="#e0cfab", sw=1.1)
    b += ellipse(0, -37, 4, 1.5, "#e4d2a5")
    b += p("M0 -56 Q-7 -44 -2 -40 Q4 -37 5 -43 Q5 -48 0 -56Z", f"url(#{prefix}_fire)")
    b += p("M0 -50 Q-3 -43 0 -41 Q3 -43 0 -50Z", "#fff2c9")
    b += line(0, -42, 0, -37, "#503f31", .8)
    b += '</g>'
    return b


def defs(prefix: str) -> str:
    return f'''<defs>
<linearGradient id="{prefix}_stone" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#45535b"/><stop offset=".4" stop-color="#293843"/><stop offset="1" stop-color="#17232e"/></linearGradient>
<linearGradient id="{prefix}_stone_edge" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#5a6263"/><stop offset=".24" stop-color="#39464e"/><stop offset="1" stop-color="#1b2a36"/></linearGradient>
<linearGradient id="{prefix}_brass" x1="0" y1="0" x2=".85" y2="1"><stop stop-color="#d6bc84"/><stop offset=".2" stop-color="#a18a5e"/><stop offset=".55" stop-color="#716144"/><stop offset=".8" stop-color="#b09868"/><stop offset="1" stop-color="#51473b"/></linearGradient>
<linearGradient id="{prefix}_wax" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#b6a58a"/><stop offset=".35" stop-color="#d6c6a5"/><stop offset="1" stop-color="#87755b"/></linearGradient>
<linearGradient id="{prefix}_fire" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#e5ab6e"/><stop offset=".6" stop-color="#f4d49b"/><stop offset="1" stop-color="#cc8052"/></linearGradient>
<radialGradient id="{prefix}_candlelight"><stop stop-color="#e4a46b" stop-opacity=".23"/><stop offset=".3" stop-color="#ce8e59" stop-opacity=".11"/><stop offset="1" stop-color="#b97d50" stop-opacity="0"/></radialGradient>
<radialGradient id="{prefix}_vignette" cx="50%" cy="46%" r="68%"><stop offset=".35" stop-color="#07111b" stop-opacity="0"/><stop offset=".7" stop-color="#07111b" stop-opacity=".2"/><stop offset="1" stop-color="#040a13" stop-opacity=".88"/></radialGradient>
<linearGradient id="{prefix}_upper_shadow" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#050c15" stop-opacity=".84"/><stop offset=".2" stop-color="#07121d" stop-opacity=".15"/><stop offset=".5" stop-color="#0a1721" stop-opacity="0"/><stop offset="1" stop-color="#06101b" stop-opacity=".4"/></linearGradient>
<radialGradient id="{prefix}_floorlight"><stop stop-color="#758579" stop-opacity=".07"/><stop offset="1" stop-color="#32484b" stop-opacity="0"/></radialGradient>
</defs>'''


def arena_body() -> str:
    rng = random.Random(0xEC11A)
    b = defs("env")
    b += rect(0, 0, 1280, 720, "#111e2b")
    b += rect(49, 112, 1182, 506, "#0a1521", "#34424b", 3, 13)
    b += rect(57, 119, 1166, 490, "#25343e", "#4c5559", 1.3, 7)
    # Large, worn slabs remain readable at native scale without visual noise.
    colors = ["#26353e", "#27363f", "#283840", "#293840", "#293942", "#2a3940", "#27363e"]
    rows = [122, 177, 231, 286, 343, 400, 457, 515, 573, 607]
    for row in range(len(rows) - 1):
        y, bottom = rows[row], rows[row+1]
        x = 59.0
        column = 0
        while x < 1221:
            width = rng.uniform(100, 162) if column or row % 2 == 0 else rng.uniform(56, 94)
            right = min(1221, x + width)
            if right - x < 10:
                break
            n1, n2 = rng.uniform(2, 7), rng.uniform(2, 7)
            points = [(x+2, y+2+n1*.2), (right-5, y+2), (right-2, y+n2), (right-2, bottom-5), (right-6, bottom-2), (x+n1, bottom-2), (x+2, bottom-6)]
            d = "M" + " L".join(f"{a:.1f} {c:.1f}" for a, c in points) + "Z"
            b += p(d, rng.choice(colors), "#14232e", 1.3)
            # A separate detail seed preserves the established slab layout/RNG stream.
            detail_seed = 0x5A17 + row * 257 + column * 977
            b += slab_edges(x, y, right, bottom, detail_seed)
            if right - x > 70:
                px, py = x+(right-x)*rng.uniform(.2,.65), y+(bottom-y)*rng.uniform(.25,.75)
                b += wear_patch(px, py, rng.uniform(15, 35), rng.uniform(5, 13), "#8b9787", rng.uniform(.035,.065), detail_seed + 13)
                if rng.random() < .34:
                    b += p(f"M{px:.1f} {py:.1f} l9 -3 6 5 11 -2 6 5", stroke="#12222e", sw=1, opacity=.57)
                    b += p(f"M{px+9:.1f} {py-3:.1f} l-1 -7 5 -4", stroke="#14232d", sw=.7, opacity=.4)
            x = right
            column += 1
    # Shallow grooves imply an inset stone border, never a collision wall.
    b += rect(61, 125, 1158, 476, "none", "#111f2b", 6, 5, .65)
    b += rect(66, 130, 1148, 466, "none", "#718077", .85, 3, .23)
    for x in range(113, 1200, 91):
        b += line(x, 125, x-2, 139, "#121f29", 2, .7)
        b += line(x-2, 583, x, 601, "#121f29", 2, .75)
    b += ellipse(640, 365, 510, 242, "url(#env_floorlight)")
    # Gold is embedded and muted. Telegraphs are rendered later by the game.
    for radius, sw, opacity in [(181, 6, .36), (180, 1.1, .19), (174, .8, .14), (151, 4.5, .33), (150, 1, .18), (145, .65, .13)]:
        color = "#101f2c" if sw > 2 else "#ad9871"
        b += circle(640, 365, radius, stroke=color, sw=sw, opacity=opacity)
    for index in range(48):
        a = index * math.tau / 48
        r1 = 152 if index % 4 else 149
        r2 = 170 if index % 4 else 175
        b += line(640+math.cos(a)*r1, 365+math.sin(a)*r1, 640+math.cos(a)*r2, 365+math.sin(a)*r2, "#aa9368", .7 if index % 4 else 1.3, .12)
    for index in range(12):
        a = index * math.tau / 12
        b += glyph(640+math.cos(a)*163, 365+math.sin(a)*163, .75, index*30+90, "#b39e78", .14)
    for radius, alpha in [(112,.095), (101,.085), (63,.07)]:
        b += circle(640,365,radius,stroke="#9ba291",sw=1,opacity=alpha)
    b += p("M640 258 L732.7 418.5 H547.3Z M640 472 L547.3 311.5 H732.7Z", stroke="#b1a17c", sw=.9, opacity=.075)
    b += p("M640 321 L650 355 684 365 650 375 640 409 630 375 596 365 630 355Z", stroke="#b6a582", sw=.9, opacity=.1)
    # Uneven wear patches are broad and almost invisible in the center.
    for index in range(24):
        x, y = rng.uniform(94,1186), rng.uniform(149,574)
        b += wear_patch(x,y,rng.uniform(13,37),rng.uniform(3,10),"#101e2a",rng.uniform(.035,.1),0x7EA2+index)
    b += rect(57, 119, 1166, 490, "url(#env_upper_shadow)", rx=7)
    # Recessed northern chapel arcade, entirely outside the actual combat bounds.
    for x in range(100, 1220, 135):
        b += p(f"M{x-57} 128 V60 Q{x-56} 27 {x} 2 Q{x+56} 27 {x+57} 60 V128Z", "url(#env_stone)", "#0b1622", 4)
        b += p(f"M{x-45} 121 V63 Q{x-44} 37 {x} 15 Q{x+44} 37 {x+45} 63 V121Z", "#0a1420", "#4c555a", 1.4, .9)
        b += p(f"M{x-35} 119 V65 Q{x-34} 46 {x} 27 Q{x+34} 46 {x+35} 65 V119Z", "#101c28", "#283944", 1)
        b += line(x,29,x,116,"#273943",2)
        b += p(f"M{x-33} 79 Q{x-13} 60 {x} 83 Q{x+13} 60 {x+33} 79", stroke="#2d3d47",sw=1.6)
        b += circle(x,57,12,stroke="#34434a",sw=1)
        b += star(x,57,7,"#5b625e",.4)
        b += rect(x-63,114,126,12,"#293744","#101c28",2,2)
        b += line(x-55,116,x+56,116,"#65706b",.7,.3)
    # Side piers and narrow buttresses preserve x=66..1214 as unobstructed floor.
    for x in [27,1253]:
        for y in [183,345,507]:
            b += ellipse(x+8,y+43,28,53,"#07131f",opacity=.6)
            b += p(f"M{x-16} {y-55} L{x+14} {y-55} {x+19} {y+52} {x-21} {y+52}Z", "url(#env_stone_edge)","#0a1521",2.5)
            b += rect(x-21,y-60,42,13,"#3e4a52","#0b1723",2,2)
            b += rect(x-24,y+45,48,16,"#35454f","#0b1723",2,2)
            b += line(x-8,y-42,x-10,y+36,"#758178",1,.35)
            b += line(x+7,y-40,x+9,y+37,"#14232e",2,.7)
            b += p(f"M{x-3} {y-30} l6 21 -3 15 5 17",stroke="#152530",sw=1.3,opacity=.7)
            b += p(f"M{x-13} {y-47} L{x-6} {y-42} {x+2} {y-48}",stroke="#7b7c6b",sw=.7,opacity=.25)
    # Low southern step and altar table sit beyond y=590.
    b += p("M63 619 L1218 619 1235 642 H47Z", "#1a2936", "#0a1723", 2)
    b += line(67,620,1214,620,"#4e5d62",1,.45)
    b += p("M512 702 L524 655 H756 L768 702Z", "url(#env_stone)", "#0b1621", 3)
    b += rect(515,648,250,17,"#3e4b55","#111d29",2,3)
    b += line(522,650,756,650,"#798077",1,.45)
    b += p("M550 664 V695 H730 V664 M566 665 V693 M714 665 V693",stroke="#172633",sw=2)
    b += p("M618 647 L620 628 H660 L662 647Z", "#4b4351", "#111b27", 2)
    b += p("M621 633 L639 630 640 644 622 647Z M640 630 L658 633 657 647 640 644Z","#9d9379","#27303a",.8)
    # Shadow vignette precedes the luminous candles so the framing stays readable.
    b += rect(0,0,1280,720,"url(#env_vignette)")
    for x,y,s in [(43,245,.82),(1237,245,.82),(43,559,.8),(1237,559,.8),(110,639,.83),(1170,639,.83),(552,648,.75),(729,648,.75)]:
        b += candle(x,y,s,"env")
    # A few wax pools and edge debris signal age without becoming obstacles.
    for x,y in [(107,643),(1168,643),(550,653),(731,653)]:
        b += ellipse(x,y,8,2.3,"#96866c",opacity=.38)
    return b


def menu_body() -> str:
    rng = random.Random(0xECA17)
    b = defs("men")
    b += '''<defs>
<linearGradient id="men_back" x1="0" y1="0" x2="1" y2=".15"><stop stop-color="#101724"/><stop offset=".25" stop-color="#101925"/><stop offset=".7" stop-color="#142331"/><stop offset="1" stop-color="#0b1623"/></linearGradient>
<radialGradient id="men_moonlight"><stop stop-color="#71858a" stop-opacity=".22"/><stop offset=".48" stop-color="#648087" stop-opacity=".09"/><stop offset="1" stop-color="#2b4758" stop-opacity="0"/></radialGradient>
<radialGradient id="men_moon"><stop stop-color="#1b2b35"/><stop offset=".62" stop-color="#14232f"/><stop offset="1" stop-color="#0a1421"/></radialGradient>
<radialGradient id="men_corona"><stop offset=".79" stop-color="#c9b183" stop-opacity="0"/><stop offset=".9" stop-color="#d1b884" stop-opacity=".17"/><stop offset=".96" stop-color="#edd3a0" stop-opacity=".55"/><stop offset="1" stop-color="#b39765" stop-opacity="0"/></radialGradient>
<linearGradient id="men_parchment" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#ddd0ae"/><stop offset=".5" stop-color="#b9ad91"/><stop offset="1" stop-color="#827b6c"/></linearGradient>
<linearGradient id="men_cover" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#6d5973"/><stop offset=".4" stop-color="#443e58"/><stop offset="1" stop-color="#252b40"/></linearGradient>
<linearGradient id="men_quiet_left" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#101724"/><stop offset=".23" stop-color="#101724" stop-opacity=".88"/><stop offset=".47" stop-color="#101724" stop-opacity="0"/></linearGradient>
</defs>'''
    b += rect(0,0,640,720,"url(#men_back)")
    b += ellipse(400,270,285,291,"url(#men_moonlight)")
    # Fine architectural uprights and a dim chapel vault form the distant layer.
    for x in [196,292,510,607]:
        b += line(x,41,x,650,"#34434b",1,.18)
    b += p("M180 615 V187 Q182 80 396 -21 Q612 78 614 187 V615",stroke="#4f5960",sw=1,opacity=.16)
    b += p("M204 613 V190 Q205 101 397 7 Q588 102 591 190 V613",stroke="#3d4d57",sw=1,opacity=.17)
    # The axis and armature ground the eclipse as an instrument rather than a logo.
    b += line(396,18,396,614,"#080f1b",10,.9)
    b += line(394,23,394,607,"#ac966c",1.4,.52)
    for y in [31,47,423,441,598]:
        b += p(f"M389 {y} L396 {y-8} 403 {y} 396 {y+8}Z","url(#men_brass)","#101b27",1)
    b += ellipse(397,251,225,76,stroke="#090f1b",sw=8,opacity=.75)
    b += '<g transform="rotate(-27 397 251)">' + ellipse(397,251,226,70,stroke="url(#men_brass)",sw=2.2,opacity=.72) + ellipse(397,251,217,63,stroke="#958466",sw=.65,opacity=.55) + '</g>'
    b += '<g transform="rotate(52 397 251)">' + ellipse(397,251,183,105,stroke="#7d755f",sw=1,opacity=.38) + '</g>'
    b += circle(397,251,180,stroke="#090f19",sw=10,opacity=.8)
    b += circle(397,251,180,stroke="url(#men_brass)",sw=3.2)
    b += circle(397,251,173,stroke="#bca579",sw=.7,opacity=.7)
    b += circle(397,251,163,stroke="#5a675f",sw=1,opacity=.7)
    for index in range(72):
        a = index*math.tau/72
        inner = 165 if index%6 else 161
        outer = 172 if index%6 else 176
        b += line(397+math.cos(a)*inner,251+math.sin(a)*inner,397+math.cos(a)*outer,251+math.sin(a)*outer,"#c0aa7f",.7 if index%6 else 1.3,.6)
    for index in range(12):
        a=index*math.tau/12
        b += glyph(397+math.cos(a)*190,251+math.sin(a)*190,.8,index*30+90,"#ac976f",.6)
    b += circle(397,251,157,"url(#men_corona)")
    b += circle(397,251,146,"url(#men_brass)","#bfa775",1,.95)
    b += circle(412,239,139,"url(#men_moon)","#41434a",.6)
    # Subtle moon texture uses broad facets, never high contrast mottling.
    for _ in range(21):
        a, r = rng.random()*math.tau, rng.uniform(25,113)
        x,y=412+math.cos(a)*r,239+math.sin(a)*r
        b += ellipse(x,y,rng.uniform(9,29),rng.uniform(4,15),"#72827e",opacity=rng.uniform(.02,.045))
    b += p("M348 128 Q297 158 288 217 M287 237 Q283 293 319 331",stroke="#efd7a5",sw=1.4,opacity=.75)
    b += circle(412,239,94,stroke="#a59b80",sw=.7,opacity=.15)
    b += p("M412 162 L431 220 489 239 431 258 412 316 393 258 335 239 393 220Z",stroke="#b9a68d",sw=.8,opacity=.35)
    b += circle(412,239,29,stroke="#c3ab8e",sw=.8,opacity=.42)
    b += star(412,239,13,"#d2bd9c",.78)
    b += circle(412,239,4,"#e4cda8",opacity=.88)
    for x,y,r in [(228,181,5),(557,341,4),(397,71,6),(238,330,3),(550,140,4)]:
        b += circle(x,y,r,"#897553","#14202a",1.4)
        b += circle(x-1,y-1,r*.35,"#d9c18b",opacity=.8)
    # A lower instrument crescent and suspended counterweight balance the orb.
    b += p("M266 366 Q394 464 528 365",stroke="#0a121e",sw=9,opacity=.7)
    b += p("M266 364 Q394 457 528 364",stroke="url(#men_brass)",sw=2.3,opacity=.8)
    b += p("M393 435 L380 460 396 488 412 460 399 435Z","url(#men_brass)","#111a25",2)
    b += p("M396 446 L389 460 396 475 403 460Z","#343c49","#c4aa77",.7)
    # Broken foreground piers use large facets with sparse hairline fractures.
    b += p("M159 697 L168 472 184 451 197 464 211 447 232 470 244 697Z","url(#men_stone)","#0a1521",3)
    b += p("M170 475 L185 461 191 481 209 466 229 477 238 692 H170Z","#293c48","#45535a",.7,.7)
    b += p("M171 475 L197 486 208 506 202 531 215 552 207 581",stroke="#0d1d2a",sw=2)
    b += p("M202 531 L184 542 178 559 M215 552 L228 548",stroke="#58605e",sw=.6,opacity=.45)
    b += line(180,504,177,678,"#65736e",1.1,.4) + line(221,510,231,679,"#142531",2,.7)
    b += p("M152 693 H252 L264 716 H143Z","url(#men_stone_edge)","#0c1723",2)
    b += line(157,697,251,697,"#7b8272",1,.43)
    b += p("M543 704 L539 406 555 382 568 397 584 377 605 404 616 704Z","url(#men_stone)","#0a1521",3)
    b += p("M542 408 L558 396 571 417 584 397 603 412 610 696 H548Z","#2a3b47","#52605f",.8,.8)
    b += p("M559 397 L566 430 558 446 573 471 568 500 584 516 578 541",stroke="#0c1b28",sw=2)
    b += p("M573 471 L591 463 602 473 M568 500 L552 510",stroke="#6d7568",sw=.7,opacity=.4)
    b += line(551,440,557,687,"#657369",1.3,.33)
    b += line(595,449,603,686,"#14242f",2,.7)
    b += p("M530 700 H625 L636 720 H522Z","url(#men_stone_edge)","#101c29",2)
    b += line(538,704,621,704,"#7b8272",1,.4)
    # Hovering illuminated folio: the brightest lower focal point.
    b += ellipse(369,577,130,39,"#07131f",opacity=.55)
    b += ellipse(365,524,133,125,"url(#men_candlelight)",opacity=.58)
    b += '<g transform="translate(355 520) rotate(-13)">'
    b += p("M-76 -44 L-2 -37 75 -48 78 38 0 49 -78 35Z","#0a1320",stroke="#101723",sw=4)
    b += p("M-78 -49 L-3 -39 75 -50 77 31 0 43 -80 29Z","url(#men_cover)","#101725",3)
    b += p("M-70 -46 Q-33 -45 -2 -34 L0 35 Q-29 21 -71 23Z","url(#men_parchment)","#9b8e72",1)
    b += p("M3 -34 Q35 -49 68 -46 L70 23 Q32 21 3 35Z","url(#men_parchment)","#8b806b",1)
    b += p("M-64 -39 Q-31 -40 -8 -31 M-64 16 Q-30 16 -8 26 M10 -31 Q35 -40 62 -39 M10 26 Q34 16 64 16",stroke="#f0dfb5",sw=.7,opacity=.55)
    b += p("M-1 -34 Q-4 -3 1 35 M4 -34 Q8 0 4 35",stroke="#5e5a5b",sw=1.2,opacity=.8)
    b += p("M-74 -46 L-62 -44 -65 -34 -75 -35Z M63 -46 L74 -49 75 -35 66 -34Z M-77 16 L-65 16 -65 26 -77 28Z M66 17 L76 16 76 30 66 29Z","url(#men_brass)","#423e3c",.7)
    for y in [-23,-14,-5,4,13]:
        b += p(f"M-57 {y} Q-40 {y-2} -22 {y+3}",stroke="#756f63",sw=1,opacity=.55)
        b += p(f"M-58 {y+3} Q-45 {y+1} -35 {y+3}",stroke="#746b60",sw=.5,opacity=.3)
    b += circle(36,-6,20,stroke="#88748e",sw=1.2,opacity=.8)
    b += circle(36,-6,15,stroke="#88748e",sw=.6,opacity=.65)
    b += p("M36 -23 L50 2 H22Z M36 11 L22 -14 H50Z",stroke="#7f6c88",sw=.8,opacity=.75)
    b += star(36,-6,8,"#7c6683",.7)
    b += p("M-10 36 L-8 62 1 56 7 60 8 35Z","#765466","#2e2638",1)
    b += '</g>'
    # The slender ritual staff is a secondary diagonal, not a second main subject.
    b += '<g transform="translate(482 544) rotate(17)">'
    b += p("M0 130 L0 -82",stroke="#151b25",sw=11)
    b += p("M0 130 L0 -82",stroke="url(#men_brass)",sw=6)
    b += line(-1,126,-1,-78,"#d2b98d",.8,.65)
    b += p("M-4 -74 Q-30 -78 -19 -107 L0 -126 19 -107 Q30 -78 4 -74",stroke="#141c26",sw=7)
    b += p("M-4 -74 Q-30 -78 -19 -107 L0 -126 19 -107 Q30 -78 4 -74",stroke="url(#men_brass)",sw=3.5)
    b += p("M0 -117 L13 -100 0 -81 -13 -100Z","#7c6d98","#1c2537",1.7)
    b += p("M0 -117 L0 -83 -13 -100Z","#bd9dc6",opacity=.6)
    b += star(0,-100,5,"#e3d0e0",.85)
    for y in [-63,-58,66,72,78]:
        b += line(-4,y,4,y,"#c3ab78",1.4,.8)
    b += '</g>'
    # Sparse fragments and pinpricks stay on the right; no literal text or UI chrome.
    for x,y,s in [(242,425,1),(494,421,.8),(279,607,.7),(523,629,.65)]:
        b += f'<g transform="translate({x} {y}) rotate({int(x)%47-23}) scale({s})">' + p("M-8 -5 L2 -9 10 -1 4 9 -7 5Z","#3c4c55","#101e2b",1.5) + line(-7,-4,1,-7,"#7a8070",.8,.4) + '</g>'
    for x,y,s in [(212,332,4),(570,253,3),(296,147,3),(503,87,4),(241,566,2.4),(458,610,3)]:
        b += star(x,y,s,"#c5b48e",.65)
    b += ellipse(408,707,248,47,"#07111c",opacity=.5)
    for x,y,s in [(230,690,.93),(517,689,.85),(602,714,.7)]:
        b += candle(x,y,s,"men")
    b += rect(0,0,640,720,"url(#men_quiet_left)")
    return b


def generate(save_svg: SaveSVG) -> None:
    save_svg("arena.svg", 1280, 720, arena_body(), "original worn blue-grey chapel arena; shallow stone facets, chipped seams and mineral wear; unobstructed low-contrast gameplay Rect2(66,140,1148,450); muted gold ritual rings; decorative edge architecture")
    save_svg("menu_art.svg", 640, 720, menu_body(), "original eclipse orrery, illuminated floating folio, cracked columns and candlelight; quiet left 150px; no baked typography")


if __name__ == "__main__":
    from generate_assets import save_svg
    generate(save_svg)
    print("Generated original arena.svg and menu_art.svg; manifest integration is handled by the main asset generator.")
