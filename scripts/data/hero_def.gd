class_name HeroDef
extends Resource
## Identity, source art and independent main-character rules.

@export var id: String = ""
@export var display_name: String = ""
@export var starter_weapon: String = "bone"
@export var idle_path: String = ""
@export var atlas_path: String = ""
@export var portrait_path: String = ""
@export var frame_size: int = 96
@export var foot_anchor: Vector2 = Vector2(48.0, 93.0)
@export var base_bonuses: Dictionary = {}
@export var main_skill: Dictionary = {}
@export var action_evidence: Dictionary = {}
@export var source_id: String = ""
@export var source_skill_name: String = ""
@export var source_skill_weight: int = 0
@export var source_url: String = ""
@export_multiline var adaptation_notes: String = ""
