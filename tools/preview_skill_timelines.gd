extends SceneTree
## Source-tree entry point for the same embedded diagnostic used by release builds.

const PREVIEW: Script = preload("res://scripts/diagnostics/wf_actions_preview.gd")

func _initialize() -> void:
	_start_preview.call_deferred()

func _start_preview() -> void:
	var preview: Node = PREVIEW.new()
	root.add_child(preview)
