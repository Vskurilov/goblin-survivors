shader_type canvas_item;

// Оттенок приходит цветом вершин — self_modulate спрайта (Actor._make_tint):
// rgb — цвет, альфа — сила (1.0 — без оттенка, 0.5 — полный).
// В Mobile цвет вершин не мешает склейке вызовов отрисовки, поэтому материал у врагов общий.
// В GL Compatibility склейку рвёт каждая смена цвета: там каждый оттенённый враг — свой вызов.
// modulate самого актора не трогать: он смешается с оттенком.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float amount = (1.0 - tint.a) * 2.0;
	COLOR = vec4(mix(tex.rgb, tint.rgb, amount), tex.a);
}