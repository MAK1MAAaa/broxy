from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("roster_bindings", ROOT / "tools/build_world_flipper_roster_skills.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class RosterBindingsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bindings = MODULE.read(MODULE.ADAPTATIONS)["characters"]
        self.document = MODULE.read(MODULE.PROFILES)
        self.profiles = {p["skill_id"]: p for p in self.document["profiles"]}
        self.skills = {s["id"]: s for s in MODULE.read(ROOT / "data/worldflipper/catalog.json")["skills"]}

    def build(self, binding: dict) -> bytes:
        return MODULE.resource(binding, self.profiles[binding["profile_id"]], self.skills[binding["profile_id"]], self.document["source_commit"])

    def test_generated_resources_match_registered_files_with_lf(self) -> None:
        for binding in self.bindings:
            data = self.build(binding)
            self.assertEqual(data, (ROOT / "data/heroes" / (binding["id"] + ".tres")).read_bytes())
            self.assertNotIn(b"\r", data)

    def test_exact_geometry_and_follow_policies_remain_distinct(self) -> None:
        expected = {"nasir": (105.0, 110.0, "caster_at_activation"), "mordiga": (150.0, 60.0, "fixed"), "falsche": (100.0, 0.0, "caster")}
        for binding in self.bindings:
            source = self.build(binding).decode("utf-8")
            line = next(line for line in source.splitlines() if line.startswith("main_skill = "))
            phase = json.loads(line.split(" = ", 1)[1])["timeline"][0]
            radius, offset, anchor = expected[binding["id"]]
            self.assertEqual((phase["radius"], phase["forward_offset"], phase["anchor"]), (radius, offset, anchor))

    def test_unknown_or_blocked_actions_are_not_generic_fallbacks(self) -> None:
        binding = self.bindings[0]
        profile = copy.deepcopy(self.profiles[binding["profile_id"]])
        profile["blockers"] = [{"opcode": "CreateRatioHeal"}]
        with self.assertRaises(ValueError):
            MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])

    def test_changed_source_identity_is_rejected(self) -> None:
        binding = copy.deepcopy(self.bindings[0])
        binding["canonical_id"] = "221008"
        with self.assertRaises(ValueError):
            self.build(binding)

    def test_variable_radius_requires_an_explicit_adapter(self) -> None:
        binding = self.bindings[0]
        profile = copy.deepcopy(self.profiles[binding["profile_id"]])
        profile["timeline"][0]["shape_source"][1][0]["min"] -= 1
        with self.assertRaises(ValueError):
            MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])

    def test_invalid_balance_and_paths_cannot_generate_resources(self) -> None:
        for key, value in [("id", "../escape"), ("damage", 0), ("damage", True), ("cooldown", float("nan")), ("geometry_scale", True), ("geometry_scale", -1)]:
            binding = copy.deepcopy(self.bindings[0])
            binding[key] = value
            with self.assertRaises(ValueError, msg=key):
                self.build(binding)

    def test_original_art_alias_cannot_be_rebound_to_another_real_profile(self) -> None:
        binding = copy.deepcopy(self.bindings[0])
        binding.update(canonical_id="221008", profile_id="desert_wizard:2")
        with self.assertRaisesRegex(ValueError, "original-art alias"):
            self.build(binding)

    def test_forged_root_phase_and_commit_evidence_is_rejected(self) -> None:
        binding = self.bindings[0]
        for field, value in [("git_blob_sha1", "0" * 40), ("sha256", "0" * 64), ("url", "https://example.com/action"), ("repository_path", "assets/other"), ("json_pointer", "/11/1")]:
            profile = copy.deepcopy(self.profiles[binding["profile_id"]])
            profile["root_source"][field] = value
            with self.assertRaises(ValueError, msg=field):
                MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])
        profile = copy.deepcopy(self.profiles[binding["profile_id"]])
        profile["timeline"][0]["source"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Phase evidence"):
            MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])
        with self.assertRaisesRegex(ValueError, "source commit"):
            MODULE.resource(binding, self.profiles[binding["profile_id"]], self.skills[binding["profile_id"]], "0" * 40)

    def test_invalid_phase_types_budgets_and_source_relationships_are_rejected(self) -> None:
        cases = [("delay", True), ("delay", float("nan")), ("delay", -1), ("delay", 31),
                 ("delay", 27.0), ("duration", False), ("duration", 0), ("duration", 11),
                 ("hits", True), ("hits", 1.0), ("hits", 0), ("hits", 33),
                 ("maximum_hits", True), ("damage_weight", True), ("damage_weight", float("inf")),
                 ("damage_weight", 0), ("damage_weight", 2), ("damage_weight", 0.5),
                 ("anchor", "unknown"), ("anchor", "fixed"), ("delay_source_units", 0),
                 ("lifetime_source_units", 600), ("origin_offset_source", [0, -221])]
        binding = self.bindings[0]
        for key, value in cases:
            profile = copy.deepcopy(self.profiles[binding["profile_id"]])
            profile["timeline"][0][key] = value
            with self.assertRaises(ValueError, msg=f"{key}={value}"):
                MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])
        for value in (True, float("nan"), float("inf"), -1, 0):
            profile = copy.deepcopy(self.profiles[binding["profile_id"]])
            profile["timeline"][0]["shape_source"][1][0] = {"min": value, "max": value}
            with self.assertRaises(ValueError, msg=f"radius={value}"):
                MODULE.resource(binding, profile, self.skills[binding["profile_id"]], self.document["source_commit"])

    def test_source_index_is_reconstructed_before_a_ready_profile_is_trusted(self) -> None:
        catalog = MODULE.read(ROOT / "data/worldflipper/catalog.json")
        aliases = MODULE.read(MODULE.ALIASES)
        lock = MODULE.read(MODULE.SOURCE_LOCK)
        index = MODULE.read(MODULE.COMPILER.DSL.DEFAULT_INDEX)
        animations = MODULE.read(ROOT / "tools/world_flipper_character_animation_sources.json")
        cache = MODULE.COMPILER.DSL.DEFAULT_CACHE
        if any(not MODULE.COMPILER.DSL.cache_file(cache, source).is_file() for source in lock["sources"]):
            self.skipTest("Original action cache is local-only; source reconstruction is verified in the prepared workspace")
        MODULE.validate_inputs(self.document, catalog, aliases, lock, index, animations, cache)
        mutations = [lambda d: d["input_hashes"].update(catalog="0" * 64),
                     lambda d: d.update(source_commit="0" * 40),
                     lambda d: next(p for p in d["profiles"] if p["canonical_id"] == "211012")["timeline"][0].update(delay=0.0)]
        for mutate in mutations:
            document = copy.deepcopy(self.document)
            mutate(document)
            with self.assertRaisesRegex(ValueError, "verified source reconstruction"):
                MODULE.validate_inputs(document, catalog, aliases, lock, index, animations, cache)
        aliases = copy.deepcopy(aliases)
        aliases["heroes"][0]["canonical_id"] = "111003"
        with self.assertRaisesRegex(ValueError, "canonical original character"):
            MODULE.validate_inputs(self.document, catalog, aliases, lock, index, animations, cache)

    def test_main_cannot_write_before_source_validation(self) -> None:
        with mock.patch("sys.argv", ["build_world_flipper_roster_skills.py"]), mock.patch.object(MODULE, "validate_inputs", side_effect=ValueError("invalid source chain")) as validate, mock.patch.object(Path, "write_bytes") as write:
            with self.assertRaisesRegex(ValueError, "invalid source chain"):
                MODULE.main()
            validate.assert_called_once()
            write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
