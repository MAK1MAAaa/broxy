"""Original occult character vectors; shared gradients come from generate_assets.DEFS.

The callback owns serialization and manifest entries. This module only authors the
six existing centered sprite canvases; it never changes gameplay geometry.
"""
from __future__ import annotations

from collections.abc import Callable

INK = "#080c16"
SaveSvg = Callable[[str, int, int, str, str], None]


def _path(d: str, fill: str, stroke: str = INK, width: float = 2.3, extra: str = "") -> str:
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'


def _etch(d: str, color: str, width: float = 1.2, extra: str = "") -> str:
    return _path(d, "none", color, width, extra)


def _ellipse(x: float, y: float, rx: float, ry: float, fill: str, extra: str = "") -> str:
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" {extra}/>'


def _gradient(name: str, light: str, mid: str, dark: str) -> str:
    return f'<linearGradient id="{name}" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="{light}"/><stop offset=".48" stop-color="{mid}"/><stop offset="1" stop-color="{dark}"/></linearGradient>'


def _chain(points: list[tuple[float, float, float]], color: str = "#b29a73") -> str:
    return "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="2.6" ry="1.65" fill="none" stroke="{color}" stroke-width="1.05" transform="rotate({angle} {x} {y})"/>'
        for x, y, angle in points
    )


def _player() -> str:
    body = '<defs>' + _gradient("sp-player-hood", "#75617f", "#44374f", "#1b1b2e")
    body += _gradient("sp-player-cloth", "#6d617c", "#44394f", "#1c2133") + '</defs>'
    body += _ellipse(48, 86, 29, 6, "#030711", 'opacity=".60"')
    # The asymmetric hem and long beak survive the reduced in-game scale.
    body += _path("M31 43 L20 51 13 71 26 68 22 84 39 80 48 89 61 80 77 84 70 66 83 70 75 49 65 41Z", "url(#sp-player-cloth)", width=2.8)
    # Broad matte planes survive the 68px runtime size; retain the dark fold valleys.
    body += _path("M30 49 L36 53 30 74 38 80 25 80Z", "#64536e", width=0)
    body += _path("M65 48 L59 54 65 74 60 80 73 79Z", "#181d31", width=0)
    body += _path("M39 52 L48 58 58 51 62 78 49 86 36 78Z", "#463a52", "#77627d", 1.1)
    body += _path("M47 60 L47 82 39 77 40 56Z", "#735c79", width=0)
    body += _path("M52 61 L58 54 61 77 52 82Z", "#202237", width=0)
    body += _etch("M31 60 L26 73 M67 59 L71 73 M39 65 L37 75 M57 63 L60 75", "#918096", 1.0, 'opacity=".40"')
    body += _path("M28 39 Q26 23 37 13 L47 7 Q61 10 68 26 L69 44 58 53 39 53 27 47Z", "url(#sp-player-hood)", width=2.8)
    body += _path("M35 21 L47 12 60 24 64 41 57 49 39 47 32 38Z", "#111525", "#8e7891", 1.1)
    body += _path("M35 23 L47 13 42 25 36 37 33 37Z", "#938095", width=0, extra='opacity=".42"')
    body += _path("M47 23 Q53 23 58 31 L55 38 64 50 51 46 45 48 38 42 34 31Z", "url(#bone)", width=1.8)
    body += _path("M48 28 L52 36 64 50 51 44 46 37Z", "#a89a7d", width=0)
    body += _path("M36 30 L47 26 42 32 38 37Z", "#f2e6c8", width=0)
    body += _path("M38 33 L45 31 43 36 39 37Z M50 31 L55 31 53 35 51 35Z", "#111524", width=0)
    body += _etch("M39 34 L42 33 M51 32 L53 32", "#d2b77b", .9)
    body += _etch("M48 35 L55 43 M44 42 L46 44", "#776b58", .8)
    body += _path("M27 46 L38 48 48 54 61 47 70 44 66 54 49 64 31 55Z", "url(#sp-player-hood)", width=1.8)
    body += _etch("M30 48 L48 58 67 47", "#a289a2", 1.3)
    body += _etch("M31 54 Q48 71 66 53", "#282332", 3)
    body += _chain([(33, 56, 42), (37, 60, 35), (42, 63, 19), (48, 64, 0), (54, 63, -19), (59, 60, -35), (64, 56, -42)])
    body += _path("M47 57 L51 61 48 66 44 62Z", "url(#gold)", width=1.0)
    body += _path("M58 56 L65 58 67 78 61 75 59 81 55 61Z", "#67526f", width=1.5)
    body += _etch("M61 60 L63 72 M59 65 L62 68", "#ba9ab4", .9)
    body += _path("M18 67 L23 65 27 70 24 75 19 75 16 71Z M73 66 L78 67 80 72 77 75 72 73 70 70Z", "url(#bone)", width=1.4)
    body += _etch("M20 69 L22 72 M75 69 L76 72", "#8e7d68", .8)
    return body


