# Turret.gd
extends Node3D

@export var gun: Node3D
@export var muzzles: Array[Node3D] = []

# Kaliberijärjestelmä (säilytetty ennallaan)
enum CaliberType { CAL_127mm, CAL_280mm, CAL_406mm }
@export_group("Caliber")
@export var caliber: CaliberType = CaliberType.CAL_127mm

var caliber_settings = {
	CaliberType.CAL_127mm: {
		"projectile_type": "127mm",
		"speed": 150.0,
		"gravity": 29.81,
		"yaw_speed": 40.0,
		"pitch_speed": 30.0,
		"up_max": 75.0,
		"down_max": -10.0
	},
	CaliberType.CAL_280mm: {
		"projectile_type": "280mm",
		"speed": 180.0,
		"gravity": 9.81,
		"yaw_speed": 15.0,
		"pitch_speed": 10.0,
		"up_max": 45.0,
		"down_max": -5.0
	},
	CaliberType.CAL_406mm: {
		"projectile_type": "406mm",
		"speed": 150.0,
		"gravity": 12.0,
		"yaw_speed": 5.0,
		"pitch_speed": 5.0,
		"up_max": 45.0,
		"down_max": -2.0
	}
}

# Sisäiset muuttujat
var is_player_controlled: bool = true
var attack_target: Node3D = null

var projectile_speed: float
var gravity: float
var projectile_name: String

var yaw_speed: float
var pitch_speed: float
var current_up_max: float
var current_down_max: float

# Debug
var _last_debug_unit: Node = null
var _debug_timer: float = 0.0

func _ready() -> void:
	var s = caliber_settings[caliber]
	projectile_speed = s["speed"]
	gravity          = s["gravity"]
	projectile_name  = s["projectile_type"]
	yaw_speed        = s["yaw_speed"]
	pitch_speed      = s["pitch_speed"]
	current_up_max   = s["up_max"]
	current_down_max = s["down_max"]

	for muzzle in muzzles:
		if "projectile_type" in muzzle:
			muzzle.projectile_type = projectile_name
		if "projectile_speed" in muzzle:
			muzzle.projectile_speed = projectile_speed


func _process(delta: float) -> void:
	if is_player_controlled:
		_process_player(delta)
	else:
		_process_ai(delta)

func _process_player(delta: float) -> void:
	if get_parent() != UnitManager.controlled_unit:
		return

	var aim_pos = _get_aim_position()
	if aim_pos == Vector3.ZERO:
		return

	#_debug_unit_under_aim(aim_pos)
	_rotate_towards(aim_pos, delta)

	if Input.is_action_pressed("fire") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		fire_muzzle()

	# Oikea hiiri — vaihda AI/pelaaja kontrolli
	if Input.is_action_just_pressed("aim_target"):  # oikea hiiri
		_try_set_ai_target(aim_pos)

func _process_ai(delta: float) -> void:
	if not attack_target:
		return

	var aim_pos = attack_target.global_position
	_rotate_towards(aim_pos, delta)
	
	 # katotaan myös AI ohajuksen aikana jotta hallinta voidaan saada takaisin
	if Input.is_action_just_pressed("aim_target"):
		var mouse_aim = _get_aim_position()  # ← hiiren osoittama paikka
		_try_set_ai_target(mouse_aim)


func _try_set_ai_target(aim_pos: Vector3) -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		aim_pos + Vector3.UP * 100.0,
		aim_pos + Vector3.DOWN * 100.0
	)
	query.collision_mask = 8
	query.collide_with_bodies = true
	var result = space.intersect_ray(query)

	var hit_unit = null
	if result:
		var node = result.collider
		while node:
			if node.is_in_group("Units"):
				hit_unit = node
				break
			node = node.get_parent()

	if hit_unit:
		attack_target = hit_unit
		is_player_controlled = false
		print("[Turret:%s] AI tähtää: %s" % [name, hit_unit.name])
	else:
		attack_target = null
		is_player_controlled = true
		print("[Turret:%s] Pelaaja ottaa kontrollin" % name)



