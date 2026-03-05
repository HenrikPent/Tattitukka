# CameraRig.gd
extends Node3D

@export var rotate_speed := 0.15 
@export var binocular_fov_levels = [45.0, 20.0, 10.0, 5.0, 2.0] # 5 eri zoom-tasoa
@export var normal_fov := 75.0

# Tilamuuttujat
# 0 = Far, 1 = Near, 2+ = Binocular zoom tasot
var zoom_step := 0 
var rotation_x := 0.0
var rotation_y := 0.0
var current_offset_dist := 20.0

var controlled_unit: Node3D = null

# Viittaus UI-maskiin (jos lisäät sellaisen)
@onready var binocular_ui = get_node_or_null("BinocularUI")

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(controlled_unit) or not get_parent().is_multiplayer_authority():
		return
	
	var is_fixed = controlled_unit.get("cam_mode_fixed") if "cam_mode_fixed" in controlled_unit else false
	
	# --- Hiiren kääntäminen ---
	if not is_fixed and event is InputEventMouseMotion:
		# Pienennetään herkkyyttä, kun zoomataan syvälle kiikareilla
		var sensitivity_multiplier = 1.0
		if zoom_step >= 2:
			# Lasketaan kerroin FOV:n perusteella (pienempi FOV = hitaampi liike)
			sensitivity_multiplier = get_viewport().get_camera_3d().fov / normal_fov
			
		rotation_y -= event.relative.x * rotate_speed * sensitivity_multiplier
		rotation_x += event.relative.y * rotate_speed * sensitivity_multiplier
		rotation_x = clamp(rotation_x, -85, 85)

	# --- Zoom-logiikka rullalla ---
	if event is InputEventMouseButton and event.pressed:
		var old_step = zoom_step
		
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoomataan sisään: Max step on 1 (near) + fov_levels määrä
			zoom_step = clampi(zoom_step + 1, 0, 1 + binocular_fov_levels.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoomataan ulos
			zoom_step = clampi(zoom_step - 1, 0, 1 + binocular_fov_levels.size())
			
		if old_step != zoom_step:
			_handle_zoom_change()

func _process(delta: float) -> void:
	# VAIN paikallinen pelaaja saa säätää kameraansa
	if not get_parent().is_multiplayer_authority():
		return
	
	var active_unit = UnitManager.controlled_unit
	
	if active_unit != controlled_unit:
		controlled_unit = active_unit
		if is_instance_valid(controlled_unit):
			_on_unit_switched()

	if not is_instance_valid(controlled_unit):
		return

	var is_fixed = controlled_unit.get("cam_mode_fixed") if "cam_mode_fixed" in controlled_unit else false
	var unit_offset = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var cam_node = get_viewport().get_camera_3d()
	
	if not cam_node: return

	if is_fixed:
		# --- LENTOKONE (Fixed) ---
		global_transform = controlled_unit.global_transform
		cam_node.position = Vector3(0, unit_offset.y, current_offset_dist)
		var target_look = global_position + (-global_transform.basis.z * 10)
		cam_node.look_at(target_look, global_transform.basis.y)
		cam_node.fov = lerp(cam_node.fov, normal_fov, delta * 10.0)
		if binocular_ui: binocular_ui.visible = false
	
	else:
		# --- LAIVA (Vapaa/Kiikari) ---
		var is_binoc = zoom_step >= 2
		var target_fov = normal_fov
		var target_dist = current_offset_dist
		
		if is_binoc:
			target_dist = 0.0
			target_fov = binocular_fov_levels[zoom_step - 2]
			if binocular_ui: binocular_ui.visible = true
		else:
			if binocular_ui: binocular_ui.visible = false
		
		# Lasketaan kääntyminen Quaternionilla
		var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
		var target_center = controlled_unit.global_position + unit_offset
		
		if is_binoc:
			# KIIKARITILA: Kamera on paikallaan ja kääntyy oman akselinsa ympäri
			global_position = target_center
			# Käytetään rotaatiota suoraan look_at:n sijaan
			global_basis = Basis(quat)
		else:
			# VAPAA TILA: Kamera kiertää laivaa ja katsoo keskelle
			var rotated_offset = quat * Vector3(0, 0, target_dist)
			global_position = target_center + rotated_offset
			look_at(target_center, Vector3.UP)
		
		# Varmistetaan, että target_fov on aina järkevä (esim. jos binocular_fov_levels on tyhjä)
		if target_fov <= 0: target_fov = normal_fov
	
		# Pehmeä FOV-muutos clampattuna välille 1.0 - 170.0
		var next_fov = lerp(cam_node.fov, target_fov, delta * 15.0)
		cam_node.fov = clamp(next_fov, 1.0, 170.0)

	# Päivitetään CameraData
	var ray_direction = -global_transform.basis.z.normalized()
	CameraData.hit_position = global_position + ray_direction * 2000.0

func _handle_zoom_change():
	# Haetaan unitin asetukset
	var d_near = controlled_unit.get("cam_near") if "cam_near" in controlled_unit else 10.0
	var d_far = controlled_unit.get("cam_far") if "cam_far" in controlled_unit else 40.0
	
	match zoom_step:
		0: current_offset_dist = d_far
		1: current_offset_dist = d_near
		_: current_offset_dist = 0.0 # Kiikaritila

func _on_unit_switched():
	# Resetoidaan zoomi Near-tilaan vaihdettaessa
	zoom_step = 1
	_handle_zoom_change()
	
	if not controlled_unit.get("cam_mode_fixed"):
		rotation_y = controlled_unit.global_rotation_degrees.y + 180
		rotation_x = 20
