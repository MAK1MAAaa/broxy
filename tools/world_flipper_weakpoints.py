"""Reconstruct complete original weak-point states without importing gameplay."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
REGISTRY=Path(__file__).with_name("world_flipper_weakpoints_sources.json")
REVISION="world-flipper-fan-07"
CELL=96
STATES=("white","red","broken")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _checked_image(source: dict,path: Path) -> Image.Image:
    data=path.read_bytes()
    if len(data)>8*1024*1024 or _sha(data)!=source["sha256"]:
        raise ValueError("Weak-point source failed size/checksum validation")
    with Image.open(path) as raw:
        if raw.format!="PNG" or list(raw.size)!=source["source_size"]:
            raise ValueError("Weak-point source format or canvas changed")
        return raw.convert("RGBA")


def _frame(raw: Image.Image,entry: dict) -> Image.Image:
    x,y,w,h=(entry[key] for key in ("x","y","w","h"))
    if any(type(value) is not int for value in (x,y,w,h)) or min(x,y)<0 or min(w,h)<=0 or x+w>raw.width or y+h>raw.height:
        raise ValueError("Weak-point atlas crop leaves source")
    value=raw.crop((x,y,x+w,y+h))
    if type(entry.get("r",False)) is not bool:
        raise ValueError("Weak-point atlas rotation must be boolean")
    if entry.get("r",False):value=value.transpose(Image.Transpose.ROTATE_90)
    if "fw" not in entry:return value
    width,height,px,py=entry["fw"],entry["fh"],-entry.get("fx",0),-entry.get("fy",0)
    if any(type(number) is not int for number in (width,height,px,py)) or min(px,py)<0 or width<value.width+px or height<value.height+py or max(width,height)>96:
        raise ValueError("Weak-point atlas trim cannot be restored")
    result=Image.new("RGBA",(width,height))
    result.alpha_composite(value,(px,py))
    return result


def _quadrants(quarter: Image.Image,shift: int=0) -> Image.Image:
    result=Image.new("RGBA",(CELL,CELL))
    for turn in range(4):
        layer=Image.new("RGBA",result.size)
        layer.alpha_composite(quarter,(48+shift,48-quarter.height-shift))
        result.alpha_composite(layer.rotate(turn*90,resample=Image.Resampling.NEAREST))
    return result


def _full_target(frames: dict[str,Image.Image],phase: str,source: dict) -> Image.Image:
    result=_quadrants(frames["sight_b" if phase=="white" else "sight_a"])
    inner=_quadrants(frames["sight_a"])
    size=round(CELL*source["parts"]["sight"]["inner_scale_fixed4096"]/8192)*2
    inner=inner.resize((size,size),Image.Resampling.NEAREST)
    result.alpha_composite(inner,((CELL-size)//2,(CELL-size)//2))
    transform=source["parts"]["sight"]["cross_source_transform"]
    offset=(48+transform["x"]//4096,48+transform["y"]//4096)
    cross=Image.new("RGBA",(CELL,CELL))
    cross.alpha_composite(frames["sight_c"],offset)
    for turn in range(4):result.alpha_composite(cross.rotate(turn*90,resample=Image.Resampling.NEAREST))
    return result


def _multiply(outer: dict,inner: dict) -> tuple[float,float,float,float,float,float]:
    a,b,c,d,x,y=(outer[key]/4096 for key in ("a","b","c","d","x","y"))
    e,f,g,h,u,v=(inner[key]/4096 for key in ("a","b","c","d","x","y"))
    return a*e+c*f,b*e+d*f,a*g+c*h,b*g+d*h,a*u+c*v+x,b*u+d*v+y


def _affine_piece(value: Image.Image,matrix: tuple[float,float,float,float,float,float],scale: float) -> Image.Image:
    a,b,c,d,x,y=(number*scale for number in matrix)
    determinant=a*d-b*c
    if abs(determinant)<1e-9:
        raise ValueError("Weak-point authored matrix is singular")
    center=96
    x,y=x+center,y+center
    inverse=(d/determinant,-c/determinant,(c*y-d*x)/determinant,-b/determinant,a/determinant,(b*x-a*y)/determinant)
    return value.transform((192,192),Image.Transform.AFFINE,inverse,resample=Image.Resampling.NEAREST)


def _broken(frames: dict[str,Image.Image],source: dict) -> Image.Image:
    data=source["parts"]["broken"]
    scale=data["global_scale_fixed4096"]/4096
    if not 0<scale<=1:
        raise ValueError("Broken state needs a bounded positive authored scale")
    result=Image.new("RGBA",(192,192))
    for kind,piece,transform in (("quarter_piece_matrices","broken_b","quarter_source_transform"),("bar_piece_matrices","broken_a","bar_source_transform")):
        for matrix in data[kind]:
            result.alpha_composite(_affine_piece(frames[piece],_multiply(matrix,data[transform]),scale))
    bounds=result.getchannel("A").getbbox()
    if bounds is None or bounds[0]<48 or bounds[1]<48 or bounds[2]>144 or bounds[3]>144:
        raise ValueError("Broken state would lose authored source pieces at its96px edge")
    return result.crop((48,48,144,144))


def weakpoint_assets(sources: list[dict],paths: dict[str,Path],output: Path) -> list[dict]:
    """Compose three complete states; validate all raw/source pieces before writing."""
    selected=[source for source in sources if source.get("kind")=="weakpoint_art"]
    if len(selected)!=1:
        raise ValueError("Weak points require one uniquely pinned official layer atlas")
    source=selected[0]
    if source["cell_size"]!=[CELL,CELL] or source["columns"]!=3 or source["states"]!=list(STATES) or source["center_anchor"]!=[48,48]:
        raise ValueError("Weak-point state layout changed")
    raw=_checked_image(source,paths[source["id"]])
    required={"sight_a","sight_b","sight_c","broken_a","broken_b"}
    if set(source["frames"])!=required:
        raise ValueError("Weak-point source needs both quarter colors and complete cross/break pieces")
    frames={name:_frame(raw,entry) for name,entry in source["frames"].items()}
    if any(value.getchannel("A").getbbox() is None for value in frames.values()):
        raise ValueError("Weak-point source pieces must be visible")
    values=[_full_target(frames,phase,source) for phase in STATES[:2]]+[_broken(frames,source)]
    atlas=Image.new("RGBA",(CELL*len(values),CELL))
    for index,value in enumerate(values):
        bounds=value.getchannel("A").getbbox()
        if bounds is None or min(bounds[:2])<=0 or max(bounds[2:])>=CELL:
            raise ValueError("Every weak-point state must retain transparent safe margins")
        if index<2:
            for x,y in ((16,16),(48,16),(16,48),(48,48)):
                if value.crop((x,y,x+32,y+32)).getchannel("A").getbbox() is None:
                    raise ValueError("Complete target requires all four quadrants")
        atlas.alpha_composite(value,(index*CELL,0))
    target=output/"boss/weakpoint-atlas.png"
    target.parent.mkdir(parents=True,exist_ok=True)
    atlas.save(target,optimize=False)
    record={"id":"boss_weakpoint_states","path":"assets/worldflipper/boss/weakpoint-atlas.png","sha256":_sha(target.read_bytes()),"size":[288,96],"alpha_bounds":list(atlas.getchannel("A").getbbox()),"source_ids":[source["id"]],"frame_size":[96,96],"columns":3,"frame_count":3,"states":list(STATES),"center_anchor":[48,48],"filter":"nearest","normalization":source["normalization"]}
    metadata={"schema_version":1,"revision":REVISION,"original_copyright":"© Cygames, Inc. / Citail Inc.","assets":{"weakpoint":{**{key:value for key,value in record.items() if key not in ("sha256","alpha_bounds","source_ids")},"path":"res://"+record["path"]}},"timing_note":"White/red flashing, charging progress and broken lifetime are project runtime adaptations. These are static complete states from original pieces; no original FPS or time remapping is claimed.","centering_note":"The authored inner-ring scale is quantized to an even68px centered cell; no half-pixel drift between white/red states."}
    (output/"boss/weakpoint-art.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    return [record]


def main() -> None:
    from fetch_world_flipper_art import acquire

    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline",action="store_true",help="Use checksum-verified cached original sources only")
    args=parser.parse_args()
    sources=json.loads(REGISTRY.read_text(encoding="utf-8"))["sources"]
    (ROOT/".tools/worldflipper/source").mkdir(parents=True,exist_ok=True)
    paths={source["id"]:acquire(source,args.offline) for source in sources}
    records=weakpoint_assets(sources,paths,ROOT/"assets/worldflipper")
    print(json.dumps({"assets":len(records),"offline":args.offline},ensure_ascii=False))


if __name__=="__main__":main()
