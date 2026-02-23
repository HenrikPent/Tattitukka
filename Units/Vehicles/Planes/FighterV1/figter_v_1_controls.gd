extends CharacterBody3D

@export_group("Stats")
@export var team_id: int = 0
@export var health: int = 200

@export_group("Camera Settings")
@export var cam_mode_fixed: bool = true
@export var cam_offset := Vector3(0, 4, 0) 
@export var cam_min_dist := 5.0
@export var cam_max_dist := 40.0

@export_group("Flight Physics")
var min_thrust: float = 100.0
var max_thrust: float = 600.0
var thrust_change: float = 250.0
var plane_mass: float = 10.0
var pitch_speed: float = 80.0
var roll_speed: float = 100.0
var lift_strength: float = 0.08

# --- SYNC-MUUTTUJAT ---
@export var sync_thrust := 150.0
@export var is_player_controlled := false

# --- AI muuttujat ---
var ai_target_pos := Vector3.ZERO # Tactical Map tarvitsee tämän piirtämiseen
var follow_target: Node3D = null   # Tämänkin lisääminen on hyvä idea myöhempää varten


var gravity: float = 9.81

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if is_player_controlled:
			_handle_movement(delta)
		else:
			_run_ai_logic(delta)
		
		move_and_slide()

func _handle_movement(delta: float) -> void:
	# 1. Työntövoima
	if Input.is_key_pressed(KEY_R):
		sync_thrust += thrust_change * delta
	if Input.is_key_pressed(KEY_F):
		sync_thrust -= thrust_change * delta
	sync_thrust = clamp(sync_thrust, min_thrust, max_thrust)

	# 2. Ohjaus (PALAUTETTU ALKUPERÄINEN LOGIIKKA)
	var roll_input = Input.get_action_strength("right") - Input.get_action_strength("left")
	var pitch_input = Input.get_action_strength("backward") - Input.get_action_strength("forward")

	if pitch_input != 0.0:
		rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch_input * pitch_speed * delta))
	if roll_input != 0.0:
		rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_input * roll_speed * delta))

	_apply_flight_math(delta)

func _run_ai_logic(delta: float) -> void:
	if sync_thrust < 200: sync_thrust += 1.0
	_apply_flight_math(delta)

func _apply_flight_math(delta: float) -> void:
	var forward_dir = -global_transform.basis.z
	var pitch_angle = global_transform.basis.z.angle_to(Vector3.DOWN) - PI / 2.0
	
	velocity = forward_dir * (sync_thrust + sin(pitch_angle) * gravity * plane_mass)

	var lift = velocity.length() * lift_strength * clamp(pitch_angle, -0.5, 0.5)
	velocity.y += lift * delta

func set_team(id: int):
	team_id = id

@rpc("any_peer", "call_local", "reliable")
func receive_damage():
	if not is_multiplayer_authority(): return
	health -= 50
	if health <= 0:
		_die()

func _die():
	global_position += Vector3(0, 100, 0)
	health = 200
