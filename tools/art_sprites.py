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
    body = '<defs>' + _gradient("sp-chaser-cloth", "#a9c0b9", "#66898a", "#293e4c") + '</defs>'
    body += _ellipse(32, 56, 20, 4, "#030810", 'opacity=".38"')
    body += _path("M18 28 Q10 31 8 39 L15 37 9 49 20 44 22 34Z M44 28 Q52 29 55 37 L51 38 59 47 47 43 41 36Z", "#4e717a", "#102330", 1.8)
    body += _path("M31 6 Q20 7 15 20 L15 34 11 47 22 43 21 55 29 48 31 60 37 48 45 56 43 43 53 48 48 32 47 20 40 9Z", "url(#sp-chaser-cloth)", "#102330", 2.2)
    body += _path("M21 18 Q27 9 36 11 L30 22 26 34 26 46 21 51 22 37 17 40 19 28Z", "#c5d2c4", width=0, extra='opacity=".46"')
    body += _path("M38 13 L44 22 43 35 48 43 40 40 42 50 35 43 33 52 31 44 34 32Z", "#3b5965", width=0)
    body += _path("M25 19 L32 14 40 18 42 26 38 35 32 40 26 32 23 26Z", "#19303c", "#9fb8ad", 1.0)
    body += _path("M27 22 L31 19 29 29 26 27Z M35 19 L39 21 36 29 34 27Z", "#d1ddc2", width=0)
    body += _path("M31 31 L34 29 34 36 31 38 30 34Z", "#0a1d29", width=0)
    body += _etch("M19 31 L22 37 18 44 M41 34 L38 42 M29 42 L27 49 M35 45 L34 51", "#b4c9bb", 1.05, 'opacity=".70"')
    body += _path("M14 43 L18 39 16 47Z M45 40 L49 43 46 46Z", "#0f2834", width=0)
    body += _etch("M22 14 L24 12 M43 16 L44 19", "#d2dbc6", 1.0)
    return body


def _rusher() -> str:
    body = '<defs>' + _gradient("sp-rusher-hide", "#966b6b", "#61434f", "#302b40") + '</defs>'
    body += _ellipse(32, 55, 25, 4, "#030711", 'opacity=".58"')
    body += _path("M22 30 L12 32 5 43 4 53 12 50 17 43 26 40 M42 30 L52 32 59 43 60 53 52 50 47 43 38 40", "url(#sp-rusher-hide)", width=2.5)
    body += _path("M17 30 L17 16 23 20 26 11 32 20 39 12 44 22 50 17 47 32 50 42 40 49 24 49 14 41Z", "url(#sp-rusher-hide)", width=2.5)
    body += _path("M18 24 L18 13 25 23 M40 23 L48 14 46 28", "#a39b8c", width=1.5)
    body += _path("M18 34 L23 25 31 22 42 27 46 35 39 45 31 49 22 42Z", "url(#bone)", width=1.8)
    body += _path("M32 24 L41 29 42 37 35 43 33 49 29 43 31 37Z", "#a09380", width=0)
    body += _path("M21 29 L29 32 25 36 21 34Z M35 32 L42 29 40 35 36 37Z", "#312634", width=0)
    body += _etch("M23 31 L26 32 M37 33 L40 31", "#ad756d", 1)
    body += _path("M29 38 L34 38 35 42 31 44 28 41Z", "#2d2634", width=0)
    body += _path("M25 43 L26 48 29 45 M34 46 L36 49 38 42", "#e1d0b0", width=1.1)
    body += _path("M7 45 L6 55 10 50 10 43 M12 45 L12 55 16 48 M53 45 L54 55 50 50 50 43 M48 45 L48 55 44 48", "url(#bone)", width=1.2)
    body += _etch("M11 38 L16 36 M49 36 L54 40 M21 24 L24 26 M42 25 L44 29", "#bb8b80", 1.1)
    body += _etch("M20 42 L25 46 M39 47 L44 42", "#402d3b", 1.2)
    return body


