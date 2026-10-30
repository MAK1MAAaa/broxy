"""Cross-check playable hero data against the independently pinned action index.

No engine, network or ignored .tools cache is needed. Original clock units remain
uninterpreted; only the project's explicitly declared 1/60-second mapping is tested.
"""

from __future__ import annotations

import json
import math
import re
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "1d45b529ef078ba9b1f876d4588debd0c8a9a214"
PROJECT_SECONDS_PER_ACTION_UNIT = 1.0 / 60.0
HERO_IDENTITIES = {
    "alk": ("1", "alk:2"),
    "clarisse": ("111003", "clarisse:2"),
    "celtie": ("141001", "wind_spgirl:2"),
    "hanabi": ("211003", "kunoichi:2"),
}


def resource_property(text: str, name: str) -> Any:
    match = re.search(rf"^{re.escape(name)}\s*=\s*", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError(f"Missing resource property: {name}")
    value, _ = json.JSONDecoder().raw_decode(text[match.end():])
    return value


def fixed_range(value: Any) -> float:
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        raise ValueError("Expected a fixed original numeric range")
    if value[0].get("min") != value[0].get("max"):
        raise ValueError("Original range is not fixed")
    return float(value[0]["min"])


class WorldFlipperRuntimeAdaptationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads((ROOT / "tools/world_flipper_skill_action_sources.json").read_text(encoding="utf-8"))
        cls.index = json.loads((ROOT / "data/worldflipper/skill_actions.json").read_text(encoding="utf-8"))
        cls.actions = {action["action_ref"]: action for action in cls.index["actions"]}
        cls.skills = {skill["skill_id"]: skill for skill in cls.index["skills"]}
        cls.sources = {source["path"]: source for source in cls.manifest["sources"]}
        cls.heroes = {}
        for hero_id in HERO_IDENTITIES:
            text = (ROOT / f"data/heroes/{hero_id}.tres").read_text(encoding="utf-8")
            cls.heroes[hero_id] = {name: resource_property(text, name) for name in
                                   ("source_id", "main_skill", "action_evidence", "adaptation_notes")}

    def source_action(self, hero_id: str) -> dict[str, Any]:
        skill_id = HERO_IDENTITIES[hero_id][1]
        return self.actions[self.skills[skill_id]["root_action_ref"]]

    def wait_value(self, action: dict[str, Any], pointer: str) -> int | float:
        wait = next(wait for wait in action["waits"] if wait["pointer"] == pointer)
        self.assertIsInstance(wait["delay_raw"], (int, float))
        self.assertFalse(wait["enclosing_wait_pointers"], "This mapping requires a direct source Wait, not an invented sum")
        return wait["delay_raw"]

    def area_wait(self, action: dict[str, Any], area: dict[str, Any]) -> int | float:
        self.assertEqual(len(area["wait_pointers"]), 1)
        return self.wait_value(action, area["wait_pointers"][0])

    def area_lifetime(self, area: dict[str, Any]) -> int | float:
        self.assertEqual(area["lifetime_raw"][0], "SpecifyHitAreaLifetimeDirectly")
        return area["lifetime_raw"][1]

    def area_hits(self, area: dict[str, Any]) -> int:
        self.assertEqual(area["hit_policy_raw"][0], "CalculatedUsingMaxNumOfHits")
        return area["hit_policy_raw"][1]

    def callback_has(self, action: dict[str, Any], area: dict[str, Any], name: str) -> bool:
        callback = next(callback for callback in area["callback_blocks"] if callback["parameter_index"] == 23)
        return any(pointer.startswith(callback["pointer"] + "/1/") for pointer in action["operation_pointers"].get(name, []))

    def assert_area_time_mapping(self, action: dict[str, Any], original: dict[str, Any], adapted: dict[str, Any]) -> None:
        self.assertAlmostEqual(adapted["delay"], self.area_wait(action, original) * PROJECT_SECONDS_PER_ACTION_UNIT, places=12)
        self.assertAlmostEqual(adapted["duration"], self.area_lifetime(original) * PROJECT_SECONDS_PER_ACTION_UNIT, places=12)
        self.assertEqual(adapted["hits"], self.area_hits(original))

    def test_all_four_heroes_bind_canonical_sources_and_declare_project_time_mapping(self) -> None:
        self.assertEqual(self.manifest["commit"], COMMIT)
        self.assertEqual(self.index["source"]["commit"], COMMIT)
        for hero_id, (canonical_id, skill_id) in HERO_IDENTITIES.items():
            with self.subTest(hero=hero_id):
                hero = self.heroes[hero_id]
                evidence = hero["action_evidence"]
                action = self.source_action(hero_id)
                source = self.sources[action["source_path"]]
                self.assertEqual(hero["source_id"], canonical_id)
                self.assertIn(canonical_id, self.skills[skill_id]["owner_character_ids"])
                self.assertEqual(evidence["catalog_skill_id"], skill_id)
                self.assertEqual(evidence["action_ref"], action["action_ref"])
                self.assertEqual(evidence["git_blob_sha1"], action["git_blob_sha1"])
                self.assertEqual(evidence["git_blob_sha1"], source["git_blob_sha1"])
                self.assertEqual(evidence["source_commit"], COMMIT)
                self.assertIn(COMMIT, source["url"])
                self.assertIn("1/60", evidence["time_adaptation"])
                self.assertIn("not a verified original FPS", evidence["time_adaptation"])
                self.assertIn("no original area size claim", evidence["geometry_adaptation"])
                self.assertTrue(math.isfinite(float(hero["main_skill"]["damage"])))

    def test_alk_uses_wait_44_and_lifetime_20_as_a_delayed_single_hit_area(self) -> None:
        action = self.source_action("alk")
        self.assertEqual(len(action["hit_areas"]), 1)
        original = action["hit_areas"][0]
        self.assertEqual(self.area_wait(action, original), 44)
        self.assertEqual(self.area_lifetime(original), 20)
        self.assertEqual(self.area_hits(original), 1)
        self.assertEqual(original["shape_raw"][0], "Circle")
        self.assertEqual(fixed_range(original["shape_raw"][1]), 425.0)
        self.assertTrue(self.callback_has(action, original, "CreateNormalAttack"))
        skill = self.heroes["alk"]["main_skill"]
        self.assertEqual(skill["delivery"], "areas")
        self.assertEqual(len(skill["timeline"]), 1)
        self.assert_area_time_mapping(action, original, skill["timeline"][0])
        self.assertEqual(skill["timeline"][0]["shape"], "circle")

    def test_clarisse_keeps_four_and_eleven_hits_and_the_independent_dispel_region(self) -> None:
        action = self.source_action("clarisse")
        self.assertEqual(len(action["hit_areas"]), 3)
        damaging = [area for area in action["hit_areas"] if self.callback_has(action, area, "CreateNormalAttack")]
        dispelling = [area for area in action["hit_areas"] if self.callback_has(action, area, "DeleteCondition")]
        self.assertEqual(len(damaging), 2)
        self.assertEqual(len(dispelling), 1)
        damaging.sort(key=lambda area: self.area_wait(action, area))
        self.assertEqual([self.area_wait(action, area) for area in damaging], [42, 79])
        self.assertEqual([self.area_lifetime(area) for area in damaging], [16, 67])
        self.assertEqual([self.area_hits(area) for area in damaging], [4, 11])
        for area in damaging:
            self.assertTrue(self.callback_has(action, area, "CreateCondition"))
            self.assertEqual(area["shape_raw"][0], "Circle")
            self.assertEqual(fixed_range(area["shape_raw"][1]), 250.0)
        dispel = dispelling[0]
        self.assertEqual(self.area_wait(action, dispel), 42)
        self.assertEqual(self.area_lifetime(dispel), 104)
        self.assertEqual(self.area_hits(dispel), 1)
        self.assertFalse(self.callback_has(action, dispel, "CreateNormalAttack"))
        skill = self.heroes["clarisse"]["main_skill"]
        timeline = skill["timeline"]
        adapted_damage = sorted((area for area in timeline if area.get("purpose") != "dispel"), key=lambda area: area["delay"])
        adapted_dispel = [area for area in timeline if area.get("purpose") == "dispel"]
        self.assertEqual(len(adapted_damage), 2)
        self.assertEqual(len(adapted_dispel), 1)
        self.assertEqual(skill["hits"], sum(self.area_hits(area) for area in damaging))
        for original, adapted in zip(damaging, adapted_damage):
            self.assert_area_time_mapping(action, original, adapted)
        self.assert_area_time_mapping(action, dispel, adapted_dispel[0])
        self.assertEqual(adapted_dispel[0]["damage_weight"], 0.0)
        self.assertAlmostEqual(sum(area["damage_weight"] for area in adapted_damage), 1.0)

    def test_celtie_preserves_the_two_direction_rectangle_and_wait_25_lifetime_31(self) -> None:
        action = self.source_action("celtie")
        self.assertEqual(len(action["hit_areas"]), 1)
        original = action["hit_areas"][0]
        self.assertEqual(self.area_wait(action, original), 25)
        self.assertEqual(self.area_lifetime(original), 31)
        self.assertEqual(self.area_hits(original), 1)
        self.assertEqual(original["shape_raw"][0], "Rectangle")
        original_width, original_length = map(fixed_range, original["shape_raw"][1:])
        self.assertEqual((original_width, original_length), (200.0, 3000.0))
        skill = self.heroes["celtie"]["main_skill"]
        self.assertEqual(skill["shape"], "rectangle")
        self.assertEqual(len(skill["timeline"]), 1)
        adapted = skill["timeline"][0]
        self.assert_area_time_mapping(action, original, adapted)
        self.assertEqual(adapted["shape"], "rectangle")
        self.assertGreater(adapted["half_length"], 0.0)
        self.assertAlmostEqual(adapted["width"] / original_width, (adapted["half_length"] * 2.0) / original_length)

    def test_hanabi_waits_55_then_creates_five_bombs_using_the_real_child_action(self) -> None:
        action = self.source_action("hanabi")
        self.assertEqual(len(action["bomb_summons"]), 1)
        summon = action["bomb_summons"][0]
        self.assertEqual(summon["count"], {"pointer": summon["pointer"] + "/1", "raw_value": 5})
        self.assertEqual(len(summon["wait_pointers"]), 1)
        wait = self.wait_value(action, summon["wait_pointers"][0])
        self.assertEqual(wait, 55)
        child_ref = summon["child_action_ref"]["raw_value"]
        self.assertEqual(child_ref, "battle/action/skill/action/rare4/kunoichi_multiball_2")
        self.assertEqual(summon["child_action_ref"]["pointer"], summon["pointer"] + "/6")
        self.assertIn(child_ref, self.skills["kunoichi:2"]["dependency_action_refs"])
        child = self.actions[child_ref]
        self.assertEqual(child["git_blob_sha1"], "58cf525774262fb0e8ca6e986a6745cc535820e8")
        self.assertEqual(child["git_blob_sha1"], self.sources[child["source_path"]]["git_blob_sha1"])
        self.assertEqual(len(child["hit_areas"]), 1)
        explosion = child["hit_areas"][0]
        self.assertEqual(explosion["shape_raw"][0], "Circle")
        self.assertEqual(fixed_range(explosion["shape_raw"][1]), 200.0)
        self.assertEqual(self.area_lifetime(explosion), 30)
        self.assertEqual(self.area_hits(explosion), 1)
        self.assertTrue(self.callback_has(child, explosion, "CreateNormalAttack"))
        skill = self.heroes["hanabi"]["main_skill"]
        self.assertEqual(skill["delivery"], "bombs")
        self.assertEqual(skill["projectiles"], summon["count"]["raw_value"])
        self.assertAlmostEqual(skill["cast_delay"], wait * PROJECT_SECONDS_PER_ACTION_UNIT, places=12)
        self.assertIn("简化", self.heroes["hanabi"]["adaptation_notes"])


if __name__ == "__main__":
    unittest.main()
