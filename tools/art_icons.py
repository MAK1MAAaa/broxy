"""Original engraved occult icons and lightweight runtime FX, authored as SVG."""
from __future__ import annotations

from generate_assets import circle, ellipse, line, path, star


def _return_ring() -> str:
    body = '<defs><linearGradient id="return_ring_bone" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#edf1e5"/><stop offset=".45" stop-color="#c6d5cf"/><stop offset="1" stop-color="#718692"/></linearGradient></defs>'
    for angle in [0, 120, 240]:
        body += f'<g transform="translate(32 32) rotate({angle})">'
        body += path("M-18 -16 Q-4 -28 12 -22 L18 -14 10 -7 11 -13 Q1 -15 -10 -9 L-16 -11 -12 -15Z", "url(#return_ring_bone)", width=2)
        body += path("M-12 -15 Q-1 -20 12 -18 L11 -13 Q1 -15 -10 -9 L-16 -11Z", "#81969b", "none", 0)
        body += path("M-14 -17 Q-2 -24 10 -21 L14 -16", "none", "#f2f3e7", 1.3)
        body += path("M-13 -14 L-8 -17 -5 -14 M11 -13 L14 -15", "none", "#5a727e", 1)
        body += path("M-4 -23 L2 -23 3 -18 -3 -17Z", "url(#gold)", "#3f4147", 1)
        body += line(-1, -22, 0, -19, "#f1dba6", .8)
        body += '</g>'
    return body


def _blood_pact() -> str:
    body = '<defs><linearGradient id="blood_pact_leather" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#795d6c"/><stop offset=".45" stop-color="#4c384e"/><stop offset="1" stop-color="#282a3c"/></linearGradient></defs>'
    body += path("M17 10 L44 5 53 13 51 53 22 59 12 51 13 16Z", "#272432", width=2.1)
    body += path("M43 10 L51 14 49 51 44 55Z", "url(#bone)", "#786b5c", 1.2)
    body += path("M15 11 L43 7 48 13 45 53 20 58 12 50 13 17Z", "url(#blood_pact_leather)", width=1.8)
    body += path("M15 12 L21 14 18 55 13 50 13 18Z", "#332e42", "#a28685", 1)
    body += path("M23 18 L40 15 41 44 22 48Z", "none", "#aa916b", 1.1)
    body += path("M24 23 L37 21 M24 27 L35 25 M23 31 L32 29", "none", "#b9a08c", 1, 'opacity=".65"')
    body += path("M16 12 L24 11 23 16 16 18Z M39 9 L44 8 47 13 42 15Z M13 45 L19 47 18 54 13 50Z", "url(#gold)", "#3f3440", 1)
    body += path("M28 45 L27 59 32 55 37 58 36 45Z", "#713e4b", "#281f2e", 1.1)
    body += path("M25 35 L31 32 38 35 40 42 35 49 28 48 23 41Z", "url(#gold)", "#302731", 1.6)
    body += path("M27 37 L31 35 36 37 37 42 33 46 28 44Z", "#b49668", "#ead09b", .8)
    body += path("M31 37 L35 40 32 44 28 41Z", "#673c4a", "#47303f", .8)
    body += line(46, 22, 49, 21, "#6c6057", .7)
    body += line(46, 26, 49, 25, "#6c6057", .7)
    return body


def _grave_candle() -> str:
    body = path("M28 53 H36 L41 59 H23Z", "url(#gold)", width=1.8)
    body += ellipse(32, 46, 20, 4, "#514638", 'stroke="#b69b6b" stroke-width="1.3"')
    body += path("M27 29 Q32 26 37 29 V49 Q32 52 27 49Z", "url(#bone)", "#5b5149", 1.4)
    body += path("M34 30 L37 29 V48 L34 49Z", "#98aaa3", "none", 0)
    body += path("M27 32 Q30 35 30 31 V39 Q33 42 33 35 V30", "none", "#f1e9ce", 1.2)
    body += path("M13 46 Q32 53 51 46 L47 53 Q32 60 17 53Z", "url(#gold)", width=1.8)
    body += path("M17 48 Q32 55 47 48 M26 54 H38", "none", "#e3c994", 1)
    body += path("M22 50 L24 53 M40 53 L42 50", "none", "#6f5c46", 1)
    body += ellipse(32, 29, 5, 1.7, "#e3dbc0")
    body += line(32, 29, 32, 25, "#4d4543", 1)
    body += path("M33 4 Q34 12 41 15 Q45 21 39 27 Q34 32 27 27 Q19 23 23 16 Q28 11 28 7 L29 17 Q34 13 33 4Z", "#365f70", width=1.7)
    body += path("M32 11 Q31 19 36 18 Q41 22 36 26 Q28 31 25 23 Q25 19 29 17 L29 22 Q33 20 32 11Z", "#9dd2c9", "none", 0)
    body += path("M32 17 L36 22 32 27 28 22Z", "#e5eee0", "#709c9d", .8)
    return body


