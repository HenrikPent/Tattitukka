extends Node

var hit_position: Vector3 = Vector3.ZERO
var hit_node: Node3D = null # TÄMÄ LISÄTTY: kertoo mitä hiiri osoittaa

func _process(_delta):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_direction * 2000 # Ammuntapiiri 2km
	
	# 1. FYSIKKAKYSELY (Raycast)
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	
	# Valinnainen: Jos et halua että kamera osuu esim. läpinäkyviin efekteihin
	query.collision_mask = 4 
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Hiiri on fyysisen kohteen päällä (laiva, saari jne.)
		hit_position = result.position
		hit_node = result.collider
	else:
		# Hiiri on "tyhjässä", käytetään tasoa (meri) tähtäyspisteenä
		hit_node = null
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(ray_origin, ray_direction)
		if intersection:
			hit_position = intersection
