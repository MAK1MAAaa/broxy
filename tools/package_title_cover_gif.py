#!/usr/bin/env python3
"""Encode native title render frames as a shared-palette looping GIF."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageSequence, __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/worldflipper/title"
DEFAULT_PORTRAIT = ROOT / "assets/worldflipper/portraits/alk.png"
SOURCE_REGISTRY = ROOT / "tools/world_flipper_cover_sources.json"
DEFAULT_CHARACTER_ID = "alk"
FRAME_COUNT = 24
DURATION_MS = 120


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package(frames: Path, output: Path, metadata: Path) -> None:
    sources = [frames / f"frame_{index:02d}.png" for index in range(FRAME_COUNT)]
    images: list[Image.Image] = []
    for source in sources:
        with Image.open(source) as image:
            if image.size != (1280, 720):
                raise ValueError(f"Unexpected native frame size: {source}")
            images.append(image.convert("RGB"))
    palette = images[0].quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    colors = palette.getpalette()[:765]
    palette.putpalette(colors + colors[:3])
    indexed = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
    for index, image in enumerate(indexed):
        indexed[index] = image.point(list(range(255)) + [0])
    delta_frames = [indexed[0].copy()]
    for previous, current in zip(indexed, indexed[1:]):
        previous_indices = Image.frombytes("L", previous.size, previous.tobytes())
        current_indices = Image.frombytes("L", current.size, current.tobytes())
        unchanged = ImageChops.difference(previous_indices, current_indices).point([255] + [0] * 255)
        delta = current.copy()
        delta.paste(255, (0, 0), unchanged)
        delta_frames.append(delta)
    output.parent.mkdir(parents=True, exist_ok=True)
    delta_frames[0].save(output, format="GIF", save_all=True, append_images=delta_frames[1:],
                         duration=[DURATION_MS] * FRAME_COUNT, loop=0, disposal=1,
                         optimize=False, transparency=255, palette=bytes(palette.getpalette()))
    decoded: list[str] = []
    durations: list[int] = []
    first_decoded: Image.Image | None = None
    with Image.open(output) as gif:
        if gif.size != (1280, 720) or gif.info.get("loop") != 0:
            raise ValueError("GIF must cover the logical screen and loop forever")
        for index, frame in enumerate(ImageSequence.Iterator(gif)):
            decoded_image = frame.convert("RGB")
            rgb = decoded_image.tobytes()
            if rgb != indexed[index].convert("RGB").tobytes():
                raise ValueError(f"GIF palette/disposal corrupted native frame {index}")
            if first_decoded is None:
                first_decoded = decoded_image.copy()
            source_difference = ImageChops.difference(images[0], images[index])
            red, green, blue = source_difference.split()
            unchanged_mask = ImageChops.lighter(ImageChops.lighter(red, green), blue).point([255] + [0] * 255)
            decoded_difference = ImageChops.difference(first_decoded, decoded_image)
            if ImageChops.multiply(decoded_difference, Image.merge("RGB", (unchanged_mask,) * 3)).getbbox() is not None:
                raise ValueError(f"GIF changed stationary native pixels in frame {index}")
            decoded.append(hashlib.sha256(rgb).hexdigest())
            durations.append(int(frame.info["duration"]))
    if len(decoded) != FRAME_COUNT or len(set(decoded)) != FRAME_COUNT or durations != [DURATION_MS] * FRAME_COUNT:
        raise ValueError("GIF must contain 24 distinct frames at 120ms each")
    if output.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("The title GIF exceeds its eight-MiB source budget")
    value = {
        "schema_version": 1, "size": [1280, 720], "frames": FRAME_COUNT,
        "frame_duration_ms": DURATION_MS, "duration_ms": FRAME_COUNT * DURATION_MS,
        "loop_forever": True, "encoder": f"Pillow {PILLOW_VERSION}; fixed shared palette; explicit transparent deltas; no reindex optimization",
        "decoded_frames_equal_global_palette_source": True,
        "stationary_source_pixels_preserved": True,
        "gif_sha256": sha(output), "base_png_sha256": sha(ART / "cover.png"),
        "base_png_path": (ART / "cover.png").relative_to(ROOT).as_posix(),
        "default_character_id": DEFAULT_CHARACTER_ID,
        "portrait_path": DEFAULT_PORTRAIT.relative_to(ROOT).as_posix(),
        "portrait_sha256": sha(DEFAULT_PORTRAIT),
        "source_registry": SOURCE_REGISTRY.relative_to(ROOT).as_posix(),
        "source_registry_sha256": sha(SOURCE_REGISTRY),
        "renderer": "scripts/ui/title_cover.gd", "renderer_sha256": sha(ROOT / "scripts/ui/title_cover.gd"),
        "runtime": "The native cover player renders these same 24 states; no GIF decoder/plugin is required",
        "source_frame_sha256": [sha(source) for source in sources], "decoded_gif_frame_sha256": decoded,
    }
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"gif": str(output), "bytes": output.stat().st_size, "frames": len(decoded),
                      "unique_frames": len(set(decoded)), "duration_ms": sum(durations), "sha256": sha(output)}))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, default=ROOT / "reports/title-cover/frames")
    parser.add_argument("--output", type=Path, default=ART / "cover.gif")
    parser.add_argument("--metadata", type=Path, default=ART / "animation.json")
    args = parser.parse_args()
    package(args.frames, args.output, args.metadata)


if __name__ == "__main__":
    main()