def _chaser() -> str:
    body = '<defs>' + _gradient("sp-chaser-cloth", "#a8bbb0", "#5e7c80", "#263847") + '</defs>'
    body += _ellipse(32, 56, 20, 4, "#030810", 'opacity=".38"')
    body += _path("M18 28 L10 30 5 39 13 37 8 47 17 43 19 35Z M45 28 L52 30 57 38 51 37 60 47 48 43 43 35Z", "#45646f", width=1.8)
    body += _path("M31 6 Q20 7 15 20 L15 33 10 47 20 43 18 55 27 49 31 60 37 48 46 56 43 43 54 48 48 32 47 20 40 9Z", "url(#sp-chaser-cloth)", width=2.2)
    # Broad torn strips read as cloth even when this spirit is only 36px tall.
    body += _path("M21 18 Q27 9 36 11 L30 23 24 32 25 42 21 49 22 35 17 40 19 28Z", "#bac7b8", width=0)
    body += _path("M39 14 L44 22 43 34 48 43 40 40 42 49 36 43 33 53 30 45 34 32Z", "#324c59", width=0)
    body += _path("M27 37 L31 42 29 51 25 47Z M38 37 L41 44 37 42 35 47Z", "#102631", width=0)
    body += _path("M25 19 L32 14 40 18 42 26 38 35 32 40 26 32 23 26Z", "#152934", "#9caf9f", 1.0)
    body += _path("M28 21 L32 18 37 21 38 27 35 33 32 36 28 31 26 25Z", "url(#bone)", width=1.1)
    body += _path("M33 20 L37 22 37 27 34 32 32 35 33 28Z", "#a3aa97", width=0)
    body += _path("M27 24 L31 23 30 28 27 27Z M34 23 L38 24 36 28 34 27Z", "#122735", width=0)
    body += _path("M31 29 L34 29 34 34 32 36 30 33Z", "#122735", width=0)
    body += _etch("M19 29 L21 33 M17 42 L20 39 M41 34 L39 39 M28 41 L27 45 M36 45 L34 51", "#b1c1af", 1.1, 'opacity=".65"')
    body += _path("M11 36 L15 33 13 39Z M48 35 L53 39 49 40Z", "#9eafa2", width=0)
    return body


