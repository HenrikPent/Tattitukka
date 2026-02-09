extends CharacterBody3D


@export_group("Network")
@export var health: int = 200

@export_group("Flight Physics")
@export var min_thrust: float = 100.0
@export var max_thrust: float = 400.0
@export var thrust_change: float = 150.0
@export var plane_mass: float = 10.0
@export var pitch_speed: float = 60.0
@export var roll_speed: float = 80.0
@export var lift_strength: float = 0.05

# Sisäiset muuttujat
var current_thrust: float = 150.0
var gravity: float = 9.81
var camera: Camera3D = null

var sync_pos: Vector3
var sync_rot: Vector3

@onready var throttle_bar: ProgressBar = $CanvasLayer/ThrottleBar

# --- Verkko ja Alustus ---

func _enter_tree():
	# Asetetaan authority nimen perusteella (oletus että nimi on peer_id)
	set_multiplayer_authority(name.to_int())

func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process(false)
		if has_node("CanvasLayer"): $CanvasLayer.hide()
		return
	
	# Etsitään "haamu" pelaaja ja sen kamera kuten sotilaalla
	var my_player = get_node_or_null("/root/Main/Players/" + name)
	if my_player:
		camera = my_player.get_node("CameraRig/Camera3D")
		camera.make_current()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_local_player() -> bool:
	return multiplayer.get_unique_id() == get_multiplayer_authority()

# --- Päivitykset ---

func _process(_delta):
	if not is_local_player(): return
	
	# UI Päivitys
	if throttle_bar:
		var throttle_percent := inverse_lerp(min_thrust, max_thrust, current_thrust) * 100.0
		throttle_bar.value = throttle_percent

func _physics_process(delta):
	if not is_local_player(): return

	handle_flight(delta)
	move_and_slide()

func handle_flight(delta):
	# 1. Thrustin säätö (R ja F)
	if Input.is_key_pressed(KEY_R):
		current_thrust += thrust_change * delta
	if Input.is_key_pressed(KEY_F):
		current_thrust -= thrust_change * delta
	current_thrust = clamp(current_thrust, min_thrust, max_thrust)

	# 2. Ohjaus (WASD / Nuolet)
	var roll_input = Input.get_action_strength("right") - Input.get_action_strength("left")
	var pitch_input = Input.get_action_strength("backward") - Input.get_action_strength("forward")

	# Pitch (Nokka ylös/alas)
	if pitch_input != 0.0:
		rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch_input * pitch_speed * delta))

	# Roll (Kallistus)
	if roll_input != 0.0:
		rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_input * roll_speed * delta))

	# 3. Liikevektori
	var forward_dir = -transform.basis.z
	var pitch_angle = transform.basis.z.angle_to(Vector3.DOWN) - PI / 2.0
	
	# Lasketaan nopeus: Työntövoima + painovoiman vaikutus nokan asennosta
	velocity = forward_dir * (current_thrust + sin(pitch_angle) * gravity * plane_mass)

	# 4. Yksinkertaistettu nostovoima
	var speed = velocity.length()
	var lift = speed * lift_strength * clamp(pitch_angle, -0.5, 0.5)
	velocity.y += lift * delta

# --- Vaurio ja Respawn (Sotilaan mallista) ---

@rpc("any_peer", "call_local", "reliable")
func receive_damage():
	if not is_multiplayer_authority(): return
	health -= 50 # Lentokone ottaa enemmän lämmiä
	if health <= 0:
		die()

func die():
	health = 200
	# Heitetään kone taivaalle respawnissa
	global_position = Vector3(randf_range(-50, 50), 100, randf_range(-50, 50))
	velocity = Vector3.ZERO
	current_thrust = 150.0
	print("Lentokone ", name, " korjattu ja palautettu taivaalle.")
