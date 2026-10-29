class_name RogueRules
extends RefCounted
## First-pass values shared by decision text and the shipped fixed-step simulation.

const FROSTFIRE_RADIUS: float = 48.0
const FROSTFIRE_FACTOR: float = 0.5
const CHORUS_INTERVAL: int = 3
const CHORUS_FACTOR: float = 0.55
const CHORUS_ANGLE: float = 0.22
const HUNTER_HEALTH_FACTOR: float = 1.8
const HUNTER_SPEED_FACTOR: float = 1.15
const SWARM_REWARD: int = 4
const BULWARK_REWARD: int = 6

static func cores() -> Array[Dictionary]:
	return [core("frostfire"), core("bone_chorus")]

static func core(id: String) -> Dictionary:
	match id:
		"frostfire":
			return {"id": id, "name": "霜火共鸣", "weapons": ["frost", "ember"], "always_grant": false,
				"description": "%s优先追踪减速目标；直接命中时消耗减速，产生%d像素范围、%d%%本次伤害的次级爆发，不触发符文。免费补齐%s与%s，各一件；每局只选一个核心。" % [GameCatalog.weapon("ember").display_name, int(FROSTFIRE_RADIUS), int(FROSTFIRE_FACTOR * 100.0), GameCatalog.weapon("frost").display_name, GameCatalog.weapon("ember").display_name]}
		"bone_chorus":
			return {"id": id, "name": "白骨齐鸣", "weapons": ["bone"], "always_grant": true,
				"description": "每件%s每第%d次攻击额外向两侧各发射一枚%d%%伤害飞刃，沿用所装符文。赠送一件%s，即使已持有；每局只选一个核心。" % [GameCatalog.weapon("bone").display_name, CHORUS_INTERVAL, int(CHORUS_FACTOR * 100.0), GameCatalog.weapon("bone").display_name]}
	return {}

static func routes() -> Array[Dictionary]:
	return [route("balanced"), route("swarm"), route("bulwark")]

static func route(id: String) -> Dictionary:
	match id:
		"balanced":
			return {"id": id, "name": "原途", "description": "沿用下一波的敌人组合与节奏。", "reward": 0,
				"weights": {}, "count_factor": 1.0, "interval_factor": 1.0}
		"swarm":
			return {"id": id, "name": "密集魂潮", "description": "追踪与冲锋敌人为主，每批数量增加；完成后额外%d魂屑，不增加经验。" % SWARM_REWARD, "reward": SWARM_REWARD,
				"weights": {"chaser": 0.8, "rusher": 0.2}, "count_factor": 1.2, "interval_factor": 1.0}
		"bulwark":
			return {"id": id, "name": "重甲巡礼", "description": "少量重甲与远程敌人，刷新间隔更长；完成后额外%d魂屑，不增加经验。" % BULWARK_REWARD, "reward": BULWARK_REWARD,
				"weights": {"tank": 0.75, "caster": 0.25}, "count_factor": 0.5, "interval_factor": 1.15}
	return {}
