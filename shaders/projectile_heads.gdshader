shader_type canvas_item;

varying flat float head_column;
varying flat float is_head;
varying vec4 head_color;

void vertex() {
	is_head = abs(INSTANCE_CUSTOM.y - 0.5) < 0.001 && abs(INSTANCE_CUSTOM.z - 0.25) < 0.001 ? 1.0 : 0.0;
	head_column = round(INSTANCE_CUSTOM.x * 31.0);
	head_color = COLOR;
}

void fragment() {
	if (is_head > 0.5) {
		vec2 texel = clamp(floor(UV * 64.0), vec2(0.0), vec2(63.0));
		vec2 atlas_uv = vec2(head_column * 64.0 + texel.x + 0.5, texel.y + 0.5) / vec2(2048.0, 64.0);
		COLOR = head_color * texture(TEXTURE, atlas_uv);
	}
}
