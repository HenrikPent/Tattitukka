#Turret
extends Node3D


@export var gun: Node3D
@export var muzzles: Array[Node3D] = []

# Kaliiperit ja niiden asetukset
enum CaliberType { CAL_127mm, CAL_280mm, CAL_406mm }
@export var caliber: CaliberType = CaliberType.CAL_127mm

var caliber_settings = {
	CaliberType.CAL_127mm: {
		"projectile_type": "127mm",
		"speed": 250.0,
		"gravity": 9.81,
		"yaw_speed": 40.0,
		"pitch_speed": 30.0,
		"up_max": 75.0,   # Pienet tykit nousevat jyrkemmin
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

# Sisäiset muuttujat, jotka täytetään _ready-vaiheessa
var projectile_speed: float
var gravity: float
var projectile_name: String
var yaw_speed: float
var pitch_speed: float
var current_up_max: float
var current_down_max: float

var current_target: Node3D = null

func _ready():
	# 1. Haetaan asetukset kaliiperin perusteella
	var settings = caliber_settings[caliber]
	
	projectile_speed = settings["speed"]
	gravity = settings["gravity"]
	projectile_name = settings["projectile_type"]
	
	yaw_speed = settings["yaw_speed"]
	pitch_speed = settings["pitch_speed"]
	current_up_max = settings["up_max"]
	current_down_max = settings["down_max"]

	# 2. annetaan tiedot turretin omille muzzleille 
	for muzzle in muzzles:
		if "projectile_type" in muzzle:
			muzzle.projectile_type = projectile_name
		if "projectile_speed" in muzzle:
			muzzle.projectile_speed = projectile_speed


func _process(delta: float) -> void:
	if get_parent() != UnitManager.controlled_unit:
		return
		
	# 1. TUNNISTA TÄHTÄYSPISTE (Raycast suoraan tässä)
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_pos = get_viewport().get_visible_rect().size / 2
		
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_dir = cam.project_ray_normal(mouse_pos)
	
	# Ammutaan säde maailmaan
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 2000)
	query.collision_mask = 4 # Kerros, jossa meri/maa on
	var result = space_state.intersect_ray(query)
	
	var final_target_pos: Vector3
	if result:
		final_target_pos = result.position
	else:
		# Jos ei osuta mihinkään, tähdätään kauas horisonttiin
		final_target_pos = ray_origin + (ray_dir * 1000.0)

	# 2. BALLISTINEN LASKENTA (Käyttäen tätä juuri laskettua pistettä)
	var diff = final_target_pos - gun.global_transform.origin
	var x = Vector2(diff.x, diff.z).length()
	var y = diff.y
	var v = projectile_speed
	var g = gravity
	
	var v2 = v * v
	var root = v2 * v2 - g * (g * (x * x) + 2 * y * v2)

	var target_pitch: float
	if root >= 0:
		target_pitch = atan((v2 - sqrt(root)) / (g * x))
	else:
		target_pitch = deg_to_rad(45.0) # Maksimikantama

	# 3. KÄÄNTÄMINEN (Yaw & Pitch)
	# (Tässä käytät samaa clamp-logiikkaa kuin aiemminkin)
	var desired_yaw = atan2(-diff.x, -diff.z)
	var yaw_diff = wrapf(desired_yaw - global_rotation.y, -PI, PI)
	global_rotation.y += clamp(yaw_diff, -deg_to_rad(yaw_speed * delta), deg_to_rad(yaw_speed * delta))
	
	var pitch_diff = target_pitch - gun.rotation.x
	gun.rotation.x += clamp(pitch_diff, -deg_to_rad(pitch_speed * delta), deg_to_rad(pitch_speed * delta))
	# 4. AMMUNTA
	if Input.is_action_pressed("fire") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		fire_muzzle()



func update_target():
	var hit_node = CameraData.hit_node
	if hit_node and hit_node.is_in_group("Units") and hit_node != get_parent():
		current_target = hit_node
	else:
		if not Input.is_action_pressed("fire"):
			current_target = null

func get_predicted_position(target: Node3D) -> Vector3:
	var target_pos = target.global_position
	var shooter_pos = gun.global_position
	var distance = shooter_pos.distance_to(target_pos)
	var t_flight = distance / projectile_speed
	
	var t_speed = target.get("speed") if "speed" in target else 0.0
	var t_steering = target.get("steering_angle") if "steering_angle" in target else 0.0
	var t_forward = -target.global_transform.basis.z.normalized()
	
	if abs(t_steering) < 0.01:
		return target_pos + (t_forward * t_speed * t_flight)
	else:
		var angle_change = t_steering * t_flight
		var rotated_dir = t_forward.rotated(Vector3.UP, angle_change)
		var average_dir = t_forward.lerp(rotated_dir, 0.5).normalized()
		return target_pos + (average_dir * t_speed * t_flight)

func fire_muzzle() -> void:
	var shooter_id = owner.get_multiplayer_authority()
	for muzzle in muzzles:
		# Tiedot on jo asetettu _ready-vaiheessa, joten täällä vain ammutaan!
		if muzzle.turret_control and muzzle.gun_index != -1:
			var permission = muzzle.turret_control.fire_permissions[muzzle.gun_index]
			if permission == 1:
				if muzzle.has_method("action_fire"):
					muzzle.action_fire(shooter_id)
		else:
			if muzzle.has_method("action_fire"):
				muzzle.action_fire(shooter_id)
