extends SceneTree
## Independent SVG raster comparison; never instantiates Main or profile storage.

const CURRENT_PATH: String = "res://assets/sprites/player.svg"
const DEFAULT_REPORT: String = "res://reports/player-material-raster.json"
const EXPECTED_SIZE: Vector2i = Vector2i(96, 96)
const LIMITS: Array[String] = [
	"Independent 96x96 SVG raster check using Godot Image.load_svg_from_string; not the imported runtime texture.",
	"Does not verify the 68px animated player, gameplay readability, frame rate or human recognition.",
	"Only the y<40 head region is required to keep identical RGBA; mask and chain source elements require separate QA.",
]


func _initialize() -> void:
	var baseline_path: String = ""
	var report_path: String = DEFAULT_REPORT
	var baseline_seen: bool = false
	var report_seen: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline=") and not baseline_seen:
			baseline_seen = true
			baseline_path = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--report=") and not report_seen:
			report_seen = true
			report_path = argument.trim_prefix("--report=")
		else:
			_usage_error("Unknown or repeated argument: " + argument)
			return
	if baseline_path.is_empty() or not baseline_path.is_absolute_path() or baseline_path.begins_with("res://") or baseline_path.begins_with("user://"):
		_usage_error("Required --baseline=<absolute SVG file path> is missing or is not an absolute filesystem path.")
		return
	if report_path.is_empty():
		_usage_error("--report requires a nonempty output file path.")
		return
	var before: Dictionary = _load_svg(baseline_path)
	var after: Dictionary = _load_svg(CURRENT_PATH)
	var report: Dictionary = {
		"schema_version": 1,
		"check": "independent-player-svg-raster",
		"engine_version": Engine.get_version_info()["string"],
		"baseline": _input_report(baseline_path, before),
		"current": _input_report(CURRENT_PATH, after),
		"expected_size": [EXPECTED_SIZE.x, EXPECTED_SIZE.y],
		"alpha_diff_pixels": null,
		"color_diff_pixels": null,
		"visible_color_diff_pixels": null,
		"rgba_diff_pixels": null,
		"rgba_diff_bbox": null,
		"head_y_lt_40_rgba_diff_pixels": null,
		"visible_alpha_nonzero_bbox": {"baseline": null, "current": null},
		"passed": false,
		"failures": [],
		"limits": LIMITS,
	}
	var failures: Array = report["failures"]
	for entry: Dictionary in [{"label": "baseline", "loaded": before}, {"label": "current", "loaded": after}]:
		var loaded: Dictionary = entry["loaded"]
		if not str(loaded["error"]).is_empty():
			failures.append(str(entry["label"]) + ": " + str(loaded["error"]))
		elif (loaded["image"] as Image).get_size() != EXPECTED_SIZE:
			failures.append(str(entry["label"]) + ": SVG must rasterize at exactly 96x96 pixels.")
	if failures.is_empty():
		_compare(before["image"], after["image"], report)
		if int(report["alpha_diff_pixels"]) != 0:
			failures.append("Alpha changed; the raster silhouette is not identical.")
		if int(report["visible_color_diff_pixels"]) <= 0:
			failures.append("No visible color changes were found.")
		if int(report["head_y_lt_40_rgba_diff_pixels"]) != 0:
			failures.append("RGBA pixels in the protected head region y<40 changed.")
	report["passed"] = failures.is_empty()
	var destination: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if destination == null:
		push_error("Cannot write raster report to %s: %s" % [report_path, error_string(FileAccess.get_open_error())])
		quit(2)
		return
	destination.store_string(JSON.stringify(report, "  ") + "\n")
	var write_error: Error = destination.get_error()
	destination.close()
	if write_error != OK:
		push_error("Writing raster report failed: " + error_string(write_error))
		quit(2)
		return
	print("PLAYER_MATERIAL_RASTER ", JSON.stringify(report))
	print("Independent SVG raster technical check only; not 68px dynamic gameplay or human-recognition evidence. Report: ", report_path)
	quit(0 if bool(report["passed"]) else 1)


func _load_svg(path: String) -> Dictionary:
	var loaded: Dictionary = {"image": null, "error": "", "sha256": "", "raster_error_code": null}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		loaded["error"] = "Cannot read SVG: " + error_string(FileAccess.get_open_error())
		return loaded
	var source: String = file.get_as_text()
	file.close()
	loaded["sha256"] = FileAccess.get_sha256(path)
	var raster := Image.new()
	var parse_error: Error = raster.load_svg_from_string(source, 1.0)
	loaded["raster_error_code"] = parse_error
	if parse_error != OK or raster.is_empty():
		loaded["error"] = "SVG rasterization failed: " + error_string(parse_error)
		return loaded
	raster.convert(Image.FORMAT_RGBA8)
	loaded["image"] = raster
	return loaded


func _input_report(path: String, loaded: Dictionary) -> Dictionary:
	var raster: Image = loaded["image"]
	return {"path": path, "sha256": loaded["sha256"], "raster_error_code": loaded["raster_error_code"],
		"parsed": raster != null, "size": [raster.get_width(), raster.get_height()] if raster != null else null,
		"error": loaded["error"]}


func _compare(before: Image, after: Image, report: Dictionary) -> void:
	var first: PackedByteArray = before.get_data()
	var second: PackedByteArray = after.get_data()
	var alpha_diff: int = 0
	var color_diff: int = 0
	var visible_color_diff: int = 0
	var rgba_diff: int = 0
	var head_diff: int = 0
	var changed_bounds := Rect2i()
	var baseline_visible := Rect2i()
	var current_visible := Rect2i()
	for y: int in EXPECTED_SIZE.y:
		for x: int in EXPECTED_SIZE.x:
			var offset: int = (y * EXPECTED_SIZE.x + x) * 4
			var alpha_changed: bool = first[offset + 3] != second[offset + 3]
			var color_changed: bool = first[offset] != second[offset] or first[offset + 1] != second[offset + 1] or first[offset + 2] != second[offset + 2]
			if alpha_changed:
				alpha_diff += 1
			if color_changed:
				color_diff += 1
				if first[offset + 3] > 0 or second[offset + 3] > 0:
					visible_color_diff += 1
			if alpha_changed or color_changed:
				rgba_diff += 1
				changed_bounds = _include_pixel(changed_bounds, x, y)
				if y < 40:
					head_diff += 1
			if first[offset + 3] > 0:
				baseline_visible = _include_pixel(baseline_visible, x, y)
			if second[offset + 3] > 0:
				current_visible = _include_pixel(current_visible, x, y)
	report["alpha_diff_pixels"] = alpha_diff
	report["color_diff_pixels"] = color_diff
	report["visible_color_diff_pixels"] = visible_color_diff
	report["rgba_diff_pixels"] = rgba_diff
	report["rgba_diff_bbox"] = _bbox_report(changed_bounds)
	report["head_y_lt_40_rgba_diff_pixels"] = head_diff
	report["visible_alpha_nonzero_bbox"] = {"baseline": _bbox_report(baseline_visible), "current": _bbox_report(current_visible)}


func _include_pixel(bounds: Rect2i, x: int, y: int) -> Rect2i:
	var pixel := Rect2i(x, y, 1, 1)
	return bounds.merge(pixel) if bounds.has_area() else pixel


func _bbox_report(bounds: Rect2i) -> Variant:
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y] if bounds.has_area() else null


func _usage_error(message: String) -> void:
	push_error(message + " Usage: --baseline=/absolute/player-before.svg [--report=res://reports/player-material-raster.json]")
	quit(2)
