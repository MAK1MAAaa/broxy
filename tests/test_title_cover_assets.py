"""Verify the delivered GIF stream and its native renderer provenance without Pillow."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/title"


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
        data = (ART / "cover.gif").read_bytes()
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
        metadata = json.loads((ART / "animation.json").read_text(encoding="utf-8"))
        self.assertEqual((metadata["frames"], metadata["frame_duration_ms"], metadata["duration_ms"]), (24, 120, 2880))
        self.assertTrue(metadata["loop_forever"])
        self.assertTrue(metadata["decoded_frames_equal_global_palette_source"] and metadata["stationary_source_pixels_preserved"])
        for name, key in (("cover.png", "base_png_sha256"), ("cover.gif", "gif_sha256")):
            self.assertEqual(hashlib.sha256((ART / name).read_bytes()).hexdigest(), metadata[key])
        self.assertEqual(hashlib.sha256((ROOT / metadata["renderer"]).read_bytes()).hexdigest(), metadata["renderer_sha256"])
        self.assertEqual(len(set(metadata["source_frame_sha256"])), 24)
        self.assertEqual(len(set(metadata["decoded_gif_frame_sha256"])), 24)

    def test_base_is_full_screen_and_the_source_is_recorded(self) -> None:
        png = (ART / "cover.png").read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack_from(">II", png, 16), (1280, 720))
        source = json.loads((ART / "image-generation.json").read_text(encoding="utf-8"))
        self.assertEqual(source["tool"], "image_gen.imagegen built-in")
        self.assertFalse(source["external_game_art_embedded"])
        self.assertIn("bird-beak", source["prompt"])


if __name__ == "__main__":
    unittest.main()
