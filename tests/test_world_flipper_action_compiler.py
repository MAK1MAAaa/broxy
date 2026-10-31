"""Pending source plans cannot silently substitute unsupported game mechanics."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_action_compiler", ROOT / "tools/compile_world_flipper_actions.py")
assert SPEC is not None and SPEC.loader is not None
COMPILER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPILER)


def command(payload: list) -> list:
    return ["Command", payload]


def block(*instructions: list) -> list:
    return ["Block", list(instructions)]


def area(radius: int = 210, hits: int = 1, coefficient: float = 38.0) -> list:
    attack = ["CreateNormalAttack", 2, 255, None, None, 255, [{"max": coefficient, "min": coefficient}],
              [{"max": 0, "min": 0}], False, False, False, False, False,
              [{"max": 30, "min": 30}], [{"max": 10, "min": 10}], ["Fire"], True]
    return ["CreateHitArea", "*", -18, ["AB"], 0, -220, 0, False, False,
            ["Circle", [{"max": radius, "min": radius}]], ["Center"], ["Center"], ["Single"],
            ["SpecifyHitAreaLifetimeDirectly", 20], ["CalculatedUsingMaxNumOfHits", hits], ["Some", [{"max": 1, "min": 1}]],
            False, True, ["None"], 0, block(), 1, 2, block(command(attack)), 0, 0, ["None"]]


def document(*instructions: list) -> list:
    return ["ActionDsl", 1, ["None"], False, False, False, False, False, False, False, 0, block(*instructions)]


def delayed(region: list, delay: int) -> list:
    return ["Event", ["Wait", delay, "*", block(command(region))]]


class WorldFlipperActionCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.plans = json.loads(COMPILER.OUTPUT.read_text(encoding="utf-8"))
        cls.lock = json.loads(COMPILER.DSL.DEFAULT_MANIFEST.read_text(encoding="utf-8"))
        cls.index = json.loads(COMPILER.DSL.DEFAULT_INDEX.read_text(encoding="utf-8"))

    def test_full_inventory_is_accounted_for_without_implementation_claims(self) -> None:
        plans = self.plans
        self.assertEqual(plans["counts"], {"catalog_variants": 1062, "verified_source_actions": 1027,
            "source_opcode_types": 55, "static_representative_ready_variants": 6,
            "static_representative_ready_characters": 3, "profile_records": 12, "implemented_by_this_compiler": 0})
        self.assertEqual({row["skill_id"] for row in plans["variants"]}, {row["skill_id"] for row in self.index["skills"]})
        self.assertEqual(set(plans["ready_character_ids"]), {"211012", "221008", "361001"})
        self.assertFalse(plans["runtime_routes"]["general_dsl_interpreter_implemented"])
        for row in plans["variants"]:
            self.assertEqual(row["status"], "pending")
        for profile in plans["profiles"]:
            self.assertEqual(profile["status"], "pending")
            self.assertFalse(profile["complete_original_action"])
            self.assertTrue(profile["remaining_gaps"])

    def test_all_fifty_five_opcodes_have_honest_routes(self) -> None:
        routes = self.plans["runtime_routes"]
        groups = [set(routes[key]) for key in ("existing_partial_mechanism_families", "project_presentation_policy", "movement_or_visibility_policy_required", "missing_primitive_families")]
        self.assertEqual(set.union(*groups), set(self.index["inventory"]["instruction_counts"]))
        self.assertEqual(len(groups[-1]), 41)
        for name in ("MoveBall", "MoveHitArea", "Repeat", "CreateRatioHeal", "AddSkillPoint", "CreateSummonsMultiball", "CreateBarrier"):
            self.assertIn(name, groups[-1])

    def test_ready_profiles_retain_distinct_original_geometry_and_time(self) -> None:
        profiles = {row["canonical_id"]: row for row in self.plans["profiles"]}
        expected = {"211012": ("fire", 28, 20, 1, 210, [0, -220], "caster_at_activation"),
                    "221008": ("water", 38, 50, 1, 300, [0, -120], "fixed"),
                    "361001": ("dark", 0, 600, 30, 200, [0, 0], "caster")}
        for identifier, (element, delay, lifetime, hits, radius, offset, anchor) in expected.items():
            profile = profiles[identifier]
            self.assertTrue(profile["runtime_profile_ready"])
            self.assertEqual(profile["element"], element)
            self.assertEqual(profile["dependencies"], [])
            self.assertEqual(len(profile["timeline"]), 1)
            phase = profile["timeline"][0]
            self.assertEqual(phase["shape_source"], ["Circle", [{"max": radius, "min": radius}]])
            self.assertEqual(phase["origin_offset_source"], offset)
            self.assertEqual(phase["anchor"], anchor)
            self.assertEqual(phase["hits"], hits)
            self.assertAlmostEqual(phase["delay"], delay / 60.0)
            self.assertAlmostEqual(phase["duration"], lifetime / 60.0)
            self.assertAlmostEqual(phase["damage_weight"], 1.0)
            self.assertIsNone(phase["geometry_scale"])
            self.assertIsNone(phase["project_damage"])
            self.assertEqual(profile["animations"]["three_pose_sources_verified"], True)
            self.assertEqual({row["pose"]: row["frame_count"] for row in profile["animations"]["poses"]}, {"neutral": 1, "walk_front": 4, "walk_back": 4})
        self.assertIn("StopBall", {row["opcode"] for row in profiles["211012"]["source_command_gaps"]})

    def test_source_evidence_binds_every_node_and_phase_to_the_fixed_blob(self) -> None:
        sources = {row["path"]: row for row in self.lock["sources"]}
        for profile in self.plans["profiles"]:
            for source in [profile["root_source"], *(row["source"] for row in profile["nodes"]), *(row["source"] for row in profile["timeline"])]:
                self.assertEqual(source["status"], "pending")
                locked = sources[source["repository_path"]]
                for key in ("git_blob_sha1", "sha256", "url"):
                    self.assertEqual(source[key], locked[key])
                self.assertTrue(source["json_pointer"].startswith("/11"))

    def test_single_area_lowers_without_fabricating_project_balance(self) -> None:
        record = COMPILER.DSL.extract_action(document(delayed(area(), 28)))
        plan = COMPILER.lower_static_action(record)
        self.assertTrue(plan["runtime_profile_ready"])
        self.assertEqual(plan["timeline"][0]["delay_source_units"], 28)
        self.assertIsNone(plan["timeline"][0]["project_damage"])
        self.assertEqual(plan["timeline"][0]["opaque_parameter_15_source"], ["Some", [{"max": 1, "min": 1}]])

    def test_unknown_gameplay_cannot_be_replaced_by_a_generic_area(self) -> None:
        record = COMPILER.DSL.extract_action(document(delayed(area(), 28), command(["FutureOpcode", 17])))
        plan = COMPILER.lower_static_action(record)
        self.assertFalse(plan["runtime_profile_ready"])
        self.assertEqual(plan["timeline"], [])
        self.assertIn("unsupported_gameplay_opcode:FutureOpcode", {row["code"] for row in plan["blockers"]})

    def test_multi_instance_and_conditional_attacks_are_blocked(self) -> None:
        variants = []
        placement = area()
        placement[12] = ["Circle", 8, 200]
        variants.append(placement)
        conditional = area()
        conditional[23][1][0][1][3] = [8194, 8197, 8200]
        variants.append(conditional)
        for region in variants:
            plan = COMPILER.lower_static_action(COMPILER.DSL.extract_action(document(command(region))))
            self.assertFalse(plan["runtime_profile_ready"])
            self.assertEqual(plan["timeline"], [])

    def test_nested_wait_clocks_are_not_silently_summed(self) -> None:
        source = document(["Event", ["Wait", 30, "*", block(delayed(area(), 24))]])
        plan = COMPILER.lower_static_action(COMPILER.DSL.extract_action(source))
        self.assertFalse(plan["runtime_profile_ready"])
        self.assertIn("nested_or_variable_wait_requires_clock_policy", {row["code"] for row in plan["blockers"]})

    def test_hit_callback_cannot_discard_its_own_wait_or_scope(self) -> None:
        for delay in (0, 12):
            region = area()
            attack = region[23][1][0]
            region[23] = block(["Event", ["Wait", delay, "*", block(attack)]])
            record = COMPILER.DSL.extract_action(document(delayed(region, 28)))
            plan = COMPILER.lower_static_action(record)
            self.assertFalse(plan["runtime_profile_ready"])
            self.assertEqual(plan["timeline"], [])
            self.assertIn("hit_callback_requires_direct_unconditional_attack", {row["code"] for row in plan["blockers"]})

    def test_caster_anchor_requires_separate_review(self) -> None:
        region = area(radius=200, hits=30, coefficient=4.0 / 3.0)
        region[4:9] = [0, 0, 0, True, True]
        region[13] = ["SpecifyHitAreaLifetimeDirectly", 600]
        record = COMPILER.DSL.extract_action(document(command(region)))
        self.assertFalse(COMPILER.lower_static_action(record)["runtime_profile_ready"])
        plan = COMPILER.lower_static_action(record, reviewed_caster_anchor=True)
        self.assertTrue(plan["runtime_profile_ready"])
        self.assertEqual(plan["timeline"][0]["anchor"], "caster")
        self.assertEqual(plan["timeline"][0]["duration"], 10.0)
        self.assertEqual(len(COMPILER.REVIEWED_CASTER_SOURCES), 2)

    def test_relative_original_damage_weights_are_preserved(self) -> None:
        first = area(radius=200, hits=4, coefficient=0.75)
        second = area(radius=300, hits=11, coefficient=17.0 / 11.0)
        plan = COMPILER.lower_static_action(COMPILER.DSL.extract_action(document(delayed(first, 42), delayed(second, 79))))
        self.assertTrue(plan["runtime_profile_ready"])
        self.assertEqual([phase["delay_source_units"] for phase in plan["timeline"]], [42, 79])
        self.assertAlmostEqual(plan["timeline"][0]["damage_weight"], 0.15)
        self.assertAlmostEqual(plan["timeline"][1]["damage_weight"], 0.85)

    def test_block_references_are_real_json_pointers_not_generated_ast_paths(self) -> None:
        source = document(delayed(area(), 28))
        record = COMPILER.DSL.extract_action(source)
        wait = record["instructions"][0]
        pruned = [COMPILER._prune_blocks(value, f"{wait['pointer']}/{index}") for index, value in enumerate(wait["raw_payload"][1:], 1)]
        pointer = pruned[-1]["source_block_pointer"]
        self.assertEqual(COMPILER.DSL.pointer_value(source, pointer)[0], "Block")

    def test_generated_sources_use_utf8_lf(self) -> None:
        for path in (ROOT / "tools/compile_world_flipper_actions.py", ROOT / "tests/test_world_flipper_action_compiler.py", COMPILER.OUTPUT):
            data = path.read_bytes()
            data.decode("utf-8")
            self.assertNotIn(b"\r\n", data)


if __name__ == "__main__":
    unittest.main()
