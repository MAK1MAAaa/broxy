class_name BackpackInventory
extends RefCounted
## Transactional grid storage. Callers receive copies; failed operations never commit partial state.

const WIDTH: int = 6
const INITIAL_HEIGHT: int = 4
const MAX_HEIGHT: int = 6
const MAX_RANK: int = 3

var height: int = INITIAL_HEIGHT
var last_error: String = ""
var _items: Array[Dictionary] = []
var _next_uid: int = 1

static func rank_multiplier(rank: int) -> float:
	return float(1 << (clampi(rank, 1, MAX_RANK) - 1))

static func definition(kind: String, id: String) -> ContentDef:
	match kind:
		"weapon": return GameCatalog.weapon(id)
		"rune": return GameCatalog.rune(id)
		"relic": return GameCatalog.relic(id)
		"skill": return GameCatalog.skill(id)
	return null

static func size_for(kind: String, id: String, rotated: bool = false) -> Vector2i:
	var content: ContentDef = definition(kind, id)
	if content == null:
		return Vector2i.ZERO
	var size: Vector2i = content.inventory_size
	return Vector2i(size.y, size.x) if rotated else size

func reset() -> void:
	height = INITIAL_HEIGHT
	_items.clear()
	_next_uid = 1
	last_error = ""

func snapshot() -> Dictionary:
	var used: int = 0
	for entry: Dictionary in _items:
		var size: Vector2i = size_for(str(entry["kind"]), str(entry["id"]), bool(entry["rotated"]))
		used += size.x * size.y
	var entries: Array[Dictionary] = _items.duplicate(true)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	return {"width": WIDTH, "height": height, "max_height": MAX_HEIGHT,
		"items": entries, "used_cells": used, "total_cells": WIDTH * height,
		"next_uid": _next_uid, "expansion_cost": expansion_cost()}

func item(uid: int) -> Dictionary:
	var index: int = _index(_items, uid)
	return _items[index].duplicate(true) if index >= 0 else {}

func expansion_cost() -> int:
	return 32 if height == INITIAL_HEIGHT else 48 if height < MAX_HEIGHT else 0

func expand() -> bool:
	if height >= MAX_HEIGHT:
		return _fail("背包已扩容至上限。")
	height += 1
	last_error = ""
	return true

func find_space(kind: String, id: String) -> Dictionary:
	return _find_space(_items, kind, id)

func can_add(kind: String, id: String) -> bool:
	return not find_space(kind, id).is_empty()

func addition_error(kind: String, id: String) -> String:
	if definition(kind, id) == null:
		return "无效的背包物品。"
	if kind == "skill" and _skill_count(_items) >= ActiveSkillRules.LIMIT:
		return "主动技能已达上限（2）。"
	return "背包空间不足。" if find_space(kind, id).is_empty() else ""

func add(kind: String, id: String, paid: int = 0, rank: int = 1) -> Dictionary:
	if definition(kind, id) == null or paid < 0 or rank < 1 or rank > MAX_RANK:
		_fail("无效的背包物品。")
		return {}
	var error: String = addition_error(kind, id)
	if not error.is_empty():
		_fail(error)
		return {}
	var placement: Dictionary = find_space(kind, id)
	if placement.is_empty():
		_fail("背包空间不足。")
		return {}
	var entry: Dictionary = {"uid": _next_uid, "kind": kind, "id": id, "rank": rank,
		"x": placement["cell"].x, "y": placement["cell"].y,
		"rotated": placement["rotated"], "paid": paid, "rune": {}}
	_next_uid += 1
	_items.append(entry)
	last_error = ""
	return entry.duplicate(true)

func move(uid: int, cell: Vector2i, rotated: bool) -> bool:
	var index: int = _index(_items, uid)
	if index < 0:
		return _fail("无效的背包物品。")
	var entry: Dictionary = _items[index]
	if not _fits(_items, str(entry["kind"]), str(entry["id"]), cell, rotated, uid):
		return _fail("摆放超出背包或与其他物品重叠。")
	entry["x"] = cell.x
	entry["y"] = cell.y
	entry["rotated"] = rotated
	last_error = ""
	return true

func merge_error(source_uid: int, target_uid: int) -> String:
	if source_uid == target_uid:
		return "请选择两件不同物品。"
	var source: Dictionary = item(source_uid)
	var target: Dictionary = item(target_uid)
	if source.is_empty() or target.is_empty():
		return "无效的背包物品。"
	if source["kind"] != target["kind"] or source["id"] != target["id"] or source["rank"] != target["rank"]:
		return "只有同名、同类、同阶物品才能合成。"
	if int(target["rank"]) >= MAX_RANK:
		return "物品已达到三阶。"
	var work: Array[Dictionary] = _merged_items(source_uid, target_uid)
	return "背包空间不足，无法收回附着符文。" if work.is_empty() else ""

func merge(source_uid: int, target_uid: int) -> bool:
	var error: String = merge_error(source_uid, target_uid)
	if not error.is_empty():
		return _fail(error)
	_items = _merged_items(source_uid, target_uid)
	last_error = ""
	return true

func merged_snapshot(source_uid: int, target_uid: int) -> Array[Dictionary]:
	if not merge_error(source_uid, target_uid).is_empty():
		return []
	return _merged_items(source_uid, target_uid)

