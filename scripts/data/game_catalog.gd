class_name GameCatalog
extends RefCounted

const WEAPON_DEFS: Array[ContentDef] = [
	preload("res://data/weapons/bone.tres"),
	preload("res://data/weapons/frost.tres"),
	preload("res://data/weapons/ember.tres"),
	preload("res://data/weapons/scatter.tres"),
]
const RUNE_DEFS: Array[ContentDef] = [
	preload("res://data/runes/pierce.tres"),
	preload("res://data/runes/bounce.tres"),
	preload("res://data/runes/blast.tres"),
]
const RELIC_DEFS: Array[ContentDef] = [
	preload("res://data/relics/damage.tres"),
	preload("res://data/relics/haste.tres"),
	preload("res://data/relics/speed.tres"),
	preload("res://data/relics/vitality.tres"),
	preload("res://data/relics/armor.tres"),
	preload("res://data/relics/magnet.tres"),
]
const ENEMY_DEFS: Array[ContentDef] = [
	preload("res://data/enemies/chaser.tres"),
	preload("res://data/enemies/rusher.tres"),
	preload("res://data/enemies/tank.tres"),
	preload("res://data/enemies/caster.tres"),
	preload("res://data/enemies/boss.tres"),
]
const WAVE_DEFS: Array[ContentDef] = [
	preload("res://data/waves/wave_1.tres"),
	preload("res://data/waves/wave_2.tres"),
	preload("res://data/waves/wave_3.tres"),
	preload("res://data/waves/wave_4.tres"),
	preload("res://data/waves/wave_5.tres"),
	preload("res://data/waves/wave_6.tres"),
	preload("res://data/waves/wave_7.tres"),
	preload("res://data/waves/wave_8.tres"),
]

static func weapon(id: String) -> ContentDef:
	return _find(WEAPON_DEFS, id)

static func rune(id: String) -> ContentDef:
	return _find(RUNE_DEFS, id)

static func relic(id: String) -> ContentDef:
	return _find(RELIC_DEFS, id)

static func enemy(id: String) -> ContentDef:
	return _find(ENEMY_DEFS, id)

static func wave(number: int) -> ContentDef:
	if number < 1 or number > WAVE_DEFS.size():
		return null
	return WAVE_DEFS[number - 1]

static func weapons() -> Array[ContentDef]:
	return WEAPON_DEFS.duplicate()

static func runes() -> Array[ContentDef]:
	return RUNE_DEFS.duplicate()

static func relics() -> Array[ContentDef]:
	return RELIC_DEFS.duplicate()

static func enemies() -> Array[ContentDef]:
	return ENEMY_DEFS.duplicate()

static func waves() -> Array[ContentDef]:
	return WAVE_DEFS.duplicate()

static func _find(definitions: Array[ContentDef], id: String) -> ContentDef:
	for definition: ContentDef in definitions:
		if definition.id == id:
			return definition
	return null
