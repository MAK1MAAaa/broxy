"""Original short skill cues, synthesized deterministically without external samples."""
from __future__ import annotations

import math
from pathlib import Path
import random
import struct
import wave

SAMPLE_RATE = 22050
DURATIONS: dict[str, float] = {"dash": 0.18, "pulse": 0.28, "pulse_hit": 0.34, "evade": 0.22}
REVISION = "skill-feedback-01"


def _envelope(time: float, duration: float, attack: float, decay: float) -> float:
    if time <= 0.0 or time >= duration:
        return 0.0
    onset = 0.5 - 0.5 * math.cos(math.pi * min(1.0, time / attack))
    release = min(1.0, (duration - time) / 0.012)
    return onset * release * math.exp(-time * decay)


def samples(name: str) -> list[float]:
    duration = DURATIONS[name]
    rng = random.Random({"dash": 9101, "pulse": 9102, "pulse_hit": 9102, "evade": 9103}[name])
    result: list[float] = []
    noise_low = 0.0
    noise_body = 0.0
    for index in range(round(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        noise = rng.uniform(-1.0, 1.0)
        noise_low += 0.055 * (noise - noise_low)
        noise_body += 0.42 * (noise - noise_body)
        air = noise_body - noise_low
        if name == "dash":
            tone = math.sin(math.tau * (620.0 * time + 1900.0 * time * time))
            value = _envelope(time, duration, 0.007, 19.0) * (0.56 * air + 0.08 * tone)
        elif name in {"pulse", "pulse_hit"}:
            body = math.sin(math.tau * (190.0 * time - 175.0 * time * time))
            rim = math.sin(math.tau * (475.0 * time - 250.0 * time * time))
            value = _envelope(time, 0.28, 0.009, 13.0) * (0.19 * body + 0.055 * rim + 0.10 * air)
            if name == "pulse_hit":
                contact = time - 0.018
                if contact > 0.0:
                    struck = math.sin(math.tau * 1190.0 * contact) + 0.54 * math.sin(math.tau * 1733.0 * contact)
                    value += _envelope(contact, duration - 0.018, 0.0035, 23.0) * (0.12 * struck + 0.14 * air)
        else:
            value = 0.0
            for onset, frequency, gain in [(0.0, 1480.0, 0.16), (0.052, 2047.0, 0.11)]:
                local = time - onset
                if local >= 0.0:
                    partials = math.sin(math.tau * frequency * local) + 0.29 * math.sin(math.tau * frequency * 1.493 * local)
                    value += _envelope(local, duration - onset, 0.003, 32.0) * gain * partials
        result.append(value)
    mean = sum(result) / len(result)
    result = [
        (value - mean)
        * (0.5 - 0.5 * math.cos(math.pi * min(1.0, index / 180.0)))
        * (0.5 - 0.5 * math.cos(math.pi * min(1.0, (len(result) - 1 - index) / 120.0)))
        for index, value in enumerate(result)
    ]
    peak = max(abs(value) for value in result)
    gain = 0.30 / peak
    return [value * gain for value in result]


def generate(directory: Path) -> list[dict[str, object]]:
    directory.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, object]] = []
    for name, duration in DURATIONS.items():
        values = samples(name)
        pcm = struct.pack("<%dh" % len(values), *(round(value * 32767) for value in values))
        with wave.open(str(directory / f"{name}.wav"), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(SAMPLE_RATE)
            stream.writeframes(pcm)
        entries.append({"id": f"audio_{name}", "path": f"assets/audio/{name}.wav", "type": "audio", "duration_seconds": duration, "sample_rate": SAMPLE_RATE, "loop": False, "source": "tools/audio_skills.py", "creator": "Project original deterministic skill synthesis", "license": "CC0-1.0", "status": "authored; in-game mix QA pending"})
    return entries
