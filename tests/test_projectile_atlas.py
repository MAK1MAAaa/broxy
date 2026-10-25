"""Protect authored head geometry and the generated eight-frame atlas contract."""
from __future__ import annotations

import json
import math
from pathlib import Path
import re
import sys
import unittest
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import art_projectiles as atlas

Point = tuple[float, float]
Segment = tuple[Point, Point]
SOURCES = ("bone", "frost", "ember", "scatter", "crescent", "storm", "comet", "return_ring")
SVG = "{http://www.w3.org/2000/svg}"


def rotate(point: Point, angle: float, origin: Point = (0., 0.)) -> Point:
    x, y = point
    cosine, sine = math.cos(angle), math.sin(angle)
    return origin[0] + cosine * x - sine * y, origin[1] + sine * x + cosine * y


def legacy_endpoints(source: str, radius: float, angle: float, origin: Point) -> list[Point]:
    """Frozen pre-atlas formulas, evaluated directly in world coordinates."""
    points: list[Point] = []
    dx, dy = math.cos(angle), math.sin(angle)

    def offset(x: float, y: float, center: Point = origin) -> Point:
        # Godot's orthogonal direction is (dy, -dx).
        return center[0] + dx * x + dy * y, center[1] + dy * x - dx * y

    if source == "crescent":
        center = (origin[0] - dx * 5., origin[1] - dy * 5.)
        for index in range(8):
            a = -math.pi * .5 + index * math.pi / 8.
            b = -math.pi * .5 + (index + 1) * math.pi / 8.
            for depth in (12., 6.):
                points.extend((offset(math.cos(a) * depth, math.sin(a) * 10., center),
                               offset(math.cos(b) * depth, math.sin(b) * 10., center)))
    elif source == "storm":
        for sign in (-1., 1.):
            offsets = ((-11., sign * 3.), (-4., sign * 6.), (-6., sign), (5., 0.))
            for index in range(3):
                points.extend((offset(*offsets[index]), offset(*offsets[index + 1])))
    elif source == "comet":
        for index in range(5):
            angles = (angle + index * math.tau / 5.,
                      angle + (index + .5) * math.tau / 5.,
                      angle + (index + 1) * math.tau / 5.)
            radii = (radius + 3., (radius + 3.) * .43, radius + 3.)
            vertices = [(origin[0] + math.cos(a) * r, origin[1] + math.sin(a) * r)
                        for a, r in zip(angles, radii)]
            points.extend((vertices[0], vertices[1], vertices[1], vertices[2]))
    return points


