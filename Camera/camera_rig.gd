# CameraRig.gd
extends Node3D

@export var rotate_speed := 0.15 
@export var zoom_speed := 2.0

var offset_distance := 5.0 
var rotation_x := 0.0
var rotation_y := 0.0

var controlled_unit: Node3D = null
var last_unit: Node3D = null 

func _unhandled_input(event: InputEvent) -> void:
	if not get_parent().is_multiplayer_authority():
		return
	
	# Vapaa kamera liikkuu vain, jos unitti ei pakota kiinteää kameraa
	var is_fixed = controlled_unit.get("cam_mode_fixed") if controlled_unit else false
	
	if not is_fixed and event is InputEventMouseMotion:
		rotation_y -= event.relative.x * rotate_speed
		rotation_x += event.relative.y * rotate_speed
		rotation_x = clamp(rotation_x, -85, 85)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			offset_distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			offset_distance += zoom_speed

func _process(_delta: float) -> void:
	# 1. Haetaan unitti suoraan UnitManagerista
	var active_unit = UnitManager.controlled_unit
	
	# 2. Tarkistetaan onko unitti vaihtunut tai vanha kadonnut
	if active_unit != controlled_unit:
		controlled_unit = active_unit
		if is_instance_valid(controlled_unit):
			_on_unit_switched()

	# Jos meillä ei ole unittia, ei tehdä mitään
	if not is_instance_valid(controlled_unit):
		return

	# --- Tästä eteenpäin unitti on varmasti elossa ---

	# 1. Haetaan unitin säädöt (fixed mode, offsetti ja rajoittimet)
	var is_fixed = controlled_unit.get("cam_mode_fixed") if "cam_mode_fixed" in controlled_unit else false
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var min_dist = controlled_unit.get("cam_min_dist") if "cam_min_dist" in controlled_unit else 2.0
	var max_dist = controlled_unit.get("cam_max_dist") if "cam_max_dist" in controlled_unit else 100.0
	
	offset_distance = clamp(offset_distance, min_dist, max_dist)

	if is_fixed:
		# --- KIINTEÄ KAMERA (Lentokone) ---
		# Kopioidaan koko transformi (sisältää paikan, suunnan ja kallistuksen)
		global_transform = controlled_unit.global_transform
		
		# Haetaan varsinainen kamera
		var cam_node = get_viewport().get_camera_3d()
		if cam_node:
			# Asetetaan kamera rigin "sisälle" taaksepäin
			cam_node.position = Vector3(0, unit_offset.y, offset_distance)
			
			# TÄRKEÄÄ: Katsotaan eteenpäin käyttäen koneen omaa yläsuuntaa (basis.y)
			# Tämä sallii kameran kallistua koneen mukana
			var target_look = global_position + (-global_transform.basis.z * 10)
			cam_node.look_at(target_look, global_transform.basis.y)
	
	else:
		# --- VAPAA KAMERA (Laiva) ---
		var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
		var rotated_offset = quat * Vector3(0, 0, offset_distance)
		var target_center = controlled_unit.global_position + unit_offset
		
		global_position = target_center + rotated_offset
		look_at(target_center, Vector3.UP)

	# 5. Päivitetään CameraData tähystystä varten
	var ray_direction = -global_transform.basis.z.normalized()
	CameraData.hit_position = global_position + ray_direction * 1000.0

func _on_unit_switched():
	if "cam_min_dist" in controlled_unit:
		var d_min = controlled_unit.cam_min_dist
		var d_max = controlled_unit.cam_max_dist
		offset_distance = d_min + (d_max - d_min) * 0.2
		
		# Jos vaihdetaan vapaaseen kameraan, nollataan katselusuunta kohteen taakse
		if not controlled_unit.get("cam_mode_fixed"):
			rotation_y = controlled_unit.global_rotation_degrees.y + 180
			rotation_x = 20