def _fold_clasp() -> str:
    body = path("M16 7 L47 12 51 53 18 58 11 47Z", "url(#robe)", "#080c16", 2)
    body += path("M17 10 L24 14 22 53 18 55 14 46Z M43 15 L47 17 49 50 43 52Z", "#182130", "#596477", 1)
    body += path("M13 20 L29 15 35 22 27 32 30 39 16 45 10 36Z", "url(#steel)", "#0d1522", 1.8)
    body += path("M51 19 L35 24 29 33 37 42 48 46 55 35Z", "url(#bone)", "#18212b", 1.8)
    body += path("M16 23 L27 19 30 22 22 32 25 37 17 40 14 35Z", "#263346", "#aebdbd", 1)
    body += path("M47 24 L37 27 34 32 40 38 47 41 51 34Z", "#3a4a53", "#cbd6c7", 1)
    body += path("M30 19 L35 23 28 33 35 40 31 45", "none", "#e7c88f", 2)
    body += path("M20 10 L25 11 M38 13 L43 14 M22 52 L27 53 M37 51 L43 50", "none", "#c2a276", 1.2)
    body += circle(17, 26, 1.5, "#e6c58d") + circle(46, 35, 1.5, "#e6c58d")
    return body


def _echo_stone() -> str:
    body = path("M28 4 L36 4 40 12 37 17H27 L24 12Z M27 48H37 L41 56 36 60H28 L23 56Z", "url(#gold)", "#15202a", 1.5)
    body += path("M20 11 C5 18 5 46 20 53 M44 11 C59 18 59 46 44 53", "none", "#15202a", 7)
    body += path("M20 11 C5 18 5 46 20 53 M44 11 C59 18 59 46 44 53", "none", "#b6bdac", 2.8)
    body += path("M23 18 C14 24 14 40 23 46 M41 18 C50 24 50 40 41 46", "none", "#72999c", 1.8)
    body += path("M25 21 L34 16 43 27 40 42 30 49 22 38 21 28Z", "#263b49", "#d3d8bc", 1.6)
    body += path("M25 22 L34 18 32 33 22 29Z", "#c0dacc", "none", 0)
    body += path("M34 18 L41 28 32 33Z", "#7bb5b0", "none", 0)
    body += path("M22 30 L32 34 30 47 23 38Z", "#608d95", "none", 0)
    body += path("M32 34 L40 29 38 41 30 47Z", "#3d6276", "none", 0)
    body += path("M26 27 L32 25 36 29 33 36 27 37 29 32Z", "none", "#e8e6c9", 1.2)
    body += path("M12 29 L9 32 12 35 M52 29 L55 32 52 35", "none", "#dbbd88", 1.5)
    return body


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

    # Each new family has a separate silhouette, rather than a recolored old icon.
    icons["crescent"] = path("M17 57 L37 18", "none", "#191d2a", 8)
    icons["crescent"] += path("M17 57 L37 18", "none", "#b49b76", 4)
    icons["crescent"] += path("M45 5 Q15 7 9 31 Q5 48 17 54 Q9 38 23 25 Q35 13 54 17 L48 11Z", "url(#steel)", "#101c29", 2)
    icons["crescent"] += path("M44 7 Q17 13 13 34 Q13 26 25 20 Q36 13 50 15", "none", "#c9e7df", 2)
    icons["crescent"] += path("M30 26 L41 31 M28 31 L39 36", "none", "#e0c58e", 2)
    icons["crescent"] += circle(18, 54, 3, "#617b84", "#f0dfb4", 1) + star(48, 40, 5, "#b5dbd8")

    icons["storm"] = path("M24 59 H40 L37 48 H27Z M27 43 H37 V50 H27Z", "url(#gold)", width=1.8)
    icons["storm"] += path("M24 45 L13 28 17 10 25 17 22 28 31 39 M40 45 L51 28 47 10 39 17 42 28 33 39", "none", "#101d2b", 7)
    icons["storm"] += path("M24 45 L13 28 17 10 25 17 22 28 31 39 M40 45 L51 28 47 10 39 17 42 28 33 39", "none", "#a1c9c3", 3.5)
    icons["storm"] += path("M34 5 L25 23 33 22 27 40 40 18 32 19Z", "#f0df9f", "#29313b", 1.4)
    icons["storm"] += path("M16 27 L8 22 M48 27 L56 22 M25 47 H39", "none", "#dec898", 1.5)
    icons["storm"] += star(32, 45, 4, "#eef1d2")

    icons["comet"] = path("M11 8 L29 20 38 17 46 27 39 41 25 42 18 33Z", "url(#violet)", width=1.8)
    icons["comet"] += path("M7 19 L25 28 M19 7 L33 23", "none", "#b6a1cf", 2)
    icons["comet"] += path("M40 20 L44 31 57 32 48 41 51 55 38 49 27 58 28 44 17 36 31 33Z", "url(#gold)", width=2)
    icons["comet"] += path("M40 20 L38 39 57 32 M17 36 L38 39 27 58 M51 55 L38 39 28 44 M38 49 L38 39", "none", "#f1dba4", 1.2)
    icons["comet"] += path("M31 33 L38 39 44 31", "#6d5b82", "#d3bbd7", 1)
    icons["comet"] += star(38, 39, 4, "#fff0c4")

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

    icons["moon_charm"] = path("M12 5 Q13 25 28 31 M52 5 Q51 25 36 31", "none", "#a98b62", 3)
    icons["moon_charm"] += path("M17 10 L20 15 M22 22 L27 26 M47 10 L44 15 M42 22 L37 26", "none", "#e4c891", 2)
    icons["moon_charm"] += circle(32, 30, 5, "#283448", "#d9bf8b", 2)
    icons["moon_charm"] += path("M39 33 Q17 29 16 44 Q15 60 34 60 Q44 59 49 51 Q31 56 28 45 Q26 36 39 33Z", "url(#bone)", width=1.8)
    icons["moon_charm"] += path("M37 35 Q21 35 20 45 Q19 55 30 57", "none", "#f1e5c7", 1.1)
    icons["moon_charm"] += star(42, 40, 5, "#ab94c8")

    icons["pilgrim"] = path("M15 9 L31 11 29 32 37 43 35 53 H11 L7 46 14 35Z", "url(#robe)", width=2)
    icons["pilgrim"] += path("M35 13 L49 15 47 35 58 45 55 57 H31 L28 48 35 38Z", "url(#robe)", width=2)
    icons["pilgrim"] += path("M18 16 L28 18 M17 23 L27 25 M38 20 L46 22 M37 27 L45 29 M11 47 H32 M32 51 H55", "none", "#d4bc91", 1.8)
    icons["pilgrim"] += path("M7 54 H26 M34 59 H53", "none", "#87775f", 2)
    icons["pilgrim"] += circle(47, 9, 5, "#252938", "#b5c9bd", 1.3) + star(47, 9, 4, "#d8e0c1")

    icons["bulwark"] = path("M11 11 L32 4 53 11 51 35 Q45 52 32 60 Q19 52 13 35Z", "#292735", "#9f937d", 2)
    icons["bulwark"] += path("M19 16 L32 12 45 16 43 34 Q39 45 32 51 Q25 44 21 34Z", "#363b45", "#b8a581", 1)
    icons["bulwark"] += path("M25 16 Q19 19 23 23 L23 40 Q19 44 25 47 Q30 45 28 41 V22 Q30 18 25 16Z M39 16 Q33 18 36 22 V41 Q33 45 39 47 Q45 44 41 40 V23 Q45 19 39 16Z", "url(#bone)", width=1.4)
    icons["bulwark"] += path("M19 27 Q32 20 45 27 M19 34 Q32 28 45 34", "none", "#d1c4a3", 2)
    icons["bulwark"] += circle(32, 37, 3, "#b6c9c0", "#29313a", 1)

    icons["hourglass"] = path("M15 6 H49 L47 12 H17Z M15 52 H49 L51 59 H13Z", "url(#gold)", width=1.6)
    icons["hourglass"] += path("M19 12 L22 25 30 31 24 39 20 52 H44 L42 39 35 31 43 23 45 12Z", "#303448", "#b7b7b1", 1.7)
    icons["hourglass"] += path("M23 16 H41 L38 24 33 28 27 24Z M25 48 L32 37 39 48Z", "url(#gold)", "none", 0)
    icons["hourglass"] += path("M40 12 L35 21 40 25 33 32 38 36 34 43 M17 13 L12 49 M47 13 L52 49", "none", "#d5bcdd", 2)
    icons["hourglass"] += path("M47 26 L55 22 53 32Z M43 36 L50 39 47 45Z", "#a9bbc1", "#252331", 1.3)
    icons["hourglass"] += path("M30 31 L33 34 M29 36 L30 38", "none", "#e8d09a", 1.5)

    icons["soul"] = path("M33 5 L46 24 43 45 31 59 20 47 17 27Z", "#3b7b82", "#142932", 2)
    icons["soul"] += path("M33 6 L31 42 17 27Z", "#a5d7c5", "none", 0)
    icons["soul"] += path("M33 6 L46 24 31 42Z", "#70b5b2", "none", 0)
    icons["soul"] += path("M31 42 L43 45 31 59Z", "#bddfc8", "none", 0)
    icons["soul"] += path("M20 47 L31 42 43 45 M23 25 L31 19 37 26 32 36Z", "none", "#d7eee0", 1.1)

    icons["return_ring"] = _return_ring()
    icons["blood_pact"] = _blood_pact()
    icons["grave_candle"] = _grave_candle()
    icons["fold_clasp"] = _fold_clasp()
    icons["echo_stone"] = _echo_stone()

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
