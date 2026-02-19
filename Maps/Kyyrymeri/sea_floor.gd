#Seafloor.gd
extends MeshInstance3D

@export var map_size = Vector2(5000, 5000)
@export var height_multiplier = 10.0
@export var noise_frequency = 0.005 # Pienennä tätä, jos haluat loivempaa



func generate(seed_val: int):
	print("--- Maaston generointi alkaa ---")
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = noise_frequency
	
	# 1. Luodaan perusverkko
	var plane = PlaneMesh.new()
	plane.size = map_size
	plane.subdivide_depth = 200 # Lisää jakoja (huom! syö tehoja)
	plane.subdivide_width = 200
	
	# 2. Muokataan korkeutta
	var st = SurfaceTool.new()
	st.create_from(plane, 0)
	var array_mesh = st.commit()
	var data = MeshDataTool.new()
	data.create_from_surface(array_mesh, 0)
	
	for i in range(data.get_vertex_count()):
		var v = data.get_vertex(i)
		
		# 1. Haetaan normaali noise-arvo
		var noise_val = noise.get_noise_2d(v.x, v.z)
		var base_height = noise_val * height_multiplier
		
		# 2. Lasketaan etäisyys reunoista (0.0 = keskellä, 1.0 = reunalla)
		# Käytetään normalisoituja koordinaatteja (0-1 asteikko)
		var dist_x = abs(v.x) / (map_size.x * 0.5)
		var dist_z = abs(v.z) / (map_size.y * 0.5)
		
		# Valitaan kumpi reuna on lähempänä
		var edge_factor = max(dist_x, dist_z)
		
		# 3. Nostetaan reunoja jyrkästi (tässä tapauksessa kynnys on 0.8 eli viimeiset 20%)
		var wall_height = 0
		if edge_factor > 0.8:
			# Lasketaan kuinka paljon ollaan "kynnyksen" yli
			var steepness = (edge_factor - 0.8) / 0.2 
			# Nostetaan reunaa esim. 50 yksikköä (reilusti yli pinnan)
			wall_height = pow(steepness, 2) * 75.0 
		
		v.y = base_height + wall_height
		data.set_vertex(i, v)
	
	# 3. Päivitetään mesh ja normaalit
	var final_mesh = ArrayMesh.new()
	data.commit_to_surface(final_mesh)
	st.clear()
	st.create_from(final_mesh, 0)
	st.generate_normals()
	self.mesh = st.commit()
	# Lasketaan uusi koko meshille, jotta se ei katoa näkyvistä (Culling)
	# x ja z ovat map_size, y on korkeus (noise + seinät)
	var aabb_size = Vector3(map_size.x,  100.0, map_size.y)
	var aabb_pos = Vector3(-map_size.x / 2.0, -80, -map_size.y / 2.0)
	self.custom_aabb = AABB(aabb_pos, aabb_size)

	# --- 3.1 LISÄTÄÄN SHADER TÄHÄN ---
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://Maps/Kyyrymeri/SeaFloorShader.gdshader")
	
	# Lähetetään korkeuskerroin shaderille, jotta värit skaalautuvat oikein
	shader_mat.set_shader_parameter("height_range", height_multiplier)
	
	# Asetetaan materiaali meshille
	self.material_override = shader_mat
	# ---------------------------------

	
	var shape_node = get_parent()
	if shape_node is CollisionShape3D:
		shape_node.shape = self.mesh.create_trimesh_shape()
