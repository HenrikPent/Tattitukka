extends Node

var depth_levels = [-4.0, -30.0, -60.0, -90.0]
@export var dive_speed := 5.0
@export var underwater_edge := -15.0 

@export var sync_depth_index := 0

@onready var parent = get_parent()
var last_sent_underwater_state := false # Tallennetaan edellinen tila rämpytyksen estoksi

func _physics_process(delta: float) -> void:
	if parent.is_multiplayer_authority():
		_read_dive_input()
		
		var target_y = depth_levels[sync_depth_index]
		parent.global_position.y = move_toward(parent.global_position.y, target_y, dive_speed * delta)
		
		# Tarkistetaan tilan muutos vain tarvittaessa
		_check_underwater_transition()

func _read_dive_input() -> void:
	if UnitManager.controlled_unit != parent:
		return
	
	if Input.is_action_just_pressed("dive_down"):
		sync_depth_index = clampi(sync_depth_index + 1, 0, depth_levels.size() - 1)
	elif Input.is_action_just_pressed("surface_up"):
		sync_depth_index = clampi(sync_depth_index - 1, 0, depth_levels.size() - 1)

func _check_underwater_transition():
	# Haetaan kamera suoraan UnitManagerin kautta tai globaalisti kerran
	# (find_child joka framella on todella raskas ja hakee usein väärän noda)
	var camera_rig = get_viewport().get_camera_3d().get_parent() # Oletetaan että rig on kameran parent
	
	if not camera_rig or not camera_rig.has_method("set_underwater"):
		return

	var is_currently_under = parent.global_position.y < underwater_edge
	
	# MUUTOS: Päivitetään vain, jos tila OIKEASTI muuttuu
	if is_currently_under != last_sent_underwater_state:
		camera_rig.set_underwater(is_currently_under)
		last_sent_underwater_state = is_currently_under
		# Printataan vain kerran muutoksen yhteydessä debuggausta varten
	