def _rusher() -> str:
    body = '<defs>' + _gradient("sp-rusher-hide", "#897381", "#584454", "#28283b") + '</defs>'
    body += _ellipse(32, 55, 25, 4, "#030711", 'opacity=".58"')
    body += _path("M22 30 L12 31 5 41 4 52 12 50 18 41 26 40 M42 30 L52 31 59 41 60 52 52 50 46 41 38 40", "url(#sp-rusher-hide)", width=2.5)
    body += _path("M11 35 L17 34 12 43 7 46 8 41Z M48 34 L53 36 57 43 53 45 49 41Z", "#9a8590", width=0)
    body += _path("M12 42 L17 40 14 46 10 49Z M47 40 L52 42 54 49 50 46Z", "#383143", width=0)
    body += _path("M17 30 L17 16 23 20 26 11 32 20 39 12 44 22 50 17 47 32 50 42 40 49 24 49 14 41Z", "url(#sp-rusher-hide)", width=2.5)
    body += _path("M18 25 L17 12 25 22 M40 23 L49 13 46 28", "url(#bone)", width=1.5)
    body += _path("M18 33 L23 24 31 21 42 26 46 34 42 42 35 48 29 48 21 41Z", "url(#bone)", width=1.8)
    body += _path("M33 24 L41 28 43 34 38 40 34 47 31 47 31 36Z", "#a49781", width=0)
    body += _path("M21 29 L29 31 26 36 21 34Z M35 31 L43 28 41 35 36 37Z", "#282333", width=0)
    body += _etch("M21 28 L28 30 M36 30 L42 27", "#f1e3c3", 1.35)
    body += _path("M29 37 L34 37 35 41 31 43 28 40Z", "#272331", width=0)
    body += _path("M22 37 L27 40 26 44 22 41Z M37 40 L42 36 41 41 37 44Z", "#ded0b3", width=0)
    body += _path("M26 42 L27 48 30 44 M33 44 L36 48 38 42", "#e8d9b9", width=1.1)
    body += _etch("M31 23 L29 27 32 30 M39 26 L38 28", "#7d7167", .9)
    # Each forelimb ends in two pale blades with a dark gap between them.
    body += _path("M6 45 L4 56 9 52 11 44Z M12 45 L12 56 17 49 17 43Z M53 45 L55 56 50 52 48 44Z M47 45 L47 56 42 49 42 43Z", "url(#bone)", width=1.3)
    body += _etch("M8 46 L6 52 M14 47 L14 51 M51 46 L53 52 M45 47 L45 51", "#b6a58c", .8)
    body += _etch("M19 24 L23 27 M43 24 L45 29 M19 42 L23 45 M39 46 L44 41", "#a58a96", 1.1)
    return body


def _tank() -> str:
    body = '<defs>' + _gradient("sp-tank-plate", "#89929b", "#465567", "#202d40") + '</defs>'
    body += _ellipse(40, 71, 31, 5, "#030711", 'opacity=".65"')
    body += _path("M23 54 L19 70 32 73 37 57 M45 57 L49 73 62 70 57 53", "#1a2536", width=2.7)
    body += _path("M18 24 L7 29 5 48 14 59 27 50 28 30Z M62 24 L73 29 75 48 66 59 53 50 52 30Z", "url(#sp-tank-plate)", width=2.7)
    body += _path("M8 32 L16 28 24 32 22 39 9 42Z M64 28 L72 32 71 42 58 39 56 32Z", "#788491", "#b3b8b6", 1.1)
    body += _path("M8 44 L20 41 21 46 14 55 9 50Z M60 41 L72 44 71 50 66 55 59 46Z", "#39495d", "#8e999f", 1.0)
    body += _path("M11 48 L16 47 14 51 11 52Z M65 47 L69 48 68 52 65 51Z", "#a28b68", width=0)
    body += _path("M25 22 L55 22 63 31 65 46 58 63 40 73 22 63 15 46 17 31Z", "url(#sp-tank-plate)", width=2.8)
    # Large overlapping plates carry the material; the engraving stays sparse.
    body += _path("M23 31 L40 25 57 31 58 46 51 55 40 61 29 55 22 46Z", "#303f53", "#a4abae", 1.7)
    body += _path("M24 32 L39 28 37 42 29 51 24 45Z", "#7e8b97", width=0)
    body += _path("M42 28 L55 33 56 45 50 52 41 58Z", "#202d42", width=0)
    body += _path("M24 52 L40 60 56 52 54 59 40 67 26 60Z", "#425269", "#8d999f", 1.2)
    body += _path("M26 61 L40 68 54 61 51 66 40 72 29 67Z", "#2b3b51", "#6f7e8b", 1.0)
    body += _etch("M26 35 L28 45 32 49 M52 35 L50 45 47 49 M28 55 L37 60", "#9ba7ad", 1.1)
    body += _path("M38 34 L42 34 42 41 47 45 42 49 42 55 38 55 38 49 33 45 38 41Z", "#a48d69", "#1c2739", 1.2)
    body += _etch("M39 38 L39 44 M39 51 L39 54", "#ddc498", .9)
    body += _path("M26 25 L27 14 34 7 47 7 55 16 54 27 47 34 33 34Z", "url(#sp-tank-plate)", width=2.6)
    body += _path("M30 16 L38 11 48 13 52 20 49 28 33 28Z", "#344255", "#a2a8ad", 1.2)
    body += _path("M30 16 L38 11 39 19 32 20Z M42 13 L48 14 51 19 43 18Z", "#7b8995", width=0)
    body += _path("M31 20 L51 19 49 24 33 24Z", "#0d1828", width=0)
    body += _etch("M36 22 L44 22", "#c6ae7d", 1.2)
    body += _path("M36 25 L44 25 43 32 38 32Z", "#516173", "#98a3aa", .9)
    body += _etch("M40 11 L40 19 M39 26 L39 30 M20 28 L23 27 M59 27 L62 28", "#bac0c0", 1.1)
    for x, y in [(24, 35), (55, 35), (29, 54), (51, 54)]:
        body += _ellipse(x, y, 1.35, 1.35, "#b4aa91")
        body += _ellipse(x + .35, y + .4, .6, .6, "#5a6269")
    body += _etch("M30 37 L32 39 M48 43 L49 40 M32 58 L34 59", "#243246", 1.0)
    body += _path("M29 64 L33 66 30 68 27 66Z M49 66 L53 64 54 66 51 68Z", "#bfa87b", width=0)
    return body


