shader_type canvas_item;

uniform vec4 tint_color: source_color = vec4(1.0, 1.0, 1.0,1.0);
uniform float tint_amount: hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, tint_color.rgb, tint_amount), tex.a);
}