"""Coverage claims must not turn archived identities into completed gameplay."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("wf_coverage", ROOT / "tools/audit_world_flipper_coverage.py")
assert SPEC is not None and SPEC.loader is not None
COVERAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COVERAGE)


class WorldFlipperCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = json.loads(COVERAGE.CATALOG.read_text(encoding="utf-8"))
        cls.ledger = json.loads(COVERAGE.LEDGER.read_text(encoding="utf-8"))

    def test_every_canonical_identity_is_explicitly_claimed_or_pending(self) -> None:
        checked = COVERAGE.audit(self.catalog, self.ledger)
        self.assertEqual(COVERAGE.encoded(checked), COVERAGE.LEDGER.read_bytes())
        for category, original in COVERAGE.canonical_sets(self.catalog).items():
            claimed = {item["canonical_id"] for item in checked["claims"][category]}
            pending = set(checked["pending_ids"][category])
            self.assertEqual(claimed | pending, set(original))
            self.assertFalse(claimed & pending)
            self.assertEqual(len(pending), checked["counts"][category]["pending"])
            self.assertEqual(len(original), checked["counts"][category]["canonical"])
        self.assertFalse(checked["fully_complete"])

    def test_all_four_existing_characters_keep_original_identity_and_explicit_gaps(self) -> None:
        claims = {item["game_id"]: item for item in self.ledger["claims"]["characters"]}
        for game_id, canonical_id in {"alk": "1", "clarisse": "111003", "celtie": "141001", "hanabi": "211003"}.items():
            self.assertEqual(claims[game_id]["canonical_id"], canonical_id)
            self.assertEqual(claims[game_id]["status"], "partial")
            self.assertTrue(claims[game_id]["remaining_gaps"])
        self.assertIn("15击", claims["clarisse"]["notes"])
        self.assertIn("逐次命中火弱点", claims["clarisse"]["notes"])
        self.assertIn("临时正面强化驱散", claims["clarisse"]["notes"])
        self.assertFalse(any("驱散尚未实现" in gap for gap in claims["clarisse"]["remaining_gaps"]))
        self.assertIn("矩形", claims["celtie"]["notes"])
        self.assertIn("前摇55单位", claims["hanabi"]["notes"])
        self.assertIn("持续30单位", claims["hanabi"]["notes"])
        self.assertTrue(any("MB反射" in gap for gap in claims["hanabi"]["remaining_gaps"]))
        for category in ("characters", "skills", "layouts"):
            self.assertTrue(all(not entry["runtime_verified"] for entry in COVERAGE.bootstrap(self.catalog)["claims"][category]))

    def test_new_three_characters_bind_canonical_profiles_without_claiming_original_levels(self) -> None:
        context = COVERAGE.validate_profile_context(self.catalog, ROOT)
        self.assertEqual(set(context), {"nasir", "mordiga", "falsche"})
        characters = {item["game_id"]: item for item in self.ledger["claims"]["characters"]}
        self.assertEqual(len(characters), 7)
        expected = {"nasir": ("211012", "magic_sword_girl:2"),
                    "mordiga": ("221008", "desert_wizard:2"),
                    "falsche": ("361001", "reaper_girl:2")}
        for game_id, (canonical_id, profile_id) in expected.items():
            claim = characters[game_id]
            self.assertEqual(claim["canonical_id"], canonical_id)
            self.assertEqual(claim["source_profile"], context[game_id])
            self.assertEqual(context[game_id]["profile_id"], profile_id)
            self.assertEqual(context[game_id]["geometry_scale"], 0.5)
            self.assertEqual(context[game_id]["project_seconds_per_source_unit"], 1 / 60)
            self.assertIn(canonical_id, claim["notes"])
            self.assertIn(profile_id, claim["notes"])
            self.assertEqual(claim["status"], "partial")
            self.assertTrue(any("等级" in gap for gap in claim["remaining_gaps"]))
            self.assertTrue(any("ShowEffect" in gap for gap in claim["remaining_gaps"]))
            skills = [entry for entry in self.ledger["claims"]["skills"] if entry["game_id"] == "hero_" + game_id]
            self.assertEqual(len(skills), 2)
            for skill in skills:
                self.assertEqual(skill["source_profile"], context[game_id])
                self.assertEqual(skill["status"], "partial")
                self.assertIn("原作等级变体尚未独立实现", skill["notes"])
        self.assertTrue(any("StopBall" in gap for gap in characters["nasir"]["remaining_gaps"]))
        self.assertTrue(any("23尚未解码" in gap for gap in characters["falsche"]["remaining_gaps"]))

    def test_background_preparation_and_equipment_decoding_do_not_expand_playable_claims(self) -> None:
        claims = COVERAGE.bootstrap(self.catalog)["claims"]
        self.assertEqual(len(claims["characters"]), 7)
        self.assertEqual(len(claims["skills"]), 14)
        self.assertTrue(all(entry["status"] == "partial" for category in ("characters", "skills") for entry in claims[category]))
        self.assertEqual(len(claims["fields"]), 4)
        self.assertEqual(len(claims["layouts"]), 3)
        self.assertEqual(len(claims["equipment"]), 16)
        self.assertEqual(sum(entry["status"] == "adapted_playable" for entry in claims["equipment"]), 8)
        self.assertFalse(any("world_flipper_background_sources" in entry["resource"] for entries in claims.values() for entry in entries))

    def test_old_weapon_skins_cannot_count_as_implemented_original_equipment_effects(self) -> None:
        claims = {item["game_id"]: item for item in self.ledger["claims"]["equipment"]}
        old = {"bone": "3010053", "frost": "5030036", "ember": "5060034", "scatter": "5040026", "crescent": "5020037", "storm": "4050031", "comet": "5030039", "return_ring": "5090030"}
        for game_id, canonical_id in old.items():
            self.assertEqual(claims[game_id]["canonical_id"], canonical_id)
            self.assertEqual(claims[game_id]["status"], "partial")
            self.assertIn("原作装备被动尚未实现", claims[game_id]["remaining_gaps"])
        new = [item for item in claims.values() if item["game_id"] not in old]
        self.assertEqual(len(new), 8)
        self.assertTrue(all(item["status"] == "adapted_playable" for item in new))

    def test_map_background_reuse_is_not_reported_as_all_original_layouts(self) -> None:
        mapped = {item["game_id"]: item for item in self.ledger["claims"]["fields"]}
        self.assertEqual(mapped["reliquary"]["canonical_id"], "sand_ruins")
        self.assertEqual(mapped["mire"]["canonical_id"], "japan_shrine")
        self.assertEqual(mapped["ashland"]["canonical_id"], "sea_ship_boss")
        self.assertEqual(mapped["town"]["canonical_id"], "common_skill_preview")
        self.assertTrue(all(item["status"] == "partial" and item["remaining_gaps"] for item in mapped.values()))
        self.assertEqual({item["canonical_id"] for item in self.ledger["claims"]["layouts"]}, {"main_2_9_5", "main_3_6_2", "main_6_6_2"})
        self.assertEqual(self.ledger["counts"]["layouts"]["pending"], 1419)
        unmapped = {item["game_id"] for item in self.ledger["unmapped_game_content"]}
        self.assertEqual(unmapped, {"glacier", "throne", "tower_peak"})

    def test_three_real_layout_claims_match_exact_sources_and_remain_partial(self) -> None:
        context = COVERAGE.validate_layout_context(self.catalog, ROOT)
        self.assertEqual(set(context), set(COVERAGE.LAYOUT_TARGETS))
        registry = COVERAGE.read_json(ROOT / "tools/world_flipper_layout_sources.json")
        self.assertEqual(len(registry["sources"]), 28)
        manifest = COVERAGE.read_json(ROOT / "assets/worldflipper/stages/manifest.json")
        self.assertEqual(len(manifest["sources"]), 12)
        self.assertEqual(len(manifest["assets"]), 6)
        for claim in self.ledger["claims"]["layouts"]:
            self.assertEqual(claim["canonical_id"], context[claim["game_id"]]["canonical_id"])
            self.assertEqual(claim["source"], context[claim["game_id"]]["source"])
            self.assertEqual(claim["resource"], "data/arenas.json")
            self.assertEqual(claim["status"], "partial")
            for term in ("碰撞", "机关", "敌人", "日服"):
                self.assertTrue(any(term in gap for gap in claim["remaining_gaps"]))

    def _reject_document_change(self, relative: str, mutate) -> None:
        original_read = COVERAGE.read_json
        path = ROOT / relative
        changed = copy.deepcopy(original_read(path))
        mutate(changed)

        def read_json(candidate: Path):
            return changed if candidate.resolve() == path.resolve() else original_read(candidate)

        with mock.patch.object(COVERAGE, "read_json", side_effect=read_json):
            with self.assertRaises(ValueError):
                COVERAGE.audit(self.catalog, self.ledger)

    def test_profile_identity_action_bytes_geometry_and_time_cannot_drift(self) -> None:
        def profile(document):
            return next(row for row in document["profiles"] if row["skill_id"] == "magic_sword_girl:2")

        for mutation in [
            lambda document: profile(document).update(canonical_id="221008"),
            lambda document: profile(document).update(action_ref="battle/action/invented"),
            lambda document: profile(document)["root_source"].update(git_blob_sha1="0" * 40),
            lambda document: profile(document)["root_source"].update(sha256="0" * 64),
            lambda document: profile(document).update(runtime_profile_ready=False),
            lambda document: profile(document)["timeline"][0]["shape_source"][1][0].update(min=200, max=200),
            lambda document: profile(document)["timeline"][0].update(delay=0.0),
            lambda document: profile(document)["timeline"][0].update(duration=0.1),
            lambda document: profile(document)["timeline"][0].update(hits=2),
            lambda document: document["time_policy"].update(project_seconds_per_source_unit=1 / 30),
            lambda document: document["time_policy"].update(original_units_verified=True),
        ]:
            with self.subTest(mutation=mutation):
                self._reject_document_change("data/worldflipper/action_profiles.json", mutation)
        for mutation in [
            lambda document: document["characters"][0].update(canonical_id="221008"),
            lambda document: document["characters"][0].update(profile_id="desert_wizard:2"),
            lambda document: document["characters"][0].update(geometry_scale=0.25),
            lambda document: document["characters"][0].update(damage=900.0),
            lambda document: document["characters"][0].update(cooldown=1.0),
        ]:
            self._reject_document_change("data/worldflipper/roster_adaptations.json", mutation)

    def test_playable_profile_resource_and_ledger_cannot_hide_changed_bindings(self) -> None:
        resource = ROOT / "data/heroes/nasir.tres"
        original_read = Path.read_bytes
        content = original_read(resource)
        for old, new in [(b'"radius": 105.0', b'"radius": 205.0'),
                         (b'"forward_offset": 110.0', b'"forward_offset": 0.0'),
                         (b'"delay": 0.4666666666666667', b'"delay": 0.0'),
                         (b'source_id = "211012"', b'source_id = "221008"')]:
            self.assertIn(old, content)
            changed = content.replace(old, new, 1)

            def read_bytes(path: Path) -> bytes:
                return changed if path.resolve() == resource.resolve() else original_read(path)

            with mock.patch.object(Path, "read_bytes", read_bytes), self.assertRaises(ValueError):
                COVERAGE.audit(self.catalog, self.ledger)
        for category, game_id in [("characters", "nasir"), ("skills", "hero_nasir")]:
            for change in [{"status": "adapted_playable"}, {"remaining_gaps": []}, {"source_profile": {}},
                           {"status": "complete", "remaining_gaps": [], "runtime_verified": True, "notes": "完成"}]:
                changed_ledger = copy.deepcopy(self.ledger)
                next(row for row in changed_ledger["claims"][category] if row["game_id"] == game_id).update(change)
                with self.assertRaises(ValueError):
                    COVERAGE.audit(self.catalog, changed_ledger)

    def test_wrong_real_stage_layout_layer_field_transform_or_wall_count_is_rejected(self) -> None:
        mutations = [
            lambda stage: stage.update(layout_id="main_3_6_2"),
            lambda stage: stage.update(layer_index=1),
            lambda stage: stage.update(field_id="japan_shrine"),
            lambda stage: stage.update(source_id="terrain_main_chapter_06_06_02"),
            lambda stage: stage.update(logic_scale=1.0),
            lambda stage: stage.update(logic_offset=[0.0, 0.0]),
            lambda stage: stage.update(native_bounds=[0, 0, 180, 320]),
            lambda stage: stage.update(play_bounds=[280, -275, 1440, 1280]),
            lambda stage: stage.update(wall_segment_count=4),
        ]
        for mutation in mutations:
            def change(arenas):
                mutation(next(arena for arena in arenas if arena["id"] == "jp_sand_2_9_5")["stage"])
            self._reject_document_change("data/arenas.json", change)

    def test_missing_or_altered_original_geometry_and_unpinned_source_are_rejected(self) -> None:
        for mutation in [
            lambda document: document["layouts"][0].update(layers=[]),
            lambda document: document["layouts"][0]["layers"][0].update(walls=[]),
            lambda document: document["layouts"][0]["layers"][0].update(bounds=[]),
            lambda document: document["layouts"][0]["layers"][0].update(objects=[]),
            lambda document: document["layouts"][0].update(terrain_ref="battle/terrain/invented"),
            lambda document: document["layouts"][0]["background"].update(ref="battle/field/invented"),
        ]:
            self._reject_document_change("data/worldflipper/layouts.json", mutation)
        for mutation in [
            lambda registry: registry["sources"].pop(),
            lambda registry: registry["sources"][0].update(url="https://example.invalid/terrain.json"),
            lambda registry: registry["sources"][0].update(sha256="0" * 64),
        ]:
            self._reject_document_change("tools/world_flipper_layout_sources.json", mutation)

    def test_stage_asset_manifest_must_retain_original_scale_sources_and_actual_png_hash(self) -> None:
        for mutation in [
            lambda manifest: manifest["assets"][0].update(source_pixel_scale=3),
            lambda manifest: manifest["assets"][0].update(sha256="0" * 64),
            lambda manifest: manifest["assets"][0].update(source_ids=[]),
            lambda manifest: manifest["sources"].pop(),
            lambda manifest: manifest["sources"][0].update(url="https://example.invalid/background.png"),
            lambda manifest: manifest["stages"][0].update(props=[]),
        ]:
            self._reject_document_change("assets/worldflipper/stages/manifest.json", mutation)

    def test_layout_completion_and_unimplemented_chapters_cannot_be_invented(self) -> None:
        for mutation in [
            lambda data: data["claims"]["layouts"][0].update(source="https://example.invalid/terrain.json"),
            lambda data: data["claims"]["layouts"][0].update(canonical_id="main_3_6_2"),
            lambda data: data["claims"]["layouts"][0].update(resource="data/worldflipper/layouts.json"),
            lambda data: data["claims"]["layouts"][0].update(status="adapted_playable", remaining_gaps=[]),
            lambda data: data["claims"]["layouts"][0].update(status="complete", remaining_gaps=[], runtime_verified=True, notes="完成"),
        ]:
            changed = copy.deepcopy(self.ledger)
            mutation(changed)
            with self.assertRaises(ValueError):
                COVERAGE.audit(self.catalog, changed)
        changed = copy.deepcopy(self.ledger)
        changed["claims"]["chapters"].append({"canonical_id": self.catalog["maps"]["chapters"][0]["id"],
            "game_id": "invented_chapter", "resource": "data/arenas.json", "source": "https://worldflipper.jp/demo/",
            "notes": "占位声明", "status": "partial", "runtime_verified": False, "remaining_gaps": ["未实现"]})
        with self.assertRaisesRegex(ValueError, "chapters have no implemented"):
            COVERAGE.audit(self.catalog, changed)

    def test_offline_audit_does_not_require_ignored_raw_caches(self) -> None:
        original_is_file = Path.is_file

        def is_file(path: Path) -> bool:
            return False if "wf-layout-research" in path.parts else original_is_file(path)

        with mock.patch.object(Path, "is_file", is_file):
            checked = COVERAGE.audit(self.catalog, self.ledger)
        self.assertEqual(checked, self.ledger)

    def test_invalid_identity_empty_source_and_false_completion_claims_fail(self) -> None:
        mutations = [
            lambda data: data["claims"]["characters"].append(copy.deepcopy(data["claims"]["characters"][0])),
            lambda data: data["claims"]["equipment"][0].update(canonical_id="unknown"),
            lambda data: data["claims"]["equipment"][0].update(source=""),
            lambda data: data["claims"]["characters"][0].update(status="complete"),
            lambda data: data["claims"]["characters"][0].update(canonical_id="111003"),
            lambda data: data["claims"]["fields"][0].update(source="https://example.invalid/incorrect.png"),
            lambda data: data["claims"]["equipment"][0].update(resource="../../outside-workspace.tres"),
        ]
        for mutation in mutations:
            data = copy.deepcopy(self.ledger)
            mutation(data)
            with self.assertRaises(ValueError):
                COVERAGE.audit(self.catalog, data)

    def test_runtime_verification_requires_a_real_successful_report(self) -> None:
        data = copy.deepcopy(self.ledger)
        data["runtime_evidence"] = None
        data["claims"]["equipment"][0]["runtime_verified"] = True
        with self.assertRaisesRegex(ValueError, "concrete validation report"):
            COVERAGE.audit(self.catalog, data)
        data["runtime_evidence"] = {"report": "reports/missing-validation.json", "sha256": "0" * 64}
        with self.assertRaisesRegex(ValueError, "missing, stale or unsuccessful"):
            COVERAGE.audit(self.catalog, data)


if __name__ == "__main__":
    unittest.main()
