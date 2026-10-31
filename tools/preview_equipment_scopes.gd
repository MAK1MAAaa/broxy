extends SceneTree
## The source launcher instantiates the same diagnostic Node embedded in release.

const PREVIEW: Script = preload("res://scripts/diagnostics/wf_equipment_preview.gd")

func _initialize() -> void:
	_start_preview.call_deferred()

func _start_preview() -> void:
	root.add_child(PREVIEW.new())
