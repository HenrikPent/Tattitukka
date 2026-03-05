#Seafloor.gd
extends MeshInstance3D

@export var map_size = Vector2(5000, 5000)
@export var height_multiplier = 10.0
@export var noise_frequency = 0.005

# --- MUUTTUJAT REUNOILLE ---
@export var edge_wall_height = 99.0 # Kuinka korkealle seinät nousevat
@export var edge_threshold = 0.8     # Missä kohtaa nousu alkaa (0.8 = viimeiset 20%)
@export var edge_steepness = 3.0     # Mitä suurempi, sitä jyrkempi nousun alku
@export var slope_start = 0.93 # Tässä kohdassa nousu alkaa
@export var plateau_start = 0.96 # Tässä kohdassa saavutetaan tasan 200m

func generate(seed_val: int):
	print("--- Maaston generointi alkaa ---")
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = noise_frequency
	
	# 1. Luodaan perusverkko
	var plane = PlaneMesh.new()
	plane.size = map_size
	plane.subdivide_depth = 200 
	plane.subdivide_width = 200
	
	# 2. Muokataan korkeutta
	var st = SurfaceTool.new()
	st.create_from(plane, 0)
	var array_mesh = st.commit()
	var data = MeshDataTool.new()
	data.create_from_surface(array_mesh, 0)
	
	for i in range(data.get_vertex_count()):
		var v = data.get_vertex(i)
		
		# 1. Perus noise-arvo pohjalle
		var noise_val = noise.get_noise_2d(v.x, v.z)
		var base_height = noise_val * height_multiplier
		
		# 2. Etäisyys (0.0 - 1.0)
		var dist_x = abs(v.x) / (map_size.x * 0.5)
		var dist_z = abs(v.z) / (map_size.y * 0.5)
		var edge_factor = max(dist_x, dist_z)
		
		# 3. Kolmivaiheinen logiikka: Pohja -> Viiste -> Tasainen huippu
		if edge_factor > plateau_start:
			# TÄYSIN TASAINEN HUIPPU
			v.y = edge_wall_height
		elif edge_factor > slope_start:
			# JYRKKY VIISTE (Smoothstep tekee siistimmän liitoksen kuin suora viiva)
			var t = (edge_factor - slope_start) / (plateau_start - slope_start)
			# t = smoothstep(0, 1, t) # Valinnainen: pehmentää kulmia entisestään
			v.y = lerp(base_height, edge_wall_height, t)
		else:
			# NORMAALI POHJA
			v.y = base_height
			
		data.set_vertex(i, v)
	
	# 3. Päivitetään mesh ja normaalit
	var final_mesh = ArrayMesh.new()
	data.commit_to_surface(final_mesh)
	st.clear()
	st.create_from(final_mesh, 0)
	st.generate_normals()
	self.mesh = st.commit()

	# Lasketaan dynaaminen AABB seinien korkeuden mukaan
	# x ja z ovat map_size, y kattaa pohjan ja seinät
	var total_height = height_multiplier + edge_wall_height + 100.0
	var aabb_size = Vector3(map_size.x, total_height, map_size.y)
	var aabb_pos = Vector3(-map_size.x / 2.0, -height_multiplier - 50.0, -map_size.y / 2.0)
	self.custom_aabb = AABB(aabb_pos, aabb_size)

	# --- 3.1 LISÄTÄÄN SHADER TÄHÄN ---
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://Maps/Kyyrymeri/SeaFloorShader.gdshader")
	
	# Shaderille tiedoksi kokonaisvaihtelu, jotta värit skaalautuvat
	# Jos haluat seinien olevan erivärisiä, voit kasvattaa tätä arvoa
	shader_mat.set_shader_parameter("height_range", height_multiplier + (edge_wall_height * 0.5))
	
	self.material_override = shader_mat
	
	# Päivitetään fysiikat
	var shape_node = get_parent()
	if shape_node is CollisionShape3D:
		shape_node.shape = self.mesh.create_trimesh_shape()
