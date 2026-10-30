class_name GameCatalog
extends RefCounted

const WEAPON_DEFS: Array[ContentDef] = [
	preload("res://data/weapons/bone.tres"),
	preload("res://data/weapons/frost.tres"),
	preload("res://data/weapons/ember.tres"),
	preload("res://data/weapons/scatter.tres"),
	preload("res://data/weapons/crescent.tres"),
	preload("res://data/weapons/storm.tres"),
	preload("res://data/weapons/comet.tres"),
	preload("res://data/weapons/return_ring.tres"),
	preload("res://data/weapons/sword_0012.tres"),
	preload("res://data/weapons/spear_0005.tres"),
	preload("res://data/weapons/sword_0004.tres"),
	preload("res://data/weapons/axe_0009.tres"),
	preload("res://data/weapons/book_0009.tres"),
	preload("res://data/weapons/sword_0007.tres"),
	preload("res://data/weapons/axe_0024.tres"),
	preload("res://data/weapons/sword_0011.tres"),
]
const RUNE_DEFS: Array[ContentDef] = [
	preload("res://data/runes/pierce.tres"),
	preload("res://data/runes/bounce.tres"),
	preload("res://data/runes/blast.tres"),
]
const SKILL_DEFS: Array[ContentDef] = [
	preload("res://data/skills/pulse.tres"),
	preload("res://data/skills/starfall.tres"),
	preload("res://data/skills/arc_slash.tres"),
]
const RELIC_DEFS: Array[ContentDef] = [
	preload("res://data/relics/damage.tres"),
	preload("res://data/relics/haste.tres"),
	preload("res://data/relics/speed.tres"),
	preload("res://data/relics/vitality.tres"),
	preload("res://data/relics/armor.tres"),
	preload("res://data/relics/magnet.tres"),
	preload("res://data/relics/moon_charm.tres"),
	preload("res://data/relics/pilgrim.tres"),
	preload("res://data/relics/bulwark.tres"),
	preload("res://data/relics/hourglass.tres"),
	preload("res://data/relics/blood_pact.tres"),
	preload("res://data/relics/grave_candle.tres"),
	preload("res://data/relics/fold_clasp.tres"),
	preload("res://data/relics/echo_stone.tres"),
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

static var _weapon_index: Dictionary = {}
static var _rune_index: Dictionary = {}
static var _skill_index: Dictionary = {}
static var _relic_index: Dictionary = {}
static var _enemy_index: Dictionary = {}

static func _static_init() -> void:
	_weapon_index = _index(WEAPON_DEFS)
	_rune_index = _index(RUNE_DEFS)
	_skill_index = _index(SKILL_DEFS)
	_relic_index = _index(RELIC_DEFS)
	_enemy_index = _index(ENEMY_DEFS)

static func weapon(id: String) -> ContentDef:
	return _weapon_index.get(id)

static func rune(id: String) -> ContentDef:
	return _rune_index.get(id)

static func relic(id: String) -> ContentDef:
	return _relic_index.get(id)

static func skill(id: String) -> ContentDef:
	return _skill_index.get(id)

static func enemy(id: String) -> ContentDef:
	return _enemy_index.get(id)

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

static func skills() -> Array[ContentDef]:
	return SKILL_DEFS.duplicate()

static func enemies() -> Array[ContentDef]:
	return ENEMY_DEFS.duplicate()

static func waves() -> Array[ContentDef]:
	return WAVE_DEFS.duplicate()

static func _index(definitions: Array[ContentDef]) -> Dictionary:
	var result: Dictionary = {}
	for definition: ContentDef in definitions:
		if not result.has(definition.id):
			result[definition.id] = definition
	return result
