class_name AdventureArt
extends RefCounted
## Presentation-only resource routing. Catalog IDs and simulation data stay stable.

const REVISION: String = "world-flipper-fan-08"
const ROOT: String = "res://assets/starfall/"
const FAN_ROOT: String = "res://assets/worldflipper/"
const FAN_OVERRIDES: Dictionary = {
	"res://assets/fx/projectile_heads.svg": "fx/projectile_heads.png",
	"res://assets/icons/damage.svg": "icons/damage.png",
	"res://assets/icons/haste.svg": "icons/haste.png",
	"res://assets/icons/speed.svg": "icons/speed.png",
	"res://assets/icons/vitality.svg": "icons/vitality.png",
	"res://assets/icons/armor.svg": "icons/armor.png",
	"res://assets/icons/magnet.svg": "icons/magnet.png",
	"res://assets/icons/moon_charm.svg": "icons/moon_charm.png",
	"res://assets/icons/pilgrim.svg": "icons/pilgrim.png",
	"res://assets/icons/bulwark.svg": "icons/bulwark.png",
	"res://assets/icons/hourglass.svg": "icons/hourglass.png",
	"res://assets/icons/blood_pact.svg": "icons/blood_pact.png",
	"res://assets/icons/grave_candle.svg": "icons/grave_candle.png",
	"res://assets/icons/fold_clasp.svg": "icons/fold_clasp.png",
	"res://assets/icons/echo_stone.svg": "icons/echo_stone.png",
	"res://assets/icons/pierce.svg": "icons/pierce.png",
	"res://assets/icons/bounce.svg": "icons/bounce.png",
	"res://assets/icons/blast.svg": "icons/blast.png",
	"res://assets/icons/skill_pulse.svg": "characters/clarisse/idle.png",
	"res://assets/icons/skill_starfall.svg": "characters/hanabi/idle.png",
	"res://assets/icons/skill_arc_slash.svg": "characters/celtie/idle.png",
	"res://assets/arena.svg": "maps/previews/reliquary.png",
	"res://assets/maps/reliquary.svg": "maps/previews/reliquary.png",
	"res://assets/maps/mire.svg": "maps/previews/mire.png",
	"res://assets/maps/glacier.svg": "maps/previews/glacier.png",
	"res://assets/maps/ashland.svg": "maps/previews/ashland.png",
	"res://assets/sprites/player.svg": "sprites/player.png",
	"res://assets/sprites/chaser.svg": "sprites/chaser.png",
	"res://assets/sprites/rusher.svg": "sprites/rusher.png",
	"res://assets/sprites/tank.svg": "sprites/tank.png",
	"res://assets/sprites/caster.svg": "sprites/caster.png",
	"res://assets/sprites/boss.svg": "sprites/boss.png",
	"res://assets/icons/bone.svg": "icons/bone.png",
	"res://assets/icons/frost.svg": "icons/frost.png",
	"res://assets/icons/ember.svg": "icons/ember.png",
	"res://assets/icons/scatter.svg": "icons/scatter.png",
	"res://assets/icons/crescent.svg": "icons/crescent.png",
	"res://assets/icons/storm.svg": "icons/storm.png",
	"res://assets/icons/comet.svg": "icons/comet.png",
	"res://assets/icons/return_ring.svg": "icons/return_ring.png",
	"res://assets/icons/sword_0012.svg": "icons/sword_0012.png",
	"res://assets/icons/spear_0005.svg": "icons/spear_0005.png",
	"res://assets/icons/sword_0004.svg": "icons/sword_0004.png",
	"res://assets/icons/axe_0009.svg": "icons/axe_0009.png",
	"res://assets/icons/book_0009.svg": "icons/book_0009.png",
	"res://assets/icons/sword_0007.svg": "icons/sword_0007.png",
	"res://assets/icons/axe_0024.svg": "icons/axe_0024.png",
	"res://assets/icons/sword_0011.svg": "icons/sword_0011.png",
}

static func path(source: String) -> String:
	var original_source: String = source
	if source.begins_with(ROOT + "icons/skill_"):
		original_source = "res://assets/" + source.trim_prefix(ROOT)
	if FAN_OVERRIDES.has(original_source):
		return FAN_ROOT + str(FAN_OVERRIDES[original_source])
	if source.begins_with(ROOT) or source.begins_with(FAN_ROOT):
		return source
	if source == "res://assets/menu_art.svg":
		return ROOT + "menu_art.png"
	if source.begins_with("res://assets/") and source.ends_with(".svg"):
		return ROOT + source.trim_prefix("res://assets/")
	return source
