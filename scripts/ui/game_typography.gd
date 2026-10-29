class_name GameTypography
extends RefCounted

const FONT_SOURCE: FontFile = preload("res://assets/fonts/fusion-pixel-12px-proportional-zh-hans.otf")

static var _font: FontFile


static func font() -> Font:
	if _font == null:
		_font = FONT_SOURCE
		_font.allow_system_fallback = false
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.force_autohinter = false
		_font.oversampling = 1.0
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.multichannel_signed_distance_field = false
		_font.generate_mipmaps = false
	return _font


static func size_for(requested: int) -> int:
	if requested <= 19:
		return 12
	if requested <= 31:
		return 24
	if requested <= 43:
		return 36
	return 48
