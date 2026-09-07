shader_type canvas_item;
render_mode unshaded;

uniform vec4 top_color : source_color = vec4(0.082, 0.145, 0.176, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.031, 0.055, 0.071, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.784, 0.416, 1.0);
uniform vec2 aspect = vec2(1.0);
uniform float speed : hint_range(0.0, 1.0) = 0.12;

float beam(vec2 p, vec2 a, vec2 b, float width) {
	vec2 segment = b - a;
	float along = clamp(dot(p - a, segment) / dot(segment, segment), 0.0, 1.0);
	return 1.0 - smoothstep(width, width + 0.002, length(p - a - along * segment));
}

void fragment() {
	vec2 uv = UV;
	vec2 p = (uv - 0.5) * aspect;
	vec3 color = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));

	// Leave the reading column quiet; grille and stage hardware sit behind the plaque.
	float right_side = smoothstep(0.35, 0.78, uv.x);
	vec2 cell = fract(uv * aspect * 110.0) - 0.5;
	float perforation = 1.0 - smoothstep(0.15, 0.30, length(cell));
	float brushed = fract(sin(dot(floor(uv * vec2(320.0, 1400.0)),
		vec2(12.9898, 78.233))) * 43758.5453);
	color *= 1.0 - perforation * right_side * 0.26;
	color += (brushed - 0.5) * 0.010;

	float truss = beam(uv, vec2(0.88, 0.0), vec2(0.88, 1.0), 0.004);
	truss += beam(uv, vec2(0.98, 0.0), vec2(0.98, 1.0), 0.004);
	vec2 bay = vec2(uv.x, fract(uv.y * 4.0));
	truss += beam(bay, vec2(0.88, 0.0), vec2(0.98, 1.0), 0.003);
	truss += beam(bay, vec2(0.98, 0.0), vec2(0.88, 1.0), 0.003);
	color += vec3(0.035, 0.049, 0.052) * min(truss, 1.0) * 0.45;

	float lamp = exp(-length((uv - vec2(0.76, 0.08)) * aspect) * 3.2);
	float warmth = 0.94 + sin(TIME * speed) * 0.06;
	color += glow_color.rgb * lamp * warmth * 0.10;
	color *= clamp(1.0 - dot(p, p) * 0.22, 0.35, 1.0);
	COLOR = vec4(color, 1.0);
}
