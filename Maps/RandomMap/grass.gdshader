shader_type spatial;

// --- Tekstuurit ja värit ---
uniform sampler2D noise_tex : source_color;
uniform vec3 grass_color_light : source_color = vec3(0.2, 0.5, 0.1);
uniform vec3 grass_color_dark : source_color = vec3(0.1, 0.3, 0.05);
uniform vec3 dirt_color : source_color = vec3(0.2, 0.15, 0.1);

varying vec3 world_pos;

void vertex() {
	// TÄRKEÄÄ: Ei muuteta VERTEX.y:tä tässä!
	// Luetaan vain sijainti maailmassa, jotta nurmikon tiheys pysyy vakiona.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Nämä luvut vaikuttavat vain siihen, kuinka tiheältä nurmikon kuvio näyttää,
	// eivät itse maaston kokoon.
	float grass_scale = 15.0;  
	float patch_scale = 0.2;   
	
	float grass_noise = texture(noise_tex, world_pos.xz * grass_scale).r;
	float patch_noise = texture(noise_tex, world_pos.xz * patch_scale).r;
	
	vec3 grass_base = mix(grass_color_dark, grass_color_light, grass_noise);
	vec3 final_color = mix(dirt_color, grass_base, smoothstep(0.4, 0.6, patch_noise));
	
	ALBEDO = final_color;
	ROUGHNESS = 1.0;
}