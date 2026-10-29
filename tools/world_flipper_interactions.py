"""Normalize pinned original orb, breakable and pickup pixels for this game's rules."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = Path(__file__).with_name("world_flipper_interactions_sources.json")
IDS = ("ball", "barrel", "chest", "health", "charge", "mana")
REVISION = "world-flipper-fan-06"
FILENAMES = {"ball": "ball-atlas.png", "barrel": "barrel-atlas.png", **{name: name + ".png" for name in IDS[2:]}}
EXPECTED = {"ball": ([64, 64], 7, 7, 2), "barrel": ([128, 128], 4, 11, 2),
            "chest": ([96, 96], 1, 1, 3), **{name: ([64, 64], 1, 1, 2) for name in IDS[3:]}}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _checked_image(source: dict, path: Path) -> Image.Image:
    data = path.read_bytes()
    if len(data) > 8 * 1024 * 1024 or _sha(data) != source["sha256"]:
        raise ValueError("Unexpected interaction source bytes: " + source["id"])
    with Image.open(path) as raw:
        if raw.format != "PNG" or list(raw.size) != source["source_size"]:
            raise ValueError("Unexpected interaction source canvas: " + source["id"])
        return raw.convert("RGBA")


def _rect(image: Image.Image, rect: list[int]) -> Image.Image:
    if len(rect) != 4 or any(type(value) is not int for value in rect):
        raise ValueError("Interaction crops require four integers")
    x, y, width, height = rect
    if min(x, y) < 0 or min(width, height) <= 0 or x + width > image.width or y + height > image.height:
        raise ValueError("Interaction crop leaves its source canvas")
    return image.crop((x, y, x + width, y + height))


def _frame(image: Image.Image, entry: dict, restore: bool) -> Image.Image:
    value = _rect(image, [entry[key] for key in ("x", "y", "w", "h")])
    if type(entry.get("r", False)) is not bool:
        raise ValueError("Atlas rotation must be a boolean")
    if entry.get("r", False):
        value = value.transpose(Image.Transpose.ROTATE_90)
    if not restore:
        return value
    width, height = entry["fw"], entry["fh"]
    x, y = -entry.get("fx", 0), -entry.get("fy", 0)
    if any(type(number) is not int for number in (width, height, x, y)) or min(x, y) < 0 or min(width, height) <= 0 or x + value.width > width or y + value.height > height:
        raise ValueError("Atlas trim restoration leaves its original canvas")
    result = Image.new("RGBA", (width, height))
    result.alpha_composite(value, (x, y))
    return result


def interaction_assets(sources: list[dict], paths: dict[str, Path], output: Path) -> list[dict]:
    """Validate all six source families before replacing any runtime output."""
    selected = [source for source in sources if source.get("kind") == "interaction_art"]
    if len(selected) != len(IDS) or {source["game_id"] for source in selected} != set(IDS) or len({source["id"] for source in selected}) != len(IDS):
        raise ValueError("Interactions require six distinct pinned sources")
    prepared: list[tuple[dict, Image.Image, dict]] = []
    for game_id in IDS:
        source = next(source for source in selected if source["game_id"] == game_id)
        raw = _checked_image(source, paths[source["id"]])
        cell, columns, count, scale = EXPECTED[game_id]
        if (source["cell_size"], source["columns"], len(source["frames"]), source["scale"]) != (cell, columns, count, scale):
            raise ValueError("Unexpected interaction frame layout: " + game_id)
        if len({entry["n"] for entry in source["frames"]}) != count:
            raise ValueError("Interaction atlas entries need distinct frame identities")
        frames: list[Image.Image] = []
        for index, entry in enumerate(source["frames"]):
            value = _frame(raw, entry, game_id in ("ball", "barrel"))
            if game_id == "ball":
                if list(value.size) != [64, 64] or source["canvas_crop"] != [16, 8, 32, 32]:
                    raise ValueError("The original orb requires its common centered crop")
                clipped = _rect(value, source["canvas_crop"])
                restored = Image.new("RGBA", value.size)
                restored.alpha_composite(clipped, (16, 8))
                if restored.tobytes() != value.tobytes():
                    raise ValueError("Orb crop would remove original visible pixels")
                value = clipped.resize(tuple(cell), Image.Resampling.NEAREST)
            elif game_id == "barrel":
                if list(value.size) != [53, 36] or source["canvas_offset"] != [14, 52] or source["foot_anchor"] != [64, 112]:
                    raise ValueError("Barrel frames must retain the shared original trim origin")
                frame = Image.new("RGBA", tuple(cell))
                frame.alpha_composite(value.resize((106, 72), Image.Resampling.NEAREST), (14, 52))
                value = frame
                if (value.getchannel("A").getbbox() is None) != (index in (0, 10)):
                    raise ValueError("Barrel empty and intact frame identities changed")
            else:
                frame = Image.new("RGBA", tuple(cell))
                scaled_size = (value.width * scale, value.height * scale)
                expected_foot = [48, 88] if game_id == "chest" else [32, 61]
                if source["foot_anchor"] != expected_foot:
                    raise ValueError("Unexpected static interaction foot anchor")
                offset = ((cell[0] - scaled_size[0]) // 2, expected_foot[1] - scaled_size[1])
                if min(offset) < 0 or offset[0] + scaled_size[0] > cell[0]:
                    raise ValueError("Static interaction leaves its canvas")
                if value.getchannel("A").getbbox() is None:
                    raise ValueError("Static interaction requires a visible original silhouette")
                frame.alpha_composite(value.resize(scaled_size, Image.Resampling.NEAREST), offset)
                value = frame
            frames.append(value)
        atlas = Image.new("RGBA", (cell[0] * columns, cell[1] * ((count + columns - 1) // columns)))
        for index, frame in enumerate(frames):
            atlas.alpha_composite(frame, (index % columns * cell[0], index // columns * cell[1]))
        runtime = {"path": "res://assets/worldflipper/interactions/" + FILENAMES[game_id], "frame_size": cell,
                   "columns": columns, "frame_count": count, "filter": "nearest"}
        if game_id == "ball":
            if source["frame_ends_seconds"] != [.12, .18, .24, .30, .36, .42, .48] or source["center_anchor"] != [32, 32]:
                raise ValueError("Unexpected adapted orb playback")
            runtime.update({"frame_ends_seconds": source["frame_ends_seconds"], "center_anchor": [32, 32], "timing_note": source["timing_note"]})
        else:
            runtime["foot_anchor"] = source["foot_anchor"]
        if game_id == "barrel":
            if (source["idle_frame"], source["break_first_frame"], source["break_last_frame"], source["break_frame_duration"]) != (1, 2, 9, .04):
                raise ValueError("Unexpected adapted barrel playback")
            runtime.update({key: source[key] for key in ("idle_frame", "break_first_frame", "break_last_frame", "break_frame_duration", "timing_note")})
        prepared.append((source, atlas, runtime))
    records: list[dict] = []
    runtime_assets: dict[str, dict] = {}
    for source, image, runtime in prepared:
        game_id = source["game_id"]
        relative = "interactions/" + FILENAMES[game_id]
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, optimize=False)
        record = {"id": "interaction_" + game_id, "path": "assets/worldflipper/" + relative,
                  "sha256": _sha(target.read_bytes()), "size": list(image.size),
                  "alpha_bounds": list(image.getchannel("A").getbbox()), "filter": "nearest", "source_ids": [source["id"]],
                  "source_scale": source["scale"], "atlas_frames": source["frames"],
                  "normalization": source.get("normalization", "Original cropped and untrimmed atlas pixels at2x nearest; stable shared canvas. Animation timing is this project's explicit adaptation."),
                  **{key: value for key, value in runtime.items() if key not in ("path", "filter")}}
        records.append(record)
        runtime_assets[game_id] = runtime
    metadata = {"schema_version": 1, "revision": REVISION, "original_copyright": "© Cygames, Inc. / Citail Inc.",
                "adaptation": "Original pixels; project-specific ball and break timing, not an exact reproduction of the original game's motion or mechanics.", "assets": runtime_assets}
    target = output / "interactions/interaction-art.json"
    target.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return records


def main() -> None:
    from fetch_world_flipper_art import acquire

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="Use checksum-verified cached original sources only")
    args = parser.parse_args()
    sources = json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    paths = {source["id"]: acquire(source, args.offline) for source in sources}
    records = interaction_assets(sources, paths, ROOT / "assets/worldflipper")
    print(json.dumps({"assets": len(records), "offline": args.offline}, ensure_ascii=False))


if __name__ == "__main__":
    main()
