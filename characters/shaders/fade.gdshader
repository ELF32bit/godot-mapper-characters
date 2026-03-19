shader_type spatial;

uniform sampler2D albedo_texture: source_color, hint_default_white;
uniform float fade = 0.0;


void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	METALLIC = 0.0; SPECULAR = 0.0;
	ALPHA = 1.0 - fade;
}
