class_name AdventureArt
extends RefCounted
## Presentation-only resource routing. Catalog IDs and simulation data stay stable.

const REVISION: String = "world-flipper-fan-01"
const ROOT: String = "res://assets/starfall/"
const FAN_ROOT: String = "res://assets/worldflipper/"
const FAN_OVERRIDES: Dictionary = {
	"res://assets/sprites/player.svg": "sprites/player.png",
	"res://assets/icons/bone.svg": "icons/bone.png",
	"res://assets/icons/frost.svg": "icons/frost.png",
	"res://assets/icons/ember.svg": "icons/ember.png",
	"res://assets/icons/scatter.svg": "icons/scatter.png",
	"res://assets/icons/crescent.svg": "icons/crescent.png",
	"res://assets/icons/storm.svg": "icons/storm.png",
	"res://assets/icons/comet.svg": "icons/comet.png",
	"res://assets/icons/return_ring.svg": "icons/return_ring.png",
}

static func path(source: String) -> String:
	if source.begins_with(ROOT) or source.begins_with(FAN_ROOT):
		return source
	if FAN_OVERRIDES.has(source):
		return FAN_ROOT + str(FAN_OVERRIDES[source])
	if source == "res://assets/menu_art.svg":
		return ROOT + "menu_art.png"
	if source.begins_with("res://assets/") and source.ends_with(".svg"):
		return ROOT + source.trim_prefix("res://assets/")
	return source
