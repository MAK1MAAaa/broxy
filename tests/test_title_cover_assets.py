"""Verify the delivered GIF stream and its native renderer provenance without Pillow."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/title"
BASE = ART / "cover-alk.png"
GIF = ART / "cover-alk.gif"
ANIMATION = ART / "cover-alk.animation.json"
GENERATION = ART / "cover-alk.image-generation.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def gif_stream(data: bytes) -> dict:
    if data[:6] not in (b"GIF87a", b"GIF89a"):
        raise ValueError("Not a GIF stream")
    width, height = struct.unpack_from("<HH", data, 6)
    packed = data[10]
    cursor = 13 + (3 * (2 ** ((packed & 7) + 1)) if packed & 128 else 0)
    frames: list[dict] = []
    delay = 0
    loop = None

    def blocks(position: int) -> tuple[bytes, int]:
        payload = bytearray()
        while True:
            size = data[position]
            position += 1
            if not size:
                return bytes(payload), position
            payload.extend(data[position:position + size])
            position += size
            if position > len(data):
                raise ValueError("Truncated GIF data")

    while cursor < len(data):
        marker = data[cursor]
        cursor += 1
        if marker == 0x3B:
            if cursor != len(data):
                raise ValueError("Unexpected trailing GIF data")
            return {"size": (width, height), "loop": loop, "frames": frames}
        if marker == 0x21:
            label = data[cursor]
            cursor += 1
            if label == 0xF9:
                if data[cursor] != 4 or data[cursor + 5] != 0:
                    raise ValueError("Invalid graphic control block")
                delay = struct.unpack_from("<H", data, cursor + 2)[0] * 10
                cursor += 6
            else:
                payload, cursor = blocks(cursor)
                if label == 0xFF and payload.startswith(b"NETSCAPE2.0\x01"):
                    loop = struct.unpack_from("<H", payload, 12)[0]
        elif marker == 0x2C:
            x, y, frame_width, frame_height, flags = struct.unpack_from("<HHHHB", data, cursor)
            cursor += 9
            if flags & 128:
                cursor += 3 * 2 ** ((flags & 7) + 1)
            minimum_code_size = data[cursor]
            payload, cursor = blocks(cursor + 1)
            frames.append({"bounds": (x, y, frame_width, frame_height), "delay": delay,
                           "code_size": minimum_code_size, "data": payload})
            delay = 0
        else:
            raise ValueError(f"Invalid GIF block {marker:#x}")
    raise ValueError("GIF trailer is missing")


class TitleCoverAssets(unittest.TestCase):
    def test_gif_has_24_timed_frames_and_infinite_loop(self) -> None:
        data = GIF.read_bytes()
        stream = gif_stream(data)
        self.assertEqual(stream["size"], (1280, 720))
        self.assertEqual(stream["loop"], 0)
        self.assertEqual(len(stream["frames"]), 24)
        self.assertEqual([frame["delay"] for frame in stream["frames"]], [120] * 24)
        self.assertEqual(stream["frames"][0]["bounds"], (0, 0, 1280, 720))
        self.assertLess(len(data), 2 * 1024 * 1024)
        for frame in stream["frames"]:
            x, y, width, height = frame["bounds"]
            self.assertTrue(width > 0 and height > 0 and x + width <= 1280 and y + height <= 720)
            self.assertTrue(2 <= frame["code_size"] <= 8 and frame["data"])

    def test_metadata_matches_actual_gif_base_and_native_renderer(self) -> None:
        metadata = json.loads(ANIMATION.read_text(encoding="utf-8"))
        self.assertEqual((metadata["frames"], metadata["frame_duration_ms"], metadata["duration_ms"]), (24, 120, 2880))
        self.assertTrue(metadata["loop_forever"])
        self.assertTrue(metadata["decoded_frames_equal_global_palette_source"] and metadata["stationary_source_pixels_preserved"])
        for path, key in ((BASE, "base_png_sha256"), (GIF, "gif_sha256"), (GENERATION, "image_generation_sha256")):
            self.assertEqual(sha(path), metadata[key])
        self.assertEqual(sha(ROOT / metadata["renderer"]), metadata["renderer_sha256"])
        self.assertEqual(metadata["base_png_path"], "assets/title/cover-alk.png")
        self.assertEqual(metadata["image_generation_path"], "assets/title/cover-alk.image-generation.json")
        self.assertTrue(metadata["native_frames_match_composite_quiet_region"])
        self.assertNotIn("portrait_path", metadata)
        self.assertEqual(len(set(metadata["source_frame_sha256"])), 24)
        self.assertEqual(len(set(metadata["decoded_gif_frame_sha256"])), 24)

    def test_base_is_full_screen_and_the_source_is_recorded(self) -> None:
        png = BASE.read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack_from(">II", png, 16), (1280, 720))
        record = json.loads(GENERATION.read_text(encoding="utf-8"))
        self.assertEqual(record["tool"], "image_gen.imagegen built-in")
        self.assertEqual((record["mode"], record["character_id"]), ("edit", "alk"))
        self.assertTrue(record["external_game_character_reference"])
        self.assertTrue(record["edit_request_summary"])
        self.assertEqual(record["normalized_output"], {
            "path": "assets/title/cover-alk.png", "sha256": sha(BASE), "size": [1280, 720], "mode": "RGB",
        })
        references = {reference["id"]: reference for reference in record["references"]}
        self.assertEqual(len(record["references"]), 2)
        self.assertEqual(set(references), {"original_cover", "alk_portrait"})
        self.assertEqual(references["original_cover"]["path"], "assets/title/cover.png")
        self.assertEqual(references["alk_portrait"]["path"], "assets/worldflipper/portraits/alk.png")
        for reference in references.values():
            source = ROOT / reference["path"]
            self.assertEqual(sha(source), reference["sha256"])
            self.assertEqual(struct.unpack_from(">II", source.read_bytes(), 16), tuple(reference["size"]))
        registry = json.loads((ROOT / "tools/world_flipper_cover_sources.json").read_text(encoding="utf-8"))
        sources = {source["id"]: source for source in registry["sources"]}
        self.assertEqual(sources["portrait_alk"]["character_id"], "alk")
        self.assertTrue(sources["portrait_alk"]["source_page"].startswith("https://wiki.biligame.com/worldflipper/"))
        self.assertEqual(references["alk_portrait"]["sha256"], sources["portrait_alk"]["sha256"])
        generated = record["generated_output"]
        self.assertEqual(generated["size"], [1672, 941])
        self.assertEqual(generated["filename"], "exec-967800bb-65a6-4299-9981-00ecc5b3c86a.png")
        self.assertRegex(generated["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(generated["local_archive"], ".tools/worldflipper/cover-alk-generated.png")
        archive = ROOT / generated["local_archive"]
        if archive.exists():
            self.assertEqual(sha(archive), generated["sha256"])
        normalization = record["technical_normalization"]
        self.assertEqual(normalization["operation"], "ImageOps.fit")
        self.assertEqual(normalization["resample"], "LANCZOS")
        self.assertEqual(normalization["source_crop"], [0.0, 0.25, 1672.0, 940.75])

    def test_earlier_covers_remain_unchanged(self) -> None:
        record = json.loads(GENERATION.read_text(encoding="utf-8"))
        preserved = {asset["path"]: asset["sha256"] for asset in record["preserved_assets"]}
        expected = {
            "assets/title/cover.png", "assets/title/cover.gif", "assets/title/animation.json",
            "assets/title/image-generation.json", "assets/worldflipper/title/cover.png",
            "assets/worldflipper/title/cover.gif", "assets/worldflipper/title/animation.json",
        }
        self.assertEqual(set(preserved), expected)
        self.assertEqual(len(record["preserved_assets"]), len(expected))
        for path, digest in preserved.items():
            self.assertEqual(sha(ROOT / path), digest)
        self.assertNotEqual(sha(BASE), preserved["assets/title/cover.png"])


if __name__ == "__main__":
    unittest.main()
