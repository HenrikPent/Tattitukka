extends MeshInstance3D

@export var map_size = Vector2(400, 400)
@export var height_multiplier = 10.0
@export var noise_frequency = 0.01

func generate(seed_val: int):
	print("--- Maaston generointi alkaa ---")
	print("Siemenluku: ", seed_val)
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = noise_frequency
	
	# 1. Luodaan perusverkko
	var plane = PlaneMesh.new()
	plane.size = map_size
	plane.subdivide_depth = 100
	plane.subdivide_width = 100
	
	# 2. Muokataan korkeutta
	var st = SurfaceTool.new()
	st.create_from(plane, 0)
	var array_mesh = st.commit()
	var data = MeshDataTool.new()
	data.create_from_surface(array_mesh, 0)
	
	print("Vertexien määrä: ", data.get_vertex_count())
	
	for i in range(data.get_vertex_count()):
		var v = data.get_vertex(i)
		var noise_val = noise.get_noise_2d(v.x, v.z)
		v.y = noise_val * height_multiplier
		data.set_vertex(i, v)
	
	# 3. Päivitetään mesh ja normaalit
	var final_mesh = ArrayMesh.new()
	data.commit_to_surface(final_mesh)
	st.clear()
	st.create_from(final_mesh, 0)
	st.generate_normals()
	self.mesh = st.commit()
	
	print("Visuaalinen mesh luotu onnistuneesti.")
	
	# 4. PÄIVITETÄÄN FYSIIKKA
	var shape_node = get_parent() # CollisionShape3D
	if shape_node is CollisionShape3D:
		print("Päivitetään fysiikkamuoto (CollisionShape3D)...")
		shape_node.shape = self.mesh.create_trimesh_shape()
		print("Fysiikka päivitetty.")
	else:
		print("VAROITUS: Parent-node ei ole CollisionShape3D! Nimi on: ", shape_node.name)
	
	# 5. Skaalataan vesi
	var water = get_tree().current_scene.find_child("Water", true, false)
	if water: 
		water.scale = Vector3(map_size.x, 1, map_size.y)
		print("Vesi löydetty ja skaalattu.")
	else:
		print("HUOM: 'Water'-nodea ei löytynyt skenestä.")
	
	print("Maasto valmis siemenellä: ", seed_val)
	print("-------------------------------")