def _caster() -> str:
    body = '<defs>' + _gradient("sp-caster-robe", "#8d758a", "#5c445f", "#28283d") + '</defs>'
    body += _ellipse(35, 64, 25, 4, "#030711", 'opacity=".55"')
    body += _path("M24 32 L42 32 48 45 52 63 42 61 35 68 26 61 14 64 18 46Z", "url(#sp-caster-robe)", width=2.5)
    body += _path("M25 39 L30 44 27 57 21 61 19 61Z", "#8a7087", width=0)
    body += _path("M31 43 L34 47 31 60 28 61Z M38 43 L42 37 46 59 39 64Z", "#342a41", width=0)
    body += _etch("M23 46 L19 58 M43 47 L47 59 M31 50 L30 58 M39 52 L40 60", "#b29aa4", 1.0, 'opacity=".58"')
    body += _path("M23 34 L15 38 10 50 19 53 28 42 M42 34 L49 38 58 35 61 42 50 47 41 43Z", "url(#sp-caster-robe)", width=2)
    body += _path("M15 39 L20 40 15 49 12 49Z M45 38 L49 40 55 38 56 42 50 45 44 42Z", "#a38a9a", width=0)
    body += _path("M23 32 L23 21 32 6 41 13 45 28 43 37 34 44 23 37Z", "url(#sp-caster-robe)", width=2.4)
    body += _path("M24 22 L32 9 29 23 26 31 25 33Z", "#b098a7", width=0, extra='opacity=".48"')
    body += _path("M27 23 L33 15 40 25 40 33 34 38 27 33Z", "#151827", "#bca3ad", 1.0)
    body += _path("M29 24 L34 20 39 25 38 32 34 37 29 32Z", "url(#bone)", width=.8)
    body += _path("M29 26 L33 27 31 30 29 29Z M35 27 L38 26 37 30 35 30Z", "#272432", width=0)
    body += _path("M33 30 L35 32 32 33Z", "#665765", width=0)
    body += _etch("M31 34 L35 34 M33 34 L33 36", "#665765", .8)
    body += _path("M22 34 L33 41 44 34 45 40 35 48 25 41Z", "#a78c67", width=1.4)
    body += _etch("M25 36 L34 43 42 37", "#dec59a", 1.1)
    body += _path("M32 45 L36 45 40 60 35 65 29 60Z", "#50384e", "#baa17a", 1.0)
    body += _path("M33 48 L35 48 36 60 33 61Z", "#997d66", width=0)
    body += _etch("M32 59 L35 61 38 58", "#d8be91", 1.0)
    # An oversized skull makes the staff readable before its engraved details.
    body += _etch("M59 64 L58 29 60 19", "#1a1e2b", 5.1)
    body += _etch("M59 63 L58 29 60 19", "#9d8b6e", 3.0)
    body += _etch("M58 61 L57 31", "#d0b993", .8)
    body += _path("M52 15 L55 10 63 10 68 15 66 23 63 25 63 29 56 29 54 25 51 22Z", "url(#bone)", width=1.7)
    body += _path("M61 12 L66 16 64 22 62 23 61 28 58 28 59 20Z", "#aea087", width=0)
    body += _path("M53 17 L58 16 57 22 53 21Z M61 16 L66 17 64 22 60 22Z", "#302a38", width=0)
    body += _path("M59 22 L61 25 57 25Z", "#564555", width=0)
    body += _etch("M56 26 L61 26 M58 26 L58 29 M61 26 L61 29 M57 33 L61 33 M57 36 L61 36", "#716054", .8)
    body += _path("M55 30 L64 30 65 33 55 33Z", "#9d815b", width=1.0)
    body += _path("M55 37 L59 36 62 39 60 43 56 43 53 40Z M13 48 L17 47 20 50 18 54 13 53Z", "url(#bone)", width=1.1)
    return body


