"""Original engraved occult icons and lightweight runtime FX, authored as SVG."""
from __future__ import annotations

from generate_assets import circle, ellipse, line, path, star


def generate(save_svg) -> None:
    icons: dict[str, str] = {}
    # A needle rather than a club: the long ivory point is readable at HUD scale.
    icons["bone"] = path("M12 55 L22 35 42 13 48 10 51 14 48 21 28 42Z", "url(#bone)", width=2)
    icons["bone"] += path("M16 51 L44 18 M24 36 L29 40", "none", "#fff1d0", 1.3)
    icons["bone"] += path("M37 11 Q33 6 39 5 L44 9 Q49 4 54 9 Q58 14 51 18 L46 21 40 17Z", "url(#bone)", width=1.8)
    icons["bone"] += path("M41 11 L45 13 M47 13 L50 11 M38 20 L45 26", "none", "#65534b", 1.5)
    icons["bone"] += path("M22 38 L28 32 M26 42 L32 36", "none", "#b5905e", 3)

    icons["frost"] = path("M32 3 L43 23 39 44 32 60 25 44 21 23Z", "#416a87", "#101e2b", 2)
    icons["frost"] += path("M32 3 L32 48 21 23Z", "#c1e8e7", "none", 0)
    icons["frost"] += path("M32 4 L43 23 32 31Z", "#7db5c5", "none", 0)
    icons["frost"] += path("M21 23 L32 31 43 23 M25 44 L32 37 39 44 M32 4V58", "none", "#d8f1e8", 1)
    icons["frost"] += path("M15 35 L21 40 16 46 M48 32 L43 39 49 44", "none", "#83b8c4", 1.4)
    icons["frost"] += star(49, 13, 6, "#deeee1") + star(13, 24, 3, "#8eafb8")

    icons["ember"] = path("M34 3 Q30 18 41 22 L43 13 Q55 28 51 42 Q48 57 32 61 Q12 57 12 41 Q12 28 24 17 L23 30 Q35 20 34 3Z", "#714351", width=2)
    icons["ember"] += path("M33 15 Q32 26 40 29 Q45 22 45 24 Q52 41 39 53 Q24 61 18 46 Q14 35 25 26 Q21 43 30 36 Q37 28 33 15Z", "url(#flame)", "none", 0)
    icons["ember"] += path("M32 35 Q38 40 36 46 Q35 50 31 54 Q23 47 29 42Z", "#fff0c2", "none", 0)
    icons["ember"] += path("M18 55 Q32 62 47 53 M22 59 L22 54 M42 59 L42 55", "none", "#c6a271", 1.4)

    icons["scatter"] = path("M32 4 L40 20 32 28 24 20Z M9 26 L22 31 24 44 14 43Z M55 26 L42 31 40 44 50 43Z", "url(#violet)", width=2)
    icons["scatter"] += path("M32 5V25 M10 27 L22 40 M54 27 L42 40", "none", "#edd0e8", 1.2)
    icons["scatter"] += path("M32 58V35 M23 52 L19 46 M41 52 L45 46", "none", "#b49ac8", 2)
    icons["scatter"] += path("M26 34 L32 30 38 34 37 49 32 55 27 49Z", "url(#gold)", width=1.6)
    icons["scatter"] += circle(32, 38, 3, "#3c2e48", "#e2c792", 1) + star(32, 38, 2, "#f3dfba")

    icons["pierce"] = path("M8 54 L48 14", "none", "#c6a472", 5)
    icons["pierce"] += path("M41 9 L56 7 54 22 48 14Z", "url(#bone)", width=1.8)
    icons["pierce"] += path("M8 31 L16 24 29 37 22 45Z M25 15 L32 8 45 21 38 29Z", "#3f354f", "#aa91bc", 1.7)
    icons["pierce"] += path("M12 35 L22 25 M29 19 L38 10 M13 50 L43 20", "none", "#ead6b1", 1.3)

    icons["bounce"] = path("M8 51 L24 27 41 41 54 13", "none", "#3f304f", 8)
    icons["bounce"] += path("M8 51 L24 27 41 41 54 13", "none", "#d6b7da", 2.5)
    icons["bounce"] += path("M43 14 L56 7 58 24 53 16Z", "url(#bone)", width=1.5)
    for x, y in [(24, 27), (41, 41)]:
        icons["bounce"] += circle(x, y, 6.5, "#292332", "#c09b67", 2) + star(x, y, 3, "#eee0b6")
    icons["bounce"] += path("M8 44 L5 50 10 55", "none", "#ba9dcb", 1.2)

    icons["blast"] = circle(32, 32, 21, "#332534", "#ae825f", 2) + circle(32, 32, 16, "none", "#d3a877", 1)
    icons["blast"] += path("M32 2 L37 22 56 9 43 27 63 32 43 37 55 55 37 43 32 63 27 43 8 55 21 37 1 32 21 27 9 9 27 21Z", "#bf827d", "#171421", 1.5)
    icons["blast"] += star(32, 32, 19, "#e4c699", 4) + star(32, 32, 10, "#fff0c7", 4) + circle(32, 32, 3, "#946278")

    icons["damage"] = path("M26 42 L38 13 52 6 52 22 34 49Z", "url(#steel)", width=2)
    icons["damage"] += path("M49 10 L32 42 M38 17 L43 24", "none", "#dce2db", 1.3)
    icons["damage"] += path("M17 35 L40 51 M23 43 L12 58", "none", "#81654b", 7)
    icons["damage"] += path("M17 34 L40 50 M22 44 L13 56", "none", "#dfc28f", 2)
    icons["damage"] += circle(12, 57, 3.5, "#cbaa73", "#211b24", 1.5) + star(50, 34, 4, "#b5a48f")

    icons["haste"] = path("M17 8 H47 M17 56 H47 M21 11 C21 26 42 36 42 53 M43 11 C43 26 22 36 22 53", "none", "#c8a66f", 3)
    icons["haste"] += path("M24 14 H40 Q40 24 32 28 Q24 24 24 14Z M24 51 Q26 43 32 39 Q38 43 40 51Z", "url(#violet)", "#514054", 1)
    icons["haste"] += path("M32 29V38 M18 10V54 M46 10V54", "none", "#e4d1aa", 1)
    icons["haste"] += path("M14 6H50 M14 58H50", "none", "#695442", 2)

    icons["speed"] = path("M29 9 L44 13 40 33 52 42 49 54 20 54 13 46 25 36Z", "url(#robe)", width=2)
    icons["speed"] += path("M21 48H48 M30 16 L40 19 M28 23 L39 26 M27 30 L37 32", "none", "#c7ae86", 1.8)
    icons["speed"] += path("M23 33 Q9 25 7 13 Q17 19 27 17 L25 23 15 20 23 27Z", "url(#bone)", width=1.4)
    icons["speed"] += path("M9 37H19 M5 44H13 M7 51H12", "none", "#a396af", 1.5)

    icons["vitality"] = path("M20 8 L44 8 49 15 49 48 42 58 22 58 15 48 15 15Z", "#302633", "#b39368", 2)
    icons["vitality"] += path("M32 49 Q20 39 21 29 Q23 22 29 26 L30 18 36 16 37 26 Q44 25 44 33 Q44 42 32 49Z", "url(#blood)", "#18121e", 1.5)
    icons["vitality"] += path("M29 21 L33 30 30 35 M36 27 L37 35 32 43 M18 18 L23 13 M41 13 L46 18", "none", "#d4a795", 1)
    icons["vitality"] += path("M19 46 L24 52H40 L45 46 M23 11H41", "none", "#dcc499", 1.2)

    icons["armor"] = path("M10 12 L32 5 54 12 51 35 Q45 52 32 60 Q17 51 13 35Z", "url(#steel)", width=2)
    icons["armor"] += path("M17 17 L32 12 47 17 45 33 Q41 45 32 52 Q23 46 19 33Z", "#263244", "#b7aa89", 1.4)
    icons["armor"] += path("M32 14V48 M24 27H40 M27 20 L32 16 37 20 36 34 32 40 28 34Z", "none", "#d2b57e", 1.5)
    for x, y in [(15, 14), (49, 14), (19, 37), (45, 37)]:
        icons["armor"] += circle(x, y, 1.5, "#e1c898")

    icons["magnet"] = path("M23 5 Q32 13 41 5 L43 18 37 23H27 L21 18Z", "url(#gold)", width=1.5)
    icons["magnet"] += circle(32, 36, 19, "#292c3f", "#b99b68", 2)
    icons["magnet"] += circle(32, 36, 14, "#3b3650", "#d2ba88", 1)
    icons["magnet"] += path("M32 21 L39 35 32 50 25 35Z", "url(#violet)", "#171521", 1.6)
    icons["magnet"] += star(32, 35, 7, "#e5d3bb") + path("M8 30 L4 35 8 40 M56 30 L60 35 56 40", "none", "#9d88b6", 1.5)

    icons["soul"] = path("M33 5 L46 24 43 45 31 59 20 47 17 27Z", "#3b7b82", "#142932", 2)
    icons["soul"] += path("M33 6 L31 42 17 27Z", "#a5d7c5", "none", 0)
    icons["soul"] += path("M33 6 L46 24 31 42Z", "#70b5b2", "none", 0)
    icons["soul"] += path("M31 42 L43 45 31 59Z", "#bddfc8", "none", 0)
    icons["soul"] += path("M20 47 L31 42 43 45 M23 25 L31 19 37 26 32 36Z", "none", "#d7eee0", 1.1)

    for name, body in icons.items():
        save_svg(f"icons/{name}.svg", 64, 64, body, f"engraved occult {name} icon; transparent; readable at 24–48px")

    glow = '<defs><radialGradient id="softlight"><stop stop-color="#fff3cf" stop-opacity=".65"/><stop offset=".2" stop-color="#d7b889" stop-opacity=".22"/><stop offset=".55" stop-color="#ad84ca" stop-opacity=".08"/><stop offset="1" stop-color="#ad84ca" stop-opacity="0"/></radialGradient></defs>'
    glow += circle(48, 48, 47, "url(#softlight)")
    save_svg("fx/glow.svg", 96, 96, glow, "soft radial light; runtime tint and opacity; cosmetic only")
    seal = circle(48, 48, 39, "none", "#ddcba0", 1, 'opacity=".55"') + circle(48, 48, 34, "none", "#bd9d75", .7, 'opacity=".3"')
    seal += path("M48 4 L53 15 48 23 43 15Z M48 92 L43 81 48 73 53 81Z M4 48 L15 43 23 48 15 53Z M92 48 L81 53 73 48 81 43Z", "#bda1c9", "#eee0c2", .7)
    seal += path("M21 21 L30 25 M75 21 L71 30 M75 75 L66 71 M21 75 L25 66", "none", "#cfb287", 2)
    save_svg("fx/seal.svg", 96, 96, seal, "player ground sigil; transparent; decorative, no collision")

    icon = '<rect width="256" height="256" rx="50" fill="#101521"/>' + circle(128, 127, 101, "none", "#786047", 2)
    icon += circle(128, 127, 93, "#252032", "#c6a16b", 3) + circle(128, 127, 85, "none", "#5d4860", 1)
    icon += path("M156 43 Q91 51 86 113 Q80 179 145 201 Q84 214 54 158 Q29 105 66 64 Q103 29 156 43Z", "url(#gold)", "none", 0)
    icon += '<g transform="translate(72 66) scale(1.8)">' + icons["ember"] + '</g>'
    icon += star(193, 58, 10, "#e4c796") + star(185, 192, 5, "#a78cb2")
    save_svg("icon.svg", 256, 256, icon, "application icon; engraved eclipse and ritual flame")


if __name__ == "__main__":
    from generate_assets import save_svg
    generate(save_svg)