def _tank() -> str:
    body = '<defs>' + _gradient("sp-tank-plate", "#7d899a", "#455467", "#243246") + '</defs>'
    body += _ellipse(40, 71, 31, 5, "#030711", 'opacity=".65"')
    body += _path("M23 54 L19 70 32 73 37 57 M45 57 L49 73 62 70 57 53", "#1a2536", width=2.7)
    body += _path("M18 24 L7 29 5 48 14 59 27 50 28 30Z M62 24 L73 29 75 48 66 59 53 50 52 30Z", "url(#sp-tank-plate)", width=2.7)
    body += _path("M9 32 L16 29 23 32 20 45 11 49Z M64 30 L71 33 69 48 60 45 57 33Z", "#59677b", "#a0a6ac", 1.0)
    body += _path("M25 22 L55 22 63 31 65 46 58 63 40 73 22 63 15 46 17 31Z", "url(#sp-tank-plate)", width=2.8)
    body += _path("M23 31 L40 25 57 31 58 46 52 58 40 66 28 58 22 46Z", "#303f53", "#a4a7a5", 1.7)
    body += _path("M24 32 L39 28 37 42 27 55 24 46Z", "#6d7a8b", width=0)
    body += _path("M42 28 L55 33 56 45 51 57 41 64Z", "#222e43", width=0)
    body += _etch("M26 35 L28 46 32 50 M52 35 L50 47 46 51 M29 58 L40 65 51 58", "#788390", 1.2)
    body += _path("M38 35 L42 35 42 43 46 46 42 49 42 57 38 57 38 49 34 46 38 43Z", "#a48d69", "#1c2739", 1.2)
    body += _etch("M39 38 L39 44 M39 51 L39 54", "#ddc498", .9)
    body += _path("M26 25 L27 14 34 7 47 7 55 16 54 27 47 34 33 34Z", "url(#sp-tank-plate)", width=2.6)
    body += _path("M30 16 L38 11 48 13 52 20 49 28 33 28Z", "#344255", "#a2a8ad", 1.2)
    body += _path("M31 20 L51 19 49 24 33 24Z", "#0d1828", width=0)
    body += _etch("M36 22 L44 22", "#c6ae7d", 1.2)
    body += _etch("M40 11 L40 19 M39 25 L39 31 M20 28 L23 27 M59 27 L62 28", "#bac0c0", 1.1)
    body += _path("M29 64 L33 66 30 68 27 66Z M49 66 L53 64 54 66 51 68Z", "#bfa87b", width=0)
    return body


def _caster() -> str:
    body = '<defs>' + _gradient("sp-caster-robe", "#8d6c78", "#654553", "#2e2b40") + '</defs>'
    body += _ellipse(35, 64, 25, 4, "#030711", 'opacity=".55"')
    body += _path("M24 32 L42 32 48 45 52 63 42 61 35 68 26 61 14 64 18 46Z", "url(#sp-caster-robe)", width=2.5)
    body += _path("M26 38 L32 43 29 58 23 61 20 60Z M37 43 L42 37 45 60 38 64Z", "#3b2c3e", width=0)
    body += _etch("M23 46 L19 58 M43 47 L47 59 M31 49 L31 60 M37 51 L39 60", "#b2948e", 1.0, 'opacity=".66"')
    body += _path("M23 34 L15 38 10 50 19 53 28 42 M42 34 L49 38 58 35 61 42 50 47 41 43Z", "url(#sp-caster-robe)", width=2)
    body += _path("M23 32 L23 21 32 6 41 13 45 28 43 37 34 44 23 37Z", "url(#sp-caster-robe)", width=2.4)
    body += _path("M27 23 L33 15 40 25 40 33 34 38 27 33Z", "#151827", "#c1a19b", 1.0)
    body += _path("M30 23 L34 20 38 25 37 33 33 36 29 31Z", "#a99b8c", width=0)
    body += _path("M29 26 L33 27 30 29Z M35 27 L38 26 37 30 35 30Z", "#272432", width=0)
    body += _etch("M33 30 L33 33 M29 35 L32 37", "#695766", .8)
    body += _path("M24 37 L33 43 43 36 42 42 35 48 27 43Z", "#b18b66", width=1.2)
    body += _path("M32 45 L36 45 39 59 35 64 30 59Z", "#533745", "#b69b75", 1.0)
    body += _etch("M34 49 L36 54 34 57 M33 59 L36 60", "#d1b58b", .9)
    # An oversized skull makes the staff readable before its engraved details.
    body += _etch("M59 64 L58 29 60 19", "#1a1e2b", 5.1)
    body += _etch("M59 63 L58 29 60 19", "#9d8b6e", 3.0)
    body += _etch("M58 61 L57 31", "#d0b993", .8)
    body += _path("M53 16 L56 11 63 11 67 16 65 23 62 24 62 29 56 28 55 24 52 22Z", "url(#bone)", width=1.7)
    body += _path("M54 17 L58 16 57 21 54 21Z M61 16 L65 17 63 22 60 21Z", "#352e3b", width=0)
    body += _path("M59 21 L61 24 58 24Z", "#564555", width=0)
    body += _etch("M57 25 L57 27 M60 25 L60 28 M57 34 L61 34 M57 38 L61 38", "#716054", .8)
    body += _path("M55 37 L59 36 62 39 60 43 56 43 53 40Z M13 48 L17 47 20 50 18 54 13 53Z", "url(#bone)", width=1.1)
    return body


