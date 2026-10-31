extends SceneTree
## Source launcher for the same embedded pressure fixture shipped in release builds.

const BENCHMARK = preload("res://scripts/diagnostics/dash_benchmark.gd")

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var diagnostic: Node = BENCHMARK.new()
	diagnostic.launcher_kind = "source_script"
	root.add_child(diagnostic)
