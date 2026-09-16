shader_type spatial;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness_amount;
	METALLIC = 0.0;
}
