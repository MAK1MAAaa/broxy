extends SceneTree
## A frozen view of the existing title/settings, without personal profile IO.

func _initialize() -> void:
	_preview.call_deferred()

func _preview() -> void:
	var output: String = "res://reports/starfall/title.png"
	var settings: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			output = argument.trim_prefix("--capture=")
		elif argument == "--settings":
			settings = true
		else:
			quit(2)
			return
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.title = "秘术余烬 · 现有界面美术验证（不保存档案）"
	var ui := GameUI.new()
	root.add_child(ui)
	ui.show_title({})
	var cover := ui.find_child("MenuArtwork", true, false) as TitleCover
	if cover != null:
		cover.set_frame(0)
	if settings:
		ui._show_settings(false)
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("ART_RESKIN_PREVIEW ", JSON.stringify({"capture": output, "settings": settings,
		"fixed_fixture": true, "personal_profile_io": false, "result": result, "revision": AdventureArt.REVISION}))
	quit(0 if result == OK else 1)
