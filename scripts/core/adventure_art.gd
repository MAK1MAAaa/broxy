class_name AdventureArt
extends RefCounted
## Presentation-only resource routing. Catalog IDs and simulation data stay stable.

const REVISION: String = "starfall-01"
const ROOT: String = "res://assets/starfall/"

static func path(source: String) -> String:
	if source.begins_with(ROOT):
		return source
	if source == "res://assets/menu_art.svg":
		return ROOT + "menu_art.png"
	if source.begins_with("res://assets/") and source.ends_with(".svg"):
		return ROOT + source.trim_prefix("res://assets/")
	return source
