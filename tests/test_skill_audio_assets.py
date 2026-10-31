"""Validate playable PCM, smooth edges and reproducible original skill resources."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import audio_skills


class SkillAudioAssetsTests(unittest.TestCase):
    def test_checked_in_pcm_and_envelopes(self) -> None:
        hashes: set[str] = set()
        for name, duration in audio_skills.DURATIONS.items():
            with self.subTest(name=name):
                path = ROOT / "assets/audio" / f"{name}.wav"
                hashes.add(hashlib.sha256(path.read_bytes()).hexdigest())
                with wave.open(str(path), "rb") as source:
                    self.assertEqual((source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getcomptype()), (1, 2, 22050, "NONE"))
                    self.assertEqual(source.getnframes(), round(22050 * duration))
                    raw = source.readframes(source.getnframes())
                values = [value / 32768.0 for value in struct.unpack("<%dh" % (len(raw) // 2), raw)]
                rms = math.sqrt(sum(value * value for value in values) / len(values))
                self.assertGreater(rms, 0.025)
                self.assertLess(rms, 0.14)
                self.assertLessEqual(max(abs(value) for value in values), 0.301)
                self.assertLess(abs(sum(values) / len(values)), 0.001)
                self.assertEqual((values[0], values[-1]), (0.0, 0.0))
                for edge in [values[:66], values[-66:]]:
                    self.assertLess(math.sqrt(sum(value * value for value in edge) / len(edge)), rms * 0.55)
        self.assertEqual(len(hashes), 4)
        self.assertNotIn(hashlib.sha256((ROOT / "assets/audio/rune.wav").read_bytes()).hexdigest(), hashes)

    def test_deterministic_generation_matches_checked_in_waves(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first"
            second = Path(temporary) / "second"
            self.assertEqual(audio_skills.generate(first), audio_skills.generate(second))
            for name in audio_skills.DURATIONS:
                expected = (ROOT / "assets/audio" / f"{name}.wav").read_bytes()
                self.assertEqual((first / f"{name}.wav").read_bytes(), expected)
                self.assertEqual((second / f"{name}.wav").read_bytes(), expected)

    def test_manifest_declares_real_cues_and_redistribution(self) -> None:
        manifest = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["skill_audio_revision"], audio_skills.REVISION)
        for name, duration in audio_skills.DURATIONS.items():
            entries = [entry for entry in manifest["assets"] if entry["path"] == f"assets/audio/{name}.wav"]
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0]["duration_seconds"], duration)
            self.assertEqual(entries[0]["sample_rate"], 22050)
            self.assertEqual(entries[0]["license"], "CC0-1.0")
            self.assertEqual(entries[0]["source"], "tools/audio_skills.py")
            self.assertFalse(entries[0]["loop"])


if __name__ == "__main__":
    unittest.main()
