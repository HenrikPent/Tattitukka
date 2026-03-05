# CameraRig.gd
extends Node3D

@export var rotate_speed := 0.15 
@export var binocular_fov_levels = [45.0, 20.0, 10.0, 5.0, 2.0]
@export var normal_fov := 75.0

var zoom_step := 0 
var rotation_x := 0.0
var rotation_y := 0.0
var current_offset_dist := 20.0

var controlled_unit: Node3D = null
var is_underwater := false
var water_fog: FogVolume = null
var current_max_x := 85.0 # vesi kameraa varten

@onready var binocular_ui = get_node_or_null("BinocularUI")
var last_hit_node: Node3D = null


func _ready():
	# Haetaan sumu kerran talteen muistiin
	water_fog = get_tree().get_first_node_in_group("WaterFogGroup")

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(controlled_unit) or not get_parent().is_multiplayer_authority():
		return
	
	var is_fixed = controlled_unit.get("cam_mode_fixed") if "cam_mode_fixed" in controlled_unit else false
	
	if not is_fixed and event is InputEventMouseMotion:
		var sensitivity_multiplier = 1.0
		if zoom_step >= 2:
			sensitivity_multiplier = get_viewport().get_camera_3d().fov / normal_fov
			
		rotation_y -= event.relative.x * rotate_speed * sensitivity_multiplier
		rotation_x += event.relative.y * rotate_speed * sensitivity_multiplier
		
		# Käytetään dynaamista rajaa kiinteän sijaan
		rotation_x = clamp(rotation_x, -85, current_max_x)

	if event is InputEventMouseButton and event.pressed:
		var old_step = zoom_step
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_step = clampi(zoom_step + 1, 0, 1 + binocular_fov_levels.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_step = clampi(zoom_step - 1, 0, 1 + binocular_fov_levels.size())
			
		if old_step != zoom_step:
			_handle_zoom_change()

func _process(delta: float) -> void:
	if not get_parent().is_multiplayer_authority(): return
	
	# --- PEHMEÄ RAJA-TRANSITIO ---
	var target_max_x = 5.0 if is_underwater else 85.0
	# Liikutetaan rajaa pehmeästi kohti tavoitetta (nopeus 5.0, voit säätää tätä)
	current_max_x = lerp(current_max_x, target_max_x, delta * 5.0)
	
	# Jos nykyinen kulma on rajan ulkopuolella (esim. juuri sukelluksen alkaessa),
	# pakotetaan se liukumaan rajan mukana
	if rotation_x > current_max_x:
		rotation_x = current_max_x
	
	_manage_unit_selection()
	if not is_instance_valid(controlled_unit) or not controlled_unit.is_inside_tree():
		CameraData.hit_node = null
		return

	var cam_node = get_viewport().get_camera_3d()
	if not cam_node: return
	
	var is_fixed = controlled_unit.get("cam_mode_fixed") if "cam_mode_fixed" in controlled_unit else false
	var is_binoc = zoom_step >= 2
	
	if is_fixed:
		_update_fixed_camera(cam_node, delta)
	elif is_binoc:
		_update_binocular_camera(cam_node, delta)
	elif is_underwater:
		_update_underwater_camera(cam_node, delta)
	else:
		_update_surface_camera(cam_node, delta)

	_update_aim_data(cam_node)

# --- TILAFUNKTIOT ---

func _update_fixed_camera(cam: Camera3D, delta: float):
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	global_transform = controlled_unit.global_transform
	cam.position = Vector3(0, unit_offset.y, current_offset_dist)
	var target_look = global_position + (-global_transform.basis.z * 10)
	cam.look_at(target_look, global_transform.basis.y)
	cam.fov = lerp(cam.fov, normal_fov, delta * 10.0)

func _update_binocular_camera(cam: Camera3D, delta: float):
	if binocular_ui: binocular_ui.visible = true
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var target_center = controlled_unit.global_position + unit_offset
	var target_fov = binocular_fov_levels[zoom_step - 2]
	var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
	
	global_position = target_center
	global_basis = Basis(quat)
	cam.fov = lerp(cam.fov, target_fov, delta * 15.0)

func _update_surface_camera(cam: Camera3D, delta: float):
	if binocular_ui: binocular_ui.visible = false
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var target_center = controlled_unit.global_position + unit_offset
	var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
	
	var rotated_offset = quat * Vector3(0, 0, current_offset_dist)
	global_position = target_center + rotated_offset
	look_at(target_center, Vector3.UP)
	cam.fov = lerp(cam.fov, normal_fov, delta * 15.0)

func _update_underwater_camera(cam: Camera3D, delta: float):
	if binocular_ui: binocular_ui.visible = false
	
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var target_center = controlled_unit.global_position + unit_offset
	
	# Käytetään suoraan rotation_x, koska se rajoitetaan unhandled_inputissa
	var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
	var rotated_offset = quat * Vector3(0, 0, current_offset_dist)
	
	global_position = target_center + rotated_offset
	look_at(target_center, Vector3.UP)
	cam.fov = lerp(cam.fov, normal_fov, delta * 15.0)

# --- APUFUNKTIOT ---

func _manage_unit_selection():
	var active_unit = UnitManager.controlled_unit
	if active_unit != controlled_unit:
		controlled_unit = active_unit
		if is_instance_valid(controlled_unit):
			_on_unit_switched()

func _update_aim_data(cam: Camera3D):
	var sc = cam.get_node_or_null("ShapeCast3D")
	if sc:
		sc.force_shapecast_update()
		if sc.is_colliding():
			var collider = sc.get_collider(0)
			CameraData.hit_position = sc.get_collision_point(0)
			CameraData.hit_node = collider
			if collider != last_hit_node:
				last_hit_node = collider
		else:
			var ray_dir = -cam.global_transform.basis.z.normalized()
			var plane = Plane(Vector3.UP, 0)
			var intersection = plane.intersects_ray(cam.global_position, ray_dir)
			CameraData.hit_position = intersection if intersection else cam.global_position + ray_dir * 4000.0
			CameraData.hit_node = null
			last_hit_node = null

func _handle_zoom_change():
	var d_near = 10.0
	var d_far = 40.0
	
	if is_instance_valid(controlled_unit):
		var unit_near = controlled_unit.get("cam_near")
		if unit_near != null: d_near = unit_near
		var unit_far = controlled_unit.get("cam_far")
		if unit_far != null: d_far = unit_far
	
	if is_underwater:
		d_near *= 1
		d_far *= 1

	match zoom_step:
		0: current_offset_dist = d_far
		1: current_offset_dist = d_near
		_: current_offset_dist = 0.0

func _on_unit_switched():
	zoom_step = 1
	_handle_zoom_change()
	if not controlled_unit.get("cam_mode_fixed"):
		rotation_y = controlled_unit.global_rotation_degrees.y + 180
		rotation_x = 20

func set_underwater(active: bool):
	is_underwater = active
	
	