def segment_distance_to_center(segment: Segment) -> float:
    (ax, ay), (bx, by) = segment
    dx, dy = bx - ax, by - ay
    amount = max(0., min(1., -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
    return math.hypot(ax + amount * dx, ay + amount * dy)


def structure(element: ElementTree.Element) -> tuple:
    return element.tag, tuple(sorted(element.attrib.items())), tuple(map(structure, element))


class ProjectileAtlasTests(unittest.TestCase):
    def setUp(self) -> None:
        self.radii = atlas.default_radii()
        self.saved: list[tuple[str, int, int, str, str]] = []
        self.metadata = atlas.generate(lambda *arguments: self.saved.append(arguments))
        self.assertEqual(len(self.saved), 1)
        _, _, _, body, _ = self.saved[0]
        self.generated = ElementTree.fromstring(f'<svg xmlns="http://www.w3.org/2000/svg">{body}</svg>')

    def test_legacy_math_oracle_survives_asset_generation(self) -> None:
        # These 45 historical angle/radius cases formerly exercised GDScript
        # sigils. They now protect the offline geometry rather than removed APIs.
        for source in ("crescent", "storm", "comet"):
            for angle in (0., .31, .9, 2.7, 5.9):
                for radius in (1., 11., 19.):
                    with self.subTest(source=source, angle=angle, radius=radius):
                        origin = (342.25, 390.75)
                        actual = [rotate(point, angle, origin)
                                  for segment in atlas.local_segments(source, radius) for point in segment]
                        expected = legacy_endpoints(source, radius, angle, origin)
                        self.assertEqual(len(actual), len(expected))
                        for point, oracle in zip(actual, expected):
                            self.assertAlmostEqual(point[0], oracle[0], places=8)
                            self.assertAlmostEqual(point[1], oracle[1], places=8)

    def test_source_frames_dimensions_and_metadata(self) -> None:
        self.assertEqual(atlas.SOURCES, SOURCES)
        self.assertEqual((atlas.FRAME_SIZE, atlas.WORLD_SIZE), (64, 32))
        self.assertEqual(self.saved[0][:3], ("fx/projectile_heads.svg", 512, 64))
        self.assertEqual(self.metadata, {
            "frame_size": [64, 64], "world_size": [32, 32], "columns": 8, "rows": 1,
            "sampling_scale": 2,
            "frames": [{"source": source, "frame": frame, "base_radius": self.radii[source]}
                       for frame, source in enumerate(SOURCES)],
        })
        groups = self.generated.findall(f"{SVG}g")
        self.assertEqual(len(groups), 8)
        for frame, group in enumerate(groups):
            self.assertEqual(group.attrib, {"transform": f"translate({frame * 64 + 32} 32) scale(2)"})

    def test_authored_cores_and_strokes_fit_separate_cells(self) -> None:
        counts = {"crescent": 16, "storm": 6, "comet": 10, "return_ring": 18}
        for source, group in zip(SOURCES, self.generated):
            with self.subTest(source=source):
                polygons = group.findall(f"{SVG}polygon")
                self.assertEqual(len(polygons), 0 if source == "return_ring" else 1)
                if polygons:
                    polygon = polygons[0]
                    self.assertEqual(polygon.get("fill"), "#f8efe2" if source == "ember" else "#f5efe0")
                    vertices = [tuple(map(float, value.split(","))) for value in polygon.attrib["points"].split()]
                    self.assertEqual(len(vertices), 16)
                    scale = {"ember": .4, "crescent": .18, "comet": .35}.get(source, .55)
                    for index, point in enumerate(vertices):
                        angle = index * math.tau / 16.
                        self.assertAlmostEqual(point[0], math.cos(angle) * self.radii[source] * scale, places=7)
                        self.assertAlmostEqual(point[1], math.sin(angle) * self.radii[source] * scale, places=7)
                paths = group.findall(f"{SVG}path")
                self.assertEqual(len(paths), counts.get(source, 0))
                expected = atlas.local_segments(source, self.radii[source])
                for path, segment in zip(paths, expected):
                    self.assertEqual(path.get("fill"), "none")
                    self.assertEqual(path.get("stroke-width"), "1.3")
                    self.assertEqual(path.get("stroke-opacity"), ".85")
                    self.assertEqual(path.get("stroke-linecap"), "butt")
                    self.assertEqual(path.get("stroke"), "#e7dba8" if source == "storm" else "#d5c1e8" if source == "comet" else "#d3e8de")
                    match = re.fullmatch(r"M([^,]+),([^ ]+) L([^,]+),([^ ]+)", path.attrib["d"])
                    self.assertIsNotNone(match)
                    actual = tuple(map(float, match.groups()))
                    for value, oracle in zip(actual, (*segment[0], *segment[1])):
                        self.assertTrue(math.isfinite(value))
                        self.assertAlmostEqual(value, oracle, places=7)
                        self.assertLess(abs(value) + .65, 16., "Visible strokes need padding inside their UV cell")

    def test_return_ring_retains_three_closed_hollow_blades(self) -> None:
        segments = atlas.local_segments("return_ring", self.radii["return_ring"])
        self.assertEqual(len(segments), 18)
        for blade in range(3):
            outline = segments[blade * 6:(blade + 1) * 6]
            for index, segment in enumerate(outline):
                self.assertEqual(segment[1], outline[(index + 1) % 6][0])
                self.assertGreaterEqual(segment_distance_to_center(segment), 4.)
                for point in segment:
                    self.assertLessEqual(math.hypot(*point), 10.01)
                    expected = rotate(segments[index][0], blade * math.tau / 3.)
                    if point == segment[0]:
                        self.assertAlmostEqual(point[0], expected[0], places=8)
                        self.assertAlmostEqual(point[1], expected[1], places=8)

    def test_checked_in_svg_and_manifest_match_generated_geometry(self) -> None:
        checked_in = ElementTree.parse(ROOT / "assets" / "fx" / "projectile_heads.svg").getroot()
        self.assertEqual(checked_in.get("width"), "512")
        self.assertEqual(checked_in.get("height"), "64")
        self.assertEqual(checked_in.get("viewBox"), "0 0 512 64")
        self.assertEqual([structure(group) for group in checked_in.findall(f"{SVG}g")],
                         [structure(group) for group in self.generated.findall(f"{SVG}g")])
        self.assertEqual(list(checked_in.iter(f"{SVG}image")), [])
        manifest = json.loads((ROOT / "assets" / "manifest.json").read_text(encoding="utf-8"))
        entries = [asset for asset in manifest["assets"] if asset["path"] == "assets/fx/projectile_heads.svg"]
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["size"], [512, 64])
        self.assertEqual(entries[0]["source"], "tools/art_projectiles.py")
        self.assertEqual(entries[0]["atlas"], self.metadata)


if __name__ == "__main__":
    unittest.main()
