"""Fetch pinned publicly hosted World Flipper assets for the existing game."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".tools/worldflipper/source"
OUTPUT = ROOT / "assets/worldflipper"
REGISTRY = Path(__file__).with_name("world_flipper_sources.json")
CELL = (96, 96)
MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def acquire(source: dict, offline: bool) -> Path:
    filename = str(source["filename"])
    if Path(filename).name != filename:
        raise ValueError("Source filenames must stay inside the cache")
    path = CACHE / filename
    if path.exists():
        data = path.read_bytes()
    else:
        if offline:
            raise FileNotFoundError(f"Missing cached source: {path}")
        request = Request(source["url"], headers={"User-Agent": "BroxyFanArtResearch/1.0"})
        with urlopen(request, timeout=40) as response:
            data = response.read(MAX_DOWNLOAD_BYTES + 1)
        if len(data) > MAX_DOWNLOAD_BYTES:
            raise ValueError(f"Source exceeds the size limit: {filename}")
    if sha256(data) != source["sha256"]:
        raise ValueError(f"Source checksum changed: {filename}")
    if not path.exists():
        path.write_bytes(data)
    return path


def pixel_frame(image: Image.Image) -> Image.Image:
    if image.size != (24, 30):
        raise ValueError(f"Unexpected player canvas: {image.size}")
    frame = Image.new("RGBA", CELL)
    frame.alpha_composite(image.convert("RGBA").resize((72, 90), Image.Resampling.NEAREST), (12, 3))
    return frame


def write_image(image: Image.Image, relative: str) -> dict:
    path = OUTPUT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=False)
    alpha = image.getchannel("A")
    if alpha.getextrema() != (0, 255):
        raise ValueError(f"The normalized asset must retain transparency: {relative}")
    return {
        "path": "assets/worldflipper/" + relative,
        "sha256": sha256(path.read_bytes()),
        "size": list(image.size),
        "alpha_bounds": list(alpha.getbbox()),
        "filter": "nearest",
    }


def player_assets(sources: list[dict], paths: dict[str, Path]) -> tuple[list[dict], list[Image.Image]]:
    frames: list[Image.Image] = []
    animations: dict[str, dict] = {}
    for source in sources:
        if source["kind"] != "player_animation":
            continue
        first = len(frames)
        durations: list[int] = []
        with Image.open(paths[source["id"]]) as image:
            if image.n_frames != source["frame_count"]:
                raise ValueError(f"Unexpected animation length: {source['id']}")
            for index in range(image.n_frames):
                image.seek(index)
                frames.append(pixel_frame(image))
                durations.append(int(image.info.get("duration", 0)))
        if durations != source["durations_ms"]:
            raise ValueError(f"Unexpected animation timing: {source['id']}")
        animations[source["pose"]] = {"first_frame": first, "frame_count": len(durations), "durations_ms": durations}
    if len(frames) != 9:
        raise ValueError("The player requires one neutral and eight walking frames")
    atlas = Image.new("RGBA", (384, 288))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % 4) * 96, (index // 4) * 96))
    idle = write_image(frames[0], "sprites/player.png")
    idle.update({"id": "player", "source_ids": ["alk_neutral"], "normalization": "3x nearest at (12,3); original 24x30 canvas retained inside 96x96"})
    motion = write_image(atlas, "sprites/player-atlas.png")
    motion.update({"id": "player_animation", "source_ids": ["alk_neutral", "alk_walk_front", "alk_walk_back"], "cell_size": list(CELL), "columns": 4, "animations": animations})
    return [idle, motion], frames


def weapon_assets(sources: list[dict], paths: dict[str, Path]) -> tuple[list[dict], list[Image.Image]]:
    assets: list[dict] = []
    images: list[Image.Image] = []
    for source in sources:
        if source["kind"] != "weapon":
            continue
        with Image.open(paths[source["id"]]) as raw:
            if list(raw.size) != source["source_size"]:
                raise ValueError(f"Unexpected weapon size: {source['id']}")
            scaled = raw.convert("RGBA").resize((raw.width * 3, raw.height * 3), Image.Resampling.NEAREST)
        image = Image.new("RGBA", (64, 64))
        offset = ((64 - scaled.width) // 2, (64 - scaled.height) // 2)
        image.alpha_composite(scaled, offset)
        result = write_image(image, "icons/" + source["game_id"] + ".png")
        result.update({"id": source["game_id"], "source_ids": [source["id"]], "normalization": "3x nearest, centered inside 64x64, no recoloring or background"})
        assets.append(result)
        images.append(image)
    if len(assets) != 8:
        raise ValueError("Every existing weapon must have an art mapping")
    return assets, images


def preview(frames: list[Image.Image], weapons: list[Image.Image]) -> Path:
    sheet = Image.new("RGBA", (960, 528), (218, 232, 221, 255))
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(frames):
        x = 8 + index * 104
        sheet.alpha_composite(frame, (x, 24))
        draw.text((x + 32, 126), str(index), fill=(30, 55, 70))
    for index, image in enumerate(weapons):
        x = 16 + (index % 4) * 236
        y = 184 + (index // 4) * 164
        sheet.alpha_composite(image.resize((128, 128), Image.Resampling.NEAREST), (x + 48, y))
    path = CACHE.parent / "runtime-contact.png"
    sheet.convert("RGB").save(path)
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Only use checksum-verified cached sources")
    parser.add_argument("--references", action="store_true", help="Also cache the Wiki portrait, pixel preview and skill GIF; these do not enter the game")
    args = parser.parse_args()
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    sources: list[dict] = registry["sources"]
    CACHE.mkdir(parents=True, exist_ok=True)
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    if args.references:
        for source in registry["references"]:
            acquire(source, args.offline)
    player, frames = player_assets(sources, paths)
    weapons, icons = weapon_assets(sources, paths)
    manifest = {
        "revision": "world-flipper-fan-01",
        "original_copyright": "© Cygames, Inc. / Citail Inc.",
        "license_status": "Original game assets; no open asset license found. Unofficial fan-work use is not a claim of authorization.",
        "copyright_source": "https://worldflipper.jp/copyright/",
        "terms_source": "https://worldflipper.jp/about/",
        "acquired_on": "2026-10-29",
        "sources": sources,
        "references_cached_only": registry["references"],
        "assets": player + weapons,
        "gameplay": "Presentation only; existing catalog IDs, names, rules and collisions remain in force.",
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"assets": len(player + weapons), "preview": str(preview(frames, icons)), "offline": args.offline}, ensure_ascii=False))


if __name__ == "__main__":
    main()
