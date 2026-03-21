shader_type spatial;

uniform sampler2D albedo_texture: source_color, hint_default_white;
uniform float fade = 0.0;
uniform float fade_type = 0.0;


void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	METALLIC = 0.0; SPECULAR = 0.0;
	ALPHA = 1.0 - fade;
	if (fade_type < 0.0) { ALBEDO *= vec3(0.0, 0.0, 1.0); }
	else if (fade_type > 0.0) { ALBEDO *= vec3(1.0, 0.0, 0.0); }
}