def _boss() -> str:
    body = '<defs>' + _gradient("sp-boss-vestment", "#66586e", "#353247", "#171c2d")
    body += _gradient("sp-boss-crown", "#ddc492", "#a78b64", "#66503f") + '</defs>'
    body += _ellipse(80, 146, 51, 8, "#03060e", 'opacity=".66"')
    body += '<ellipse cx="80" cy="47" rx="48" ry="35" fill="none" stroke="#958365" stroke-width="1.3" opacity=".35"/>'
    # Architectural pleats and detached hands give the boss its own silhouette.
    body += _path("M51 66 L38 79 31 103 42 102 35 140 52 136 64 151 80 143 96 151 109 136 126 140 119 101 130 103 122 79 109 66Z", "url(#sp-boss-vestment)", width=3.7)
    body += _path("M50 80 L60 87 54 127 62 143 47 132 43 133Z M109 80 L101 88 106 127 98 144 113 132 119 134Z", "#22263a", width=0)
    body += _path("M64 88 L79 96 96 87 104 128 94 143 80 139 67 145 57 128Z", "#484054", "#807084", 1.3)
    body += _path("M65 89 L76 98 73 132 67 140 60 126Z", "#655363", width=0)
    body += _path("M84 99 L96 89 101 126 94 139 85 132Z", "#292b40", width=0)
    body += _etch("M46 98 L42 123 M114 98 L119 124 M62 103 L59 125 M99 103 L103 125 M73 141 L80 137 88 140", "#7a6c7e", 1.5)
    body += _path("M48 67 L49 47 58 34 79 25 100 34 112 48 112 69 97 83 65 84Z", "url(#sp-boss-vestment)", width=3.2)
    body += _path("M58 52 Q63 34 80 32 Q99 36 103 53 L100 70 84 85 65 75Z", "#101626", "#99868f", 1.3)
    body += _path("M66 47 Q80 37 94 47 L94 65 87 78 80 83 70 74 65 61Z", "url(#bone)", width=2.1)
    body += _path("M81 43 L93 48 92 64 86 77 81 81 83 63Z", "#b2a58d", width=0)
    body += _path("M68 48 L77 43 73 58 70 67 67 60Z", "#efe3c7", width=0)
    body += _etch("M80 47 L78 59 82 65 79 76 M86 53 L88 57", "#8d7c6d", 1.0)
    body += _path("M39 68 L56 71 69 82 80 88 92 82 105 71 122 68 115 86 99 91 81 103 61 92 45 86Z", "url(#sp-boss-crown)", width=2.1)
    body += _path("M46 73 L59 77 69 87 81 94 95 87 106 77 115 73 111 82 96 87 81 99 65 87 50 82Z", "#69503f", width=0)
    body += _etch("M46 71 L59 75 71 85 81 91 94 84 106 75 116 71", "#e4cda0", 1.3)
    body += _etch("M55 82 L61 83 M102 83 L108 80 M67 88 L70 91 M93 90 L97 87", "#c6a879", 1.0)
    body += _path("M77 100 L85 100 90 126 81 138 71 126Z", "url(#sp-boss-crown)", width=1.8)
    body += _path("M80 106 L84 114 81 129 77 121Z", "#493646", "#d8b98a", 1.0)
    body += _etch("M76 122 L80 125 86 119 M79 104 L84 104", "#e1c79b", 1.0)
    # Crown peaks are solid mass, rather than a thin halo lost at small scale.
    body += _path("M43 37 L38 15 52 22 55 8 69 19 80 4 91 19 106 8 109 23 122 15 117 38 103 45 80 42 58 45Z", "url(#sp-boss-crown)", width=2.8)
    body += _path("M44 24 L55 30 59 19 69 28 80 15 91 28 103 19 106 31 117 25 113 35 102 40 80 37 59 40 47 35Z", "#756047", width=0)
    body += _etch("M43 18 L48 32 59 36 M57 12 L61 29 M80 8 L80 31 M104 12 L101 30 M118 19 L113 33 103 36", "#ead2a0", 1.3)
    body += _path("M76 29 L80 23 85 29 81 36Z", "#7c657d", "#e1c895", 1.0)
    body += _etch("M51 40 Q80 32 109 40", "#d1b17e", 1.2)
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
        ("chaser", 64, _chaser, "tattered pursuing spirit; center anchor"),
        ("rusher", 64, _rusher, "low angular claw beast; center anchor"),
        ("tank", 80, _tank, "heavy shield-shaped iron guardian; center anchor"),
        ("caster", 72, _caster, "ceremonial robed cultist and skull staff; center anchor"),
        ("boss", 160, _boss, "crowned faceless idol with detached floating hands; center anchor"),
    ]:
        save_svg(f"sprites/{name}.svg", size, size, author(), role)


if __name__ == "__main__":
    from generate_assets import save_svg

    generate(save_svg)