def _boss() -> str:
    body = '<defs>' + _gradient("sp-boss-vestment", "#75657a", "#3d374f", "#171c2d")
    body += _gradient("sp-boss-crown", "#e8cf9f", "#aa8050", "#49372c") + '</defs>'
    body += _ellipse(80, 146, 51, 8, "#03060e", 'opacity=".66"')
    body += '<ellipse cx="80" cy="47" rx="48" ry="35" fill="none" stroke="#958365" stroke-width="1.3" opacity=".35"/>'
    # Architectural pleats and detached hands give the boss its own silhouette.
    body += _path("M51 66 L38 79 31 103 42 102 35 140 52 136 64 151 80 143 96 151 109 136 126 140 119 101 130 103 122 79 109 66Z", "url(#sp-boss-vestment)", width=3.7)
    body += _path("M50 80 L60 87 54 127 62 143 47 132 43 133Z M109 80 L101 88 106 127 98 144 113 132 119 134Z", "#22263a", width=0)
    body += _path("M48 88 L54 93 48 123 51 132 44 130Z M108 88 L114 94 118 126 112 123Z", "#8c7588", width=0, extra='opacity=".65"')
    body += _path("M64 88 L79 96 96 87 104 128 94 143 80 139 67 145 57 128Z", "#484054", "#948092", 1.3)
    body += _path("M65 89 L76 98 73 132 67 140 60 126Z", "#806879", width=0)
    body += _path("M84 99 L96 89 101 126 94 139 85 132Z", "#292b40", width=0)
    body += _path("M64 96 L68 99 63 126 68 135 65 139 59 127Z M93 97 L97 94 102 126 96 138 92 137 98 125Z", "#a18c72", width=0)
    body += _path("M63 116 L66 107 68 118 64 123Z M94 113 L97 107 99 118 95 124Z", "#514254", width=0)
    body += _etch("M46 98 L42 123 M114 98 L119 124 M73 106 L71 129 M88 106 L91 129 M73 141 L80 137 88 140", "#938090", 1.5)
    body += _etch("M47 134 L52 132 62 145 M98 145 L109 132 118 135", "#aa9473", 1.5)
    body += _path("M48 67 L49 49 60 40 79 35 99 40 112 50 112 69 97 83 65 84Z", "url(#sp-boss-vestment)", width=3.2)
    body += _path("M58 54 Q63 41 80 40 Q99 42 103 55 L100 70 84 85 65 75Z", "#101626", "#99868f", 1.3)
    body += _path("M66 47 Q80 37 94 47 L94 65 87 78 80 83 70 74 65 61Z", "url(#bone)", width=2.1)
    body += _path("M81 43 L93 48 92 64 86 77 81 81 83 63Z", "#b2a58d", width=0)
    body += _path("M68 48 L77 43 73 58 70 67 67 60Z", "#efe3c7", width=0)
    body += _etch("M80 47 L78 59 82 65 79 76 M86 53 L88 57", "#8d7c6d", 1.0)
    body += _path("M39 68 L56 71 69 82 80 88 92 82 105 71 122 68 115 86 99 91 81 103 61 92 45 86Z", "url(#sp-boss-crown)", width=2.1)
    body += _path("M46 73 L59 77 69 87 81 94 95 87 106 77 115 73 111 82 96 87 81 99 65 87 50 82Z", "#4d382d", width=0)
    body += _etch("M46 71 L59 75 71 85 81 91 94 84 106 75 116 71", "#e4cda0", 1.3)
    body += _etch("M55 82 L61 83 M102 83 L108 80 M67 88 L70 91 M93 90 L97 87", "#c6a879", 1.0)
    body += _path("M77 100 L85 100 90 126 81 138 71 126Z", "url(#sp-boss-crown)", width=1.8)
    body += _path("M80 106 L84 114 81 129 77 121Z", "#493646", "#d8b98a", 1.0)
    body += _etch("M76 122 L80 125 86 119 M79 104 L84 104", "#e1c79b", 1.0)
    # Keep a real gap between the solid crown and the hood at runtime scale.
    body += _path("M43 25 L38 9 52 15 55 4 69 13 80 2 91 13 106 4 109 16 122 9 117 26 103 31 80 28 58 31Z", "url(#sp-boss-crown)", width=2.8)
    body += _path("M44 16 L55 23 59 13 69 22 80 11 91 22 103 13 106 23 117 17 113 24 102 27 80 24 59 27 47 23Z", "#5d4431", width=0)
    body += _etch("M43 12 L48 22 58 25 M57 7 L61 21 M80 6 L80 21 M104 7 L101 22 M118 13 L113 23 104 26", "#ead2a0", 1.3)
    body += _path("M76 19 L80 13 85 19 81 26Z", "#7c657d", "#e1c895", 1.0)
    body += _etch("M52 28 Q80 21 108 28", "#d1b17e", 1.2)
    # Floating palms have long jointed fingers and clear negative space at wrists.
    body += _path("M21 93 L13 87 9 90 15 99 8 96 5 100 15 108 12 113 18 119 27 116 32 108 30 98 26 91Z", "url(#bone)", width=2.2)
    body += _path("M139 93 L147 87 151 90 145 99 152 96 155 100 145 108 148 113 142 119 133 116 128 108 130 98 134 91Z", "url(#bone)", width=2.2)
    body += _path("M22 96 L27 99 27 107 22 114 17 111 19 106 16 100Z M138 96 L133 99 133 107 138 114 143 111 141 106 144 100Z", "#b1a28b", width=0)
    body += _etch("M14 92 L20 99 22 106 M10 100 L17 104 M25 95 L28 100 M146 92 L140 99 138 106 M150 100 L143 104 M135 95 L132 100", "#7f6d60", 1.1)
    body += _etch("M19 117 L28 113 M132 113 L141 117", "#d8bf8e", 2.3)
    body += _etch("M28 87 L32 83 M129 83 L133 87 M25 78 L23 74 M135 77 L137 73", "#9d8769", 1.5, 'opacity=".75"')
    return body


def generate(save_svg: SaveSvg) -> None:
    """Write only the six established sprite paths, with their existing pivots."""
    for name, size, author, role in [
        ("player", 96, _player, "ivory beaked mask, plum hood, broad matte cloth planes and dark folds, ritual chain; center anchor"),
        ("chaser", 64, _chaser, "torn blue-grey shroud, ivory hollow face and separated rag strips; center anchor"),
        ("rusher", 64, _rusher, "low plum-hide beast, angular bone face and paired jointed ivory claws; center anchor"),
        ("tank", 80, _tank, "shield-shaped iron guardian, overlapping steel plates and worn brass rivets; center anchor"),
        ("caster", 72, _caster, "plum cultist vestments, aged gold yoke and oversized carved skull staff; center anchor"),
        ("boss", 160, _boss, "detached aged-gold crown with broad lit planes and dark recesses, ivory faceless idol, long embroidered vestments and floating hands; center anchor"),
    ]:
        save_svg(f"sprites/{name}.svg", size, size, author(), role)


if __name__ == "__main__":
    from generate_assets import save_svg

    generate(save_svg)
