"""Original interaction pixels, adapted timing and outer-only landmark regressions."""
from __future__ import annotations

from copy import deepcopy
import fnmatch
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/worldflipper"
IDS = ("ball", "barrel", "chest", "health", "charge", "mana")


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(path: Path) -> Image.Image:
    with Image.open(path) as raw:
        return raw.convert("RGBA")


def module(name: str):
    spec = importlib.util.spec_from_file_location(name + "_test", ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def fixture_sources(directory: Path) -> tuple[list[dict], dict[str, Path]]:
    sources = deepcopy(read(ROOT / "tools/world_flipper_interactions_sources.json")["sources"])
    paths: dict[str, Path] = {}
    for source in sources:
        image = Image.new("RGBA", tuple(source["source_size"]))
        draw = ImageDraw.Draw(image)
        for index, entry in enumerate(source["frames"]):
            if source["game_id"] == "barrel" and index in (0, 10):
                continue
            x, y, w, h = (entry[key] for key in ("x", "y", "w", "h"))
            draw.rectangle((x, y, x + w - 1, y + h - 1), fill=(22 + index * 17, 81, 144, 255))
            image.putpixel((x + w // 2, y + h // 2), (91, 40, 140, 128))
        path = directory / source["filename"]
        image.save(path)
        source["sha256"] = sha(path)
        paths[source["id"]] = path
    return sources, paths


class WorldFlipperInteractionAssets(unittest.TestCase):
    def test_six_source_identities_and_runtime_metadata_are_pinned(self) -> None:
        sources = read(ROOT / "tools/world_flipper_interactions_sources.json")["sources"]
        self.assertEqual(len(sources), 6)
        self.assertEqual({source["game_id"] for source in sources}, set(IDS))
        self.assertEqual(len({source["id"] for source in sources}), 6)
        manifest = read(ART / "manifest.json")
        records = {record["id"]: record for record in manifest["assets"]}
        metadata = read(ART / "interactions/interaction-art.json")
        self.assertEqual(metadata["revision"], "world-flipper-fan-06")
        self.assertEqual(set(metadata["assets"]), set(IDS))
        for source in sources:
            with self.subTest(source=source["id"]):
                self.assertTrue(source["url"].startswith("https://worldflipper.jp/demo/src/"))
                self.assertEqual(source["source_page"], "https://worldflipper.jp/demo/")
                self.assertRegex(source["atlas"]["sha256"], r"^[0-9a-f]{64}$")
                record = records[source["id"]]
                self.assertEqual(record["source_ids"], [source["id"]])
                self.assertEqual(record["atlas_frames"], source["frames"])
                self.assertEqual(sha(ROOT / record["path"]), record["sha256"])
                runtime = metadata["assets"][source["game_id"]]
                self.assertEqual(runtime["path"], "res://" + record["path"])
                self.assertEqual(runtime["frame_size"], source["cell_size"])
                self.assertEqual(runtime["frame_count"], len(source["frames"]))
        meta_record = next(record for record in manifest["metadata_files"] if record["path"].endswith("interaction-art.json"))
        self.assertEqual(sha(ROOT / meta_record["path"]), meta_record["sha256"])

    def test_orb_and_barrel_have_complete_frames_and_explicit_adapted_timing(self) -> None:
        assets = read(ART / "interactions/interaction-art.json")["assets"]
        ball = rgba(ART / "interactions/ball-atlas.png")
        self.assertEqual(ball.size, (448, 64))
        self.assertEqual(assets["ball"]["frame_ends_seconds"], [.12, .18, .24, .30, .36, .42, .48])
        self.assertIn("adaptation", assets["ball"]["timing_note"].lower())
        for index in range(7):
            value = ball.crop((index * 64, 0, index * 64 + 64, 64))
            bounds = value.getchannel("A").getbbox()
            self.assertTrue(0 < bounds[0] < bounds[2] < 64 and 0 < bounds[1] < bounds[3] < 64)
            self.assertEqual(value.tobytes(), value.resize((32,32), Image.Resampling.NEAREST).resize((64,64), Image.Resampling.NEAREST).tobytes())
        barrel = rgba(ART / "interactions/barrel-atlas.png")
        self.assertEqual(barrel.size, (512, 384))
        self.assertEqual(assets["barrel"]["foot_anchor"], [64,112])
        self.assertEqual(assets["barrel"]["idle_frame"], 1)
        self.assertEqual((assets["barrel"]["break_first_frame"], assets["barrel"]["break_last_frame"], assets["barrel"]["break_frame_duration"]), (2,9,.04))
        self.assertIn("adaptation", assets["barrel"]["timing_note"].lower())
        for index in range(12):
            x, y = index % 4 * 128, index // 4 * 128
            frame = barrel.crop((x,y,x+128,y+128))
            self.assertEqual(frame.getchannel("A").getbbox() is None, index in (0,10,11))
        self.assertEqual(barrel.crop((128,0,256,128)).getchannel("A").getbbox()[3],112)

    def test_complete_chest_and_pickups_keep_integer_pixels_at_the_contract_feet(self) -> None:
        for game_id, cell, scale, foot in (("chest",96,3,(48,88)),("health",64,2,(32,61)),("charge",64,2,(32,61)),("mana",64,2,(32,61))):
            with self.subTest(asset=game_id):
                image=rgba(ART / "interactions" / (game_id+".png"))
                self.assertEqual(image.size,(cell,cell))
                bounds=image.getchannel("A").getbbox()
                self.assertEqual(bounds[3],foot[1])
                self.assertGreater(bounds[0],0)
                self.assertLess(bounds[2],cell)
                self.assertEqual(image.getchannel("A").getextrema(),(0,255))
                source=next(source for source in read(ROOT / "tools/world_flipper_interactions_sources.json")["sources"] if source["game_id"]==game_id)
                entry=source["frames"][0]
                width,height=(entry["h"],entry["w"]) if entry.get("r") else (entry["w"],entry["h"])
                x,y=(cell-width*scale)//2,foot[1]-height*scale
                value=image.crop((x,y,x+width*scale,y+height*scale))
                self.assertEqual(value.tobytes(),value.resize((width,height),Image.Resampling.NEAREST).resize(value.size,Image.Resampling.NEAREST).tobytes())

    def test_processor_restores_rotated_frames_without_losing_original_pixels(self) -> None:
        processor=module("world_flipper_interactions")
        with tempfile.TemporaryDirectory(prefix="embers-interaction-") as directory:
            temporary=Path(directory)
            sources,paths=fixture_sources(temporary)
            output=temporary/"runtime"
            records=processor.interaction_assets(sources,paths,output)
            self.assertEqual(len(records),6)
            for source in sources:
                record=next(record for record in records if record["id"]==source["id"])
                sheet=rgba(output/Path(record["path"]).relative_to("assets/worldflipper"))
                raw=rgba(paths[source["id"]])
                cell=source["cell_size"][0]
                for index,entry in enumerate(source["frames"]):
                    x,y,w,h=(entry[key] for key in ("x","y","w","h"))
                    value=raw.crop((x,y,x+w,y+h))
                    if entry.get("r"):
                        value=value.transpose(Image.Transpose.ROTATE_90)
                    expected=Image.new("RGBA",(cell,cell))
                    if source["game_id"] in ("ball","barrel"):
                        original=Image.new("RGBA",(entry["fw"],entry["fh"]))
                        original.alpha_composite(value,(-entry.get("fx",0),-entry.get("fy",0)))
                        if source["game_id"]=="ball":
                            expected=original.crop((16,8,48,40)).resize((64,64),Image.Resampling.NEAREST)
                        else:
                            expected.alpha_composite(original.resize((106,72),Image.Resampling.NEAREST),(14,52))
                    else:
                        scaled=value.resize((value.width*source["scale"],value.height*source["scale"]),Image.Resampling.NEAREST)
                        expected.alpha_composite(scaled,((cell-scaled.width)//2,source["foot_anchor"][1]-scaled.height))
                    x,y=index%source["columns"]*cell,index//source["columns"]*cell
                    self.assertEqual(sheet.crop((x,y,x+cell,y+cell)).tobytes(),expected.tobytes())
            saved={path.relative_to(output):path.read_bytes() for path in output.rglob("*") if path.is_file()}
            processor.interaction_assets(list(reversed(sources))+[{"id":"unrelated","kind":"weapon"}],paths,output)
            self.assertEqual({path: (output/path).read_bytes() for path in saved},saved)

    def test_bad_late_source_leaves_all_six_runtime_assets_and_metadata_unchanged(self) -> None:
        processor=module("world_flipper_interactions")
        with tempfile.TemporaryDirectory(prefix="embers-interaction-bad-") as directory:
            temporary=Path(directory)
            sources,paths=fixture_sources(temporary)
            output=temporary/"runtime"
            processor.interaction_assets(sources,paths,output)
            saved={path:path.read_bytes() for path in output.rglob("*") if path.is_file()}
            for mutation in ("sha","crop","rotation","scale","layout","foot","ball_timing","barrel_timing","missing","duplicate"):
                invalid=deepcopy(sources)
                if mutation=="sha":invalid[-1]["sha256"]="0"*64
                elif mutation=="crop":invalid[-1]["frames"][0]["x"]=100000
                elif mutation=="rotation":invalid[-1]["frames"][0]["r"]=1
                elif mutation=="scale":invalid[-1]["scale"]=1.5
                elif mutation=="layout":invalid[-1]["cell_size"]=[32,32]
                elif mutation=="foot":invalid[-1]["foot_anchor"]=[32,64]
                elif mutation=="ball_timing":invalid[0]["frame_ends_seconds"]=[.1]*7
                elif mutation=="barrel_timing":invalid[1]["break_frame_duration"]=-.04
                elif mutation=="missing":invalid.pop()
                else:invalid[-1]=deepcopy(invalid[0])
                with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                    processor.interaction_assets(invalid,paths,output)
                self.assertEqual({path:path.read_bytes() for path in saved},saved)

    def test_large_native_floors_and_all_upright_landmarks_stay_outside_walkability(self) -> None:
        maps=module("world_flipper_maps")
        self.assertEqual(maps.SIZE,(3780,2192))
        self.assertEqual(maps.WORLD_ORIGIN,(-1146,-767))
        self.assertEqual(maps.WALKABLE,(64,232,3508,2032))
        self.assertEqual(maps.PREVIEW_CROP,(1146,772,1280,720))
        manifest=read(ART/"manifest.json")
        for source in read(ROOT/"tools/world_flipper_maps_sources.json")["sources"]:
            if source["kind"]=="arena_map":
                self.assertGreater(source["crop"][2]*source["crop"][3],64*64)
                continue
            if source["kind"]!="arena_landmark":continue
            base=Image.new("RGB",maps.HALF_SIZE,(21,43,65))
            raw=Image.new("RGBA",tuple(source["source_size"]),(140,85,32,255))
            before=base.crop(maps.HALF_WALKABLE).tobytes()
            placements=maps._landmarks(base,raw,source)
            self.assertEqual(base.crop(maps.HALF_WALKABLE).tobytes(),before)
            self.assertGreater(len(placements),0)
            record=next(record for record in manifest["assets"] if record["id"]=="arena_"+source["game_id"])
            self.assertEqual(record["world_origin"],[-1146,-767])
            self.assertEqual(record["walkable_art_rect"],[64,232,3508,2032])
            for placement in record["landmarks"]:
                x,y,w,h=placement["art_rect"]
                self.assertTrue(x+w<=64 or x>=3508 or y+h<=232 or y>=2032)
                self.assertEqual(placement["scale"],2)
            invalid=deepcopy(source)
            invalid["placements"][0]["position"]=[400,400]
            with self.assertRaises(ValueError):maps._landmarks(base.copy(),raw,invalid)

    def test_both_exports_include_raw_interactions_and_the_timing_metadata(self) -> None:
        filters=re.findall(r'^include_filter="([^"]+)"',(ROOT/"export_presets.cfg").read_text(encoding="utf-8"),re.M)
        self.assertEqual(len(filters),2)
        paths=["assets/worldflipper/interactions/"+name for name in ("ball-atlas.png","barrel-atlas.png","chest.png","health.png","charge.png","mana.png","interaction-art.json")]
        for include in filters:
            for path in paths:self.assertTrue(any(fnmatch.fnmatchcase(path,pattern) for pattern in include.split(",")),path)


if __name__=="__main__":
    unittest.main()
