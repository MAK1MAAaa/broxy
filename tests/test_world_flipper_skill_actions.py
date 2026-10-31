"""Pinned action provenance, lossless structure extraction and safe caching."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("world_flipper_skill_actions", ROOT / "tools/world_flipper_skill_actions.py")
assert SPEC is not None and SPEC.loader is not None
ACTIONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ACTIONS)


def command(payload: list) -> list:
    return ["Command", payload]


def block(*instructions: list) -> list:
    return ["Block", list(instructions)]


def document(*instructions: list) -> list:
    return ["ActionDsl", 1, ["None"], False, False, False, False, False, False, False, 0, block(*instructions)]


def source_for(data: bytes, filename: str = "action.json") -> dict:
    return {"path": "assets/battle/action/test.action.dsl.json", "git_blob_sha1": ACTIONS.git_blob_sha1(data),
            "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), "cache_filename": filename}


class WorldFlipperSkillActionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads(ACTIONS.DEFAULT_MANIFEST.read_text(encoding="utf-8"))
        cls.catalog = json.loads(ACTIONS.DEFAULT_CATALOG.read_text(encoding="utf-8"))
        cls.index = json.loads(ACTIONS.DEFAULT_INDEX.read_text(encoding="utf-8"))

    def test_twelve_representatives_and_bomb_dependencies_are_pinned(self) -> None:
        manifest = self.manifest
        self.assertEqual(manifest["commit"], self.catalog["source"]["commit"])
        self.assertEqual(manifest["commit"], "1d45b529ef078ba9b1f876d4588debd0c8a9a214")
        self.assertEqual(len(manifest["sources"]), 1027)
        self.assertEqual(len(manifest["representative_source_paths"]), 26)
        samples = [source for source in manifest["sources"] if source["kind"] == "representative_skill_action"]
        self.assertEqual(len(samples), 24)
        self.assertEqual(len({source["dev_name"] for source in samples}), 12)
        self.assertFalse(manifest["scope"]["runtime_support_claim"])
        skills = {skill["id"]: skill for skill in self.catalog["skills"]}
        for source in manifest["sources"]:
            self.assertEqual(source["url"], ACTIONS.action_url(manifest["repository_full_name"], manifest["commit"], source["path"]))
            self.assertIn(manifest["commit"], source["display_url"])
            self.assertEqual(len(source["sha256"]), 64)
            self.assertEqual(len(source["git_blob_sha1"]), 40)
            self.assertGreater(source["bytes"], 0)
            for skill_id in source["skill_ids"]:
                self.assertEqual(skills[skill_id]["action_file"], {"path": source["path"], "git_blob_sha1": source["git_blob_sha1"]})
        for dev in {source["dev_name"] for source in samples}:
            self.assertEqual({source["rank"] for source in samples if source["dev_name"] == dev}, {1, 2})

    def test_compact_index_covers_all_variants_and_closes_all_eight_child_actions(self) -> None:
        index = self.index
        self.assertEqual(index["counts"], {"skill_variants": 1062, "unique_catalog_roots": 1019,
                                          "verified_actions": 1027, "child_only_actions": 8, "opcode_types": 55, "hit_areas": 1639})
        self.assertEqual(index["source"]["manifest_sha256"], hashlib.sha256(ACTIONS.json_bytes(self.manifest)).hexdigest())
        sources = {source["path"]: source for source in self.manifest["sources"]}
        actions = {action["action_ref"]: action for action in index["actions"]}
        self.assertEqual(len(actions), 1027)
        self.assertEqual({action["source_path"] for action in actions.values()}, set(sources))
        for action in actions.values():
            self.assertEqual(action["git_blob_sha1"], sources[action["source_path"]]["git_blob_sha1"])
            self.assertNotIn("raw_payload", action)
            for dependency in action["child_actions"]:
                self.assertIn(dependency["action_ref"], actions)
                self.assertTrue(dependency["pointers"])
        skills = {skill["skill_id"]: skill for skill in index["skills"]}
        self.assertEqual(set(skills), {skill["id"] for skill in self.catalog["skills"]})
        root_refs = set()
        for catalog_skill in self.catalog["skills"]:
            skill = skills[catalog_skill["id"]]
            self.assertEqual(skill["root_action_ref"], catalog_skill["action_ref"])
            self.assertEqual(skill["owner_character_ids"], catalog_skill["owner_character_ids"])
            root_refs.add(skill["root_action_ref"])
            reached = set()
            pending = [skill["root_action_ref"]]
            while pending:
                ref = pending.pop()
                if ref in reached:
                    continue
                reached.add(ref)
                pending.extend(dependency["action_ref"] for dependency in actions[ref]["child_actions"])
            expected_dependencies = reached - {skill["root_action_ref"]}
            self.assertEqual(set(skill["dependency_action_refs"]), expected_dependencies)
            expected_operations = {name for ref in reached for name in actions[ref]["operation_pointers"]}
            self.assertEqual(skill["all_opcodes"], sorted(expected_operations))
            self.assertNotIn("runtime_supported", skill)
        child_only = set(actions) - root_refs
        self.assertEqual(len(child_only), 8)
        self.assertEqual(child_only, {"battle/action/skill/action/rare4/docking_beast_xm19_multiball_1",
                                    "battle/action/skill/action/rare4/docking_beast_xm19_multiball_2",
                                    "battle/action/skill/action/rare4/illusionist_multiball_1",
                                    "battle/action/skill/action/rare4/illusionist_multiball_2",
                                    "battle/action/skill/action/rare4/kunoichi_multiball_1",
                                    "battle/action/skill/action/rare4/kunoichi_multiball_2",
                                    "battle/action/skill/action/rare5/ruin_girl_multiball_1",
                                    "battle/action/skill/action/rare5/ruin_girl_multiball_2"})

    def test_compact_hit_area_inventory_and_source_pointers_preserve_policy_variants(self) -> None:
        instruction_counts: dict[str, int] = {}
        shape_counts: dict[str, int] = {}
        policy_counts: dict[str, int] = {}
        lifetime_counts: dict[str, int] = {}
        for action in self.index["actions"]:
            all_pointers = {pointer for pointers in action["operation_pointers"].values() for pointer in pointers}
            for name, pointers in action["operation_pointers"].items():
                instruction_counts[name] = instruction_counts.get(name, 0) + len(pointers)
            wait_pointers = {wait["pointer"] for wait in action["waits"]}
            self.assertEqual(wait_pointers, set(action["operation_pointers"].get("Wait", [])))
            self.assertEqual({area["pointer"] for area in action["hit_areas"]}, set(action["operation_pointers"].get("CreateHitArea", [])))
            self.assertEqual({summon["pointer"] for summon in action.get("bomb_summons", [])}, set(action["operation_pointers"].get("CreateBombMultiball", [])))
            for summon in action.get("bomb_summons", []):
                self.assertEqual(summon["count"]["pointer"], summon["pointer"] + "/1")
                self.assertEqual(summon["child_action_ref"]["pointer"], summon["pointer"] + "/6")
                self.assertIn(summon["child_action_ref"]["raw_value"], {child["action_ref"] for child in action["child_actions"]})
                self.assertTrue(set(summon["wait_pointers"]).issubset(wait_pointers))
            for area in action["hit_areas"]:
                self.assertTrue(set(area["wait_pointers"]).issubset(wait_pointers))
                self.assertTrue({scope["owner"] for scope in area["scope"]}.issubset(all_pointers))
                for callback in area["callback_blocks"]:
                    self.assertEqual(callback["pointer"], area["pointer"] + "/" + str(callback["parameter_index"]))
                for field, counter in (("shape_raw", shape_counts), ("hit_policy_raw", policy_counts), ("lifetime_raw", lifetime_counts)):
                    tag = area[field][0]
                    counter[tag] = counter.get(tag, 0) + 1
        inventory = self.index["inventory"]
        self.assertEqual(instruction_counts, inventory["instruction_counts"])
        self.assertEqual(shape_counts, {"Circle": 983, "Rectangle": 626, "Sector": 30})
        self.assertEqual(policy_counts, {"CalculatedUsingMaxNumOfHits": 1482, "SpecifyMinHitIntervalDirectly": 157})
        self.assertEqual(lifetime_counts, {"SpecifyHitAreaLifetimeDirectly": 1637, "SpecifyHitAreaLifetimeSLv": 2})
        self.assertEqual(shape_counts, inventory["hit_area_shapes"])
        self.assertEqual(policy_counts, inventory["hit_policies"])
        self.assertEqual(lifetime_counts, inventory["hit_area_lifetimes"])

    def test_catalog_deduplication_preserves_all_rank_references(self) -> None:
        sources = ACTIONS.catalog_sources(self.catalog)
        self.assertEqual(len(sources), 1019)
        self.assertEqual(len(sources), self.manifest["scope"]["catalog_unique_action_paths"])
        self.assertEqual(sum(len(source["skill_ids"]) for source in sources), 1062)
        self.assertEqual({skill for source in sources for skill in source["skill_ids"]}, {skill["id"] for skill in self.catalog["skills"]})

    def test_hit_callbacks_preserve_order_scope_and_raw_wait_units(self) -> None:
        attack = ["CreateNormalAttack", 3, 255, None, None, 120, [{"max": 0.75, "min": 0.65}]]
        condition = ["CreateCondition", 3, [["ACToleranceOfElement", [{"max": 1800, "min": 1800}], 255, [{"max": -0.25, "min": -0.2}]]]]
        area = ["CreateHitArea", "*", 0, ["CD"], 0, 0, 0, False, False,
                ["Circle", [{"max": 250, "min": 250}]], ["Center"], ["Center"], ["Single"],
                ["SpecifyHitAreaLifetimeDirectly", 16], ["CalculatedUsingMaxNumOfHits", 4], ["Some", [{"max": 12, "min": 12}]],
                False, True, ["None"], 1, block(), 2, 3, block(command(attack), command(condition)), 0, 0, ["None"]]
        wait = ["Event", ["Wait", 42, "*", block(command(area))]]
        immediate = ["CreateCondition", -33, [["ACSkillDamage", [{"max": 900, "min": 900}], [{"max": 0.75, "min": 0.65}]]]]
        original = document(wait, command(immediate))
        extracted = ACTIONS.extract_action(original)
        instructions = extracted["instructions"]
        self.assertEqual([row["name"] for row in instructions], ["Wait", "CreateHitArea", "CreateNormalAttack", "CreateCondition", "CreateCondition"])
        region = instructions[1]
        self.assertEqual(region["wait_context"], [{"pointer": "/11/1/0/1", "delay_raw": 42, "selector_raw": "*"}])
        self.assertEqual(region["fields"]["shape"]["raw_value"], area[9])
        self.assertEqual(region["fields"]["lifetime"]["raw_value"], ["SpecifyHitAreaLifetimeDirectly", 16])
        self.assertEqual(region["fields"]["hit_policy"]["raw_value"], ["CalculatedUsingMaxNumOfHits", 4])
        self.assertEqual(region["fields"]["max_hits_raw"]["raw_value"], 4)
        self.assertEqual(region["fields"]["parameter_15_raw"]["raw_value"], area[15])
        callbacks = region["fields"]["callback_blocks"]
        self.assertEqual([row["parameter_index"] for row in callbacks], [20, 23])
        self.assertEqual(callbacks[1]["direct_instruction_pointers"], [instructions[2]["pointer"], instructions[3]["pointer"]])
        self.assertEqual(instructions[2]["scope"][-1]["role"], "hit_callback")
        self.assertEqual(instructions[3]["wait_context"], region["wait_context"])
        self.assertEqual(instructions[-1]["wait_context"], [])
        self.assertEqual(instructions[-1]["scope"], [])
        for row in instructions:
            self.assertEqual(ACTIONS.pointer_value(original, row["pointer"]), row["raw_payload"])
            for field in row["fields"].values():
                if isinstance(field, dict) and "pointer" in field:
                    self.assertEqual(ACTIONS.pointer_value(original, field["pointer"]), field["raw_value"])

        interval_area = [*area[:14], ["SpecifyMinHitIntervalDirectly", 6], *area[15:]]
        interval_fields = ACTIONS.extract_action(document(command(interval_area)))["instructions"][0]["fields"]
        self.assertEqual(interval_fields["min_hit_interval_raw"]["raw_value"], 6)
        self.assertNotIn("max_hits_raw", interval_fields)

    def test_nested_waits_and_unknown_operations_are_not_flattened_or_invented(self) -> None:
        payload = ["FutureOpcode", {"range": [{"max": 9, "min": 2}]}, ["UnknownTaggedEnum", 37]]
        original = document(["Event", ["Wait", 42, "*", block(["Event", ["Wait", 7, "?", block(command(payload))]])]])
        extracted = ACTIONS.extract_action(original)
        unknown = extracted["instructions"][-1]
        self.assertEqual(unknown["name"], "FutureOpcode")
        self.assertEqual(unknown["raw_payload"], payload)
        self.assertEqual(unknown["fields"], {})
        self.assertEqual([row["delay_raw"] for row in unknown["wait_context"]], [42, 7])
        self.assertNotIn("time_seconds", unknown)
        self.assertNotIn("UnknownTaggedEnum", extracted["instruction_counts"])
        self.assertEqual(extracted["root_header_raw"], original[:11])

    def test_dependency_pointers_cover_objects_and_preserve_json_pointer_escaping(self) -> None:
        ref = "battle/action/skill/child"
        original = document(command(["FutureOpcode", {"a/b~c": ref}, ref]))
        dependencies = ACTIONS.extract_action(original)["action_dependencies"]
        self.assertEqual(dependencies, [{"action_ref": ref, "pointers": ["/11/1/0/1/1/a~1b~0c", "/11/1/0/1/2"]}])
        for pointer in dependencies[0]["pointers"]:
            self.assertEqual(ACTIONS.pointer_value(original, pointer), ref)

    def test_hash_size_and_document_shape_mismatches_fail_closed(self) -> None:
        data = ACTIONS.json_bytes(document(command(["StopBall", 12])))
        source = source_for(data)
        self.assertEqual(ACTIONS.verified_action(data, source)[0], "ActionDsl")
        with self.assertRaisesRegex(ValueError, "Git blob SHA mismatch"):
            ACTIONS.verified_action(data + b"\n", source)
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            ACTIONS.verified_action(data, {**source, "sha256": "0" * 64})
        with self.assertRaisesRegex(ValueError, "Byte count mismatch"):
            ACTIONS.verified_action(data, {**source, "bytes": len(data) + 1})
        invalid = ACTIONS.json_bytes(["OtherDocument"])
        with self.assertRaisesRegex(ValueError, "Not an ActionDsl"):
            ACTIONS.verified_action(invalid, source_for(invalid))

    def test_cache_is_verified_offline_and_unsafe_paths_are_rejected(self) -> None:
        data = ACTIONS.json_bytes(document())
        source = source_for(data)
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "action.json").write_bytes(data)
            value, evidence = ACTIONS.load_action(source, self.manifest, cache, True)
            self.assertEqual(value, document())
            self.assertEqual(evidence["verified_git_blob_sha1"], source["git_blob_sha1"])
            (cache / "action.json").write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "Git blob SHA mismatch"):
                ACTIONS.load_action(source, self.manifest, cache, True)
            for filename in ("../escape.json", "/escape.json", "..\\escape.json", "C:/escape.json"):
                with self.assertRaises(ValueError):
                    ACTIONS.cache_file(cache, {**source, "cache_filename": filename})
            with self.assertRaises(FileNotFoundError):
                ACTIONS.load_action({**source, "cache_filename": "missing.json"}, self.manifest, cache, True)

    def test_unverified_download_never_enters_cache(self) -> None:
        data = ACTIONS.json_bytes(document())
        source = source_for(data)
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(ACTIONS.urllib.request, "urlopen", side_effect=lambda *args, **kwargs: io.BytesIO(b"bad bytes")) as fetch:
                with patch.object(ACTIONS.time, "sleep"):
                    with self.assertRaisesRegex(ValueError, "Git blob SHA mismatch"):
                        ACTIONS.load_action(source, self.manifest, Path(directory), False)
            self.assertEqual(fetch.call_count, 3)
            self.assertFalse((Path(directory) / "action.json").exists())

    def test_recursive_actions_are_looked_up_in_tree_and_cycles_terminate(self) -> None:
        child_ref = "battle/action/child"
        child_data = ACTIONS.json_bytes(document(command(["FutureOpcode", "battle/action/test"])))
        root_data = ACTIONS.json_bytes(document(command(["FutureOpcode", child_ref])))
        root = source_for(root_data)
        child_path = f"assets/{child_ref}.action.dsl.json"
        child = {"path": child_path, "git_blob_sha1": ACTIONS.git_blob_sha1(child_data)}
        tree = {"tree": [{"path": child_path, "sha": child["git_blob_sha1"], "type": "blob"}]}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "action.json").write_bytes(root_data)
            child_cache = ACTIONS.cache_file(cache, child)
            child_cache.parent.mkdir(parents=True)
            child_cache.write_bytes(child_data)
            report = ACTIONS.research([root], self.manifest, cache, True, 2, tree)
            self.assertEqual(report["verified_files"], 2)
            self.assertEqual(report["failure_count"], 0)
            self.assertEqual(report["unresolved_action_dependencies"], {})
            self.assertIn("no claim", report["interpretation_status"])

    def test_missing_child_is_reported_and_unpinned_paths_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            ACTIONS.dependency_source("battle/action/missing", {"tree": []})
        for commit, path in (("main", "assets/x"), (self.manifest["commit"], "assets/../x"), (self.manifest["commit"], "/assets/x")):
            with self.assertRaises(ValueError):
                ACTIONS.action_url("blead/wf-assets", commit, path)


if __name__ == "__main__":
    unittest.main()
