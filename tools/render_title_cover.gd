extends SceneTree
## Bake the same discrete frames used by the real title animation; no profile IO.

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	var directory: String = "res://reports/title-cover/frames"
	var with_ui: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			directory = argument.trim_prefix("--output=")
		elif argument == "--ui":
			with_ui = true
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 封面帧输出（不保存档案）"
	var cover: TitleCover
	if with_ui:
		var ui := GameUI.new()
		root.add_child(ui)
		ui.show_title({})
		cover = ui.find_child("MenuArtwork", true, false) as TitleCover
	else:
		cover = TitleCover.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(cover)
	if cover == null:
		push_error("The actual title must expose its real cover player")
		quit(1)
		return
	cover.set_playing(false)
	root.warp_mouse(Vector2(20, 20))
	for settle: int in 4:
		await process_frame
	var output: String = ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(1)
		return
	for index: int in TitleCover.FRAME_COUNT:
		cover.set_frame(index)
		await process_frame
		await RenderingServer.frame_post_draw
		var file: String = output.path_join("frame_%02d.png" % index)
		var error: Error = root.get_texture().get_image().save_png(file)
		if error != OK:
			push_error("Could not save animation frame: " + file)
			quit(1)
			return
		print("TITLE_COVER_FRAME ", JSON.stringify({"frame": index, "path": file, "sha256": FileAccess.get_sha256(file)}))
	cover.set_frame(TitleCover.FRAME_COUNT)
	await process_frame
	await RenderingServer.frame_post_draw
	var loop_matches: bool = root.get_texture().get_image().get_data() == Image.load_from_file(output.path_join("frame_00.png")).get_data()
	if not loop_matches:
		push_error("The frame count wraps to the identical first frame")
		quit(1)
		return
	print("TITLE_COVER_BAKE ", JSON.stringify({"frames": TitleCover.FRAME_COUNT,
		"frame_seconds": TitleCover.FRAME_SECONDS, "with_ui": with_ui, "profile_io": false,
		"viewport": [1280, 720], "directory": directory, "loop_frame_zero_matches": loop_matches,
		"gif_sha256": FileAccess.get_sha256("res://assets/title/cover.gif"), "player": cover.snapshot()}))
	quit(0)