func remove(uid: int) -> Dictionary:
	var index: int = _index(_items, uid)
	if index < 0:
		_fail("无效的背包物品。")
		return {}
	var entry: Dictionary = _items[index]
	if entry["kind"] == "weapon":
		var weapon_count: int = 0
		for candidate: Dictionary in _items:
			weapon_count += 1 if candidate["kind"] == "weapon" else 0
		if weapon_count <= 1:
			_fail("必须保留至少一件法器。")
			return {}
	var work: Array[Dictionary] = _items.duplicate(true)
	work.remove_at(index)
	var rune: Dictionary = entry.get("rune", {})
	if not rune.is_empty() and not _restore_rune(work, rune):
		_fail("背包空间不足，无法收回附着符文。")
		return {}
	_items = work
	last_error = ""
	return entry.duplicate(true)

func equip(rune_uid: int, weapon_uid: int) -> bool:
	var rune_index: int = _index(_items, rune_uid)
	var weapon_index: int = _index(_items, weapon_uid)
	if rune_index < 0 or weapon_index < 0 or _items[rune_index]["kind"] != "rune" or _items[weapon_index]["kind"] != "weapon":
		return _fail("无效的符文或法器。")
	var work: Array[Dictionary] = _items.duplicate(true)
	var incoming: Dictionary = _rune_record(work[rune_index])
	var previous: Dictionary = (work[weapon_index].get("rune", {}) as Dictionary).duplicate(true)
	var old_cell := Vector2i(int(work[rune_index]["x"]), int(work[rune_index]["y"]))
	work[weapon_index]["rune"] = incoming
	work.remove_at(rune_index)
	if not previous.is_empty() and not _restore_rune(work, previous, old_cell):
		return _fail("背包空间不足，无法收回附着符文。")
	_items = work
	last_error = ""
	return true

func unequip(weapon_uid: int) -> bool:
	var index: int = _index(_items, weapon_uid)
	if index < 0 or _items[index]["kind"] != "weapon":
		return _fail("无效的法器。")
	var rune: Dictionary = _items[index].get("rune", {})
	if rune.is_empty():
		return _fail("这件法器没有装备符文。")
	var work: Array[Dictionary] = _items.duplicate(true)
	work[index]["rune"] = {}
	if not _restore_rune(work, rune):
		return _fail("背包空间不足。")
	_items = work
	last_error = ""
	return true

func _merged_items(source_uid: int, target_uid: int) -> Array[Dictionary]:
	var work: Array[Dictionary] = _items.duplicate(true)
	var source_index: int = _index(work, source_uid)
	var target_index: int = _index(work, target_uid)
	if source_index < 0 or target_index < 0:
		return []
	var source: Dictionary = work[source_index]
	var target: Dictionary = work[target_index]
	target["rank"] = int(target["rank"]) + 1
	target["paid"] = int(source["paid"]) + int(target["paid"])
	var source_rune: Dictionary = source.get("rune", {})
	var target_rune: Dictionary = target.get("rune", {})
	if target_rune.is_empty() and not source_rune.is_empty():
		target["rune"] = source_rune.duplicate(true)
	work.remove_at(source_index)
	if not source_rune.is_empty() and not target_rune.is_empty() and not _restore_rune(work, source_rune):
		return []
	return work

func _restore_rune(work: Array[Dictionary], rune: Dictionary, preferred: Vector2i = Vector2i(-1, -1)) -> bool:
	var placement: Dictionary = {}
	if preferred.x >= 0 and _fits(work, "rune", str(rune["id"]), preferred, false):
		placement = {"cell": preferred, "rotated": false}
	else:
		placement = _find_space(work, "rune", str(rune["id"]))
	if placement.is_empty():
		return false
	var entry: Dictionary = _rune_record(rune)
	entry["kind"] = "rune"
	entry["x"] = placement["cell"].x
	entry["y"] = placement["cell"].y
	entry["rotated"] = placement["rotated"]
	entry["rune"] = {}
	work.append(entry)
	return true

func _find_space(entries: Array[Dictionary], kind: String, id: String) -> Dictionary:
	if kind == "skill" and _skill_count(entries) >= ActiveSkillRules.LIMIT:
		return {}
	var original: Vector2i = size_for(kind, id)
	if original.x <= 0 or original.y <= 0:
		return {}
	for rotated: bool in [false, true]:
		if rotated and original.x == original.y:
			continue
		for y: int in height:
			for x: int in WIDTH:
				var cell := Vector2i(x, y)
				if _fits(entries, kind, id, cell, rotated):
					return {"cell": cell, "x": cell.x, "y": cell.y, "rotated": rotated}
	return {}

static func _skill_count(entries: Array[Dictionary]) -> int:
	var count: int = 0
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) == "skill":
			count += 1
	return count

func _fits(entries: Array[Dictionary], kind: String, id: String, cell: Vector2i, rotated: bool, ignore_uid: int = -1) -> bool:
	var size: Vector2i = size_for(kind, id, rotated)
	if size.x <= 0 or size.y <= 0 or cell.x < 0 or cell.y < 0 or cell.x + size.x > WIDTH or cell.y + size.y > height:
		return false
	var rectangle := Rect2i(cell, size)
	for entry: Dictionary in entries:
		if int(entry["uid"]) == ignore_uid:
			continue
		var other := Rect2i(Vector2i(int(entry["x"]), int(entry["y"])), size_for(str(entry["kind"]), str(entry["id"]), bool(entry["rotated"])))
		if rectangle.intersects(other):
			return false
	return true

static func _rune_record(entry: Dictionary) -> Dictionary:
	return {"uid": int(entry["uid"]), "id": str(entry["id"]), "rank": int(entry.get("rank", 1)), "paid": int(entry.get("paid", 0))}

static func _index(entries: Array[Dictionary], uid: int) -> int:
	for index: int in entries.size():
		if int(entries[index]["uid"]) == uid:
			return index
	return -1

func _fail(message: String) -> bool:
	last_error = message
	return false
