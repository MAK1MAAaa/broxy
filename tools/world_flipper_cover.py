"""Normalize the official cover background and preserve the original portrait."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name("world_flipper_cover_sources.json")


def _checked_image(source: dict, path: Path) -> Image.Image:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"Cover source checksum changed: {source['id']}")
    with Image.open(path) as image:
        if list(image.size) != source["source_size"]:
            raise ValueError(f"Unexpected cover source size: {source['id']}")
        return image.convert("RGBA")


def _record(path: Path, relative: str, image: Image.Image, source: dict, normalization: str) -> dict:
    return {
        "id": source["id"],
        "path": "assets/worldflipper/" + relative,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size": list(image.size),
        "alpha_bounds": list(image.getchannel("A").getbbox()),
        "filter": "linear",
        "source_ids": [source["id"]],
        "normalization": normalization,
    }


def cover_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    selected = [source for source in sources if source["kind"] in {"cover_background", "cover_portrait"}]
    by_id = {str(source["id"]): source for source in selected}
    if set(by_id) != {"cover_background", "portrait_alk"} or len(selected) != 2:
        raise ValueError("The cover requires one official background and the default Alk portrait")
    background = by_id["cover_background"]
    raw_background = _checked_image(background, paths["cover_background"])
    matte = Image.new("RGBA", raw_background.size, "#fff9e8")
    matte.alpha_composite(raw_background)
    image = ImageOps.fit(matte, (1280, 720), method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
    background_path = output / "title/cover.png"
    background_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(background_path, optimize=False)
    records = [_record(background_path, "title/cover.png", image, background,
                       "Cream matte; proportional cover fit and centered 1280x720 crop; no character baked into the background")]
    portrait = by_id["portrait_alk"]
    portrait_source = paths["portrait_alk"]
    portrait_image = _checked_image(portrait, portrait_source)
    if portrait_image.getchannel("A").getextrema() != (0, 255):
        raise ValueError("The original portrait must retain its transparent background")
    portrait_path = output / "portraits/alk.png"
    portrait_path.parent.mkdir(parents=True, exist_ok=True)
    portrait_path.write_bytes(portrait_source.read_bytes())
    records.append(_record(portrait_path, "portraits/alk.png", portrait_image, portrait,
                           "Original source bytes preserved; runtime keeps the full aspect ratio inside a separate right-side portrait layer"))
    return records


def main() -> None:
    from fetch_world_flipper_art import acquire

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Only use checksum-verified cached sources")
    args = parser.parse_args()
    sources: list[dict] = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    (ROOT / ".tools/worldflipper/source").mkdir(parents=True, exist_ok=True)
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    records = cover_assets(sources, paths, ROOT / "assets/worldflipper")
    print(json.dumps({"assets": records, "offline": args.offline}, ensure_ascii=False))


if __name__ == "__main__":
    main()
