// Godot 4.x käyttää shader_type spatial;
shader_type spatial;

uniform vec3 deep_color : source_color = vec3(0.01, 0.03, 0.08);   // Erittäin tumma sini-musta
uniform vec3 shallow_color : source_color = vec3(0.05, 0.2, 0.25); // Tummanvihreän sinertävä
uniform float height_range = 10.0; // Säädä tätä korkeusvaihtelun mukaan

// Tämä muuttuja siirtää tiedon vertex-osasta fragment-osaan
varying float world_height;

void vertex() {
	// Täällä VERTEX.y on vielä oikea maailman koordinaatti
	world_height = VERTEX.y;
}

void fragment() {
	// Nyt käytämme world_height-muuttujaa, joka pysyy samana riippumatta kameran kulmasta
	// Clamp varmistaa, että weight pysyy välillä 0.0 - 1.0
	float weight = clamp((world_height + (height_range * 0.5)) / height_range, 0.0, 1.0);
	
	ALBEDO = mix(deep_color, shallow_color, weight);
	
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
}
