extends RefCounted
## Test-only physical inventory setup; production runs never receive implicit skills.

static func equip_pulse(state: RunState) -> bool:
	for item: Dictionary in state.backpack_snapshot()["items"]:
		if str(item.get("kind", "")) == "skill" and str(item.get("id", "")) == "pulse":
			return true
	if state.backpack.add("skill", "pulse").is_empty():
		return false
	state._sync_backpack_projection()
	state.changed.emit()
	return true