# --- TÄHTÄYS ---
func _get_aim_position() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return Vector3.ZERO

	var mouse_pos: Vector2
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_pos = get_viewport().get_visible_rect().size / 2.0
	else:
		mouse_pos = get_viewport().get_mouse_position()

	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_dir    = cam.project_ray_normal(mouse_pos)

	# Raycast maata/merta vasten (layer 4 = bitti 3)
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 2000.0
	)
	query.collision_mask = 8  # layer 3 (maa/meri)

	var result = space.intersect_ray(query)
	if result:
		return result.position
	else:
		return ray_origin + ray_dir * 1000.0


func _rotate_towards(target_pos: Vector3, delta: float) -> void:
	var diff = target_pos - gun.global_transform.origin

	# --- Yaw ---
	var desired_yaw = atan2(-diff.x, -diff.z)
	var yaw_diff    = wrapf(desired_yaw - global_rotation.y, -PI, PI)
	global_rotation.y += clamp(
		yaw_diff,
		-deg_to_rad(yaw_speed * delta),
		 deg_to_rad(yaw_speed * delta)
	)

	# --- Pitch (ballistinen) ---
	var horiz_dist = Vector2(diff.x, diff.z).length()
	var vert_diff  = diff.y
	var target_pitch = _calc_ballistic_pitch(horiz_dist, vert_diff)

	var pitch_diff = target_pitch - gun.rotation.x
	gun.rotation.x += clamp(
		pitch_diff,
		-deg_to_rad(pitch_speed * delta),
		 deg_to_rad(pitch_speed * delta)
	)

	# Rajoitetaan kulma
	gun.rotation.x = clamp(
		gun.rotation.x,
		deg_to_rad(current_down_max),
		deg_to_rad(current_up_max)
	)


func _calc_ballistic_pitch(x: float, y: float) -> float:
	# Klassinen ballistinen kaava, matala kulma
	var v  = projectile_speed
	var g  = gravity
	var v2 = v * v
	var discriminant = v2 * v2 - g * (g * x * x + 2.0 * y * v2)

	if discriminant >= 0.0:
		return atan((v2 - sqrt(discriminant)) / (g * x))
	else:
		return deg_to_rad(45.0)  # Kantama ylitetty → maksimikanta


# --- DEBUG: tulostaa mille unitille tähtätään ---

func _debug_unit_under_aim(aim_pos: Vector3) -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		aim_pos + Vector3.UP * 100.0,
		aim_pos + Vector3.DOWN * 100.0
	)
	query.collision_mask = 8
	query.collide_with_bodies = true
	var result = space.intersect_ray(query)

	var hit_unit = null
	if result:
		var node = result.collider
		while node:
			if node.is_in_group("Units"):
				hit_unit = node
				break
			node = node.get_parent()

	# Tulostetaan vain jos kohde vaihtui TAI sekunti kulunut
	_debug_timer += get_process_delta_time()
	if hit_unit != _last_debug_unit or _debug_timer >= 1.0:
		_debug_timer = 0.0
		_last_debug_unit = hit_unit
		if hit_unit:
			var pos = hit_unit.global_position
			var rot = hit_unit.global_rotation_degrees
			print("[Turret:%s] Tähtää: %s | pos: (%.1f, %.1f, %.1f) | rot: (%.1f, %.1f, %.1f)" % [
				name, hit_unit.name,
				pos.x, pos.y, pos.z,
				rot.x, rot.y, rot.z
			])
		else:
			print("[Turret:%s] Ei tähtää yksikköön" % name)

# --- AMMUNTA ---

func fire_muzzle() -> void:
	var shooter_id = owner.get_multiplayer_authority()
	for muzzle in muzzles:
		if muzzle.turret_control and muzzle.gun_index != -1:
			var permission = muzzle.turret_control.fire_permissions[muzzle.gun_index]
			if permission == 1 and muzzle.has_method("action_fire"):
				muzzle.action_fire(shooter_id)
		elif muzzle.has_method("action_fire"):
			muzzle.action_fire(shooter_id)
