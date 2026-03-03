# Turret.gd
extends Node3D
@export_group("Setup")
@export var gun: Node3D
@export var muzzles: Array[Node3D] = []
@export var is_front: bool = true

# Kaliberijärjestelmä (säilytetty ennallaan)
enum CaliberType { CAL_127mm, CAL_280mm, CAL_406mm }
@export_group("Caliber")
@export var caliber: CaliberType = CaliberType.CAL_127mm

var caliber_settings = {
	CaliberType.CAL_127mm: {
		"projectile_type": "127mm",
		"speed": 270.0,
		"gravity": 15, #tämä määritelään ammuksen skenessä ammukselle
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
		"gravity": 9.81,
		"yaw_speed": 5.0,
		"pitch_speed": 5.0,
		"up_max": 45.0,
		"down_max": -2.0
	}
}

@export_group("Turret Settings")
@export var forbidden_width: float = 60.0 # kielletyn sektorin leveys asteina (puolet kummallekin puolelle)
var rest_yaw: float:
	get:
		return 0.0 if is_front else 180.0# lepoasento asteina, 0 = keula, 180 = perä

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

var is_aim_ready: bool = false

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

func release_to_ai() -> void:
	if is_player_controlled:
		is_player_controlled = false
		attack_target = null
		print("[Turret:%s] Paluu AI-hallintaan" % name)


func _process_ai(delta: float) -> void:
	var effective_target = attack_target
	
	# Pelaaja voi ottaa kontrollin oikealla hiirella JOS hän hallitsee laivaa
	if Input.is_action_just_pressed("aim_target"):
		print("[Turret:%s] Pelaaja yritti kontrollin" % name)
		var ship = get_parent()
		if ship and ship == UnitManager.controlled_unit and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			is_player_controlled = true
			print("[Turret:%s] Pelaaja otti kontrollin" % name)
	
	# Validoi target (ei kuollut, ei uppoava)
	if is_instance_valid(effective_target) and "team_id" in effective_target:
		if effective_target.team_id == 0:
			effective_target = null
			attack_target = null
	
	# Jos maalia ei ole, ei tehdä mitään
	if not is_instance_valid(effective_target):
		_return_to_rest(delta)
		return

	# Tähdätään kohteeseen
	var aim_pos = _get_predicted_aim_position(effective_target)
	_rotate_towards(aim_pos, delta)
	
	# AI-ampuminen
	if is_aim_ready:
		fire_muzzle()

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

# laiva kutsuu tätä kun se saa uuden targetin
func set_turret_target(target: Node3D) -> void:
	if is_instance_valid(target):
		attack_target = target
		is_player_controlled = false
		print("[Turret:%s] Laiva antoi targetin: %s" % [name, target.name])
	else:
		attack_target = null


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
		ray_origin + ray_dir * 5000.0
	)
	query.collision_mask = 8  # layer 3 (maa/meri)

	var result = space.intersect_ray(query)
	if result:
		return result.position
	else:
		return ray_origin + ray_dir * 1000.0


func _rotate_towards(target_pos: Vector3, delta: float) -> void:
	var diff = target_pos - gun.global_transform.origin
	var ship = get_parent()
	
	# --- 1. LASKETAAN ALKUPERÄINEN TAVOITE ---
	# Tallennetaan mihin pelaaja/AI HALUAISI tähdätä (radiaaneina)
	var true_desired_yaw = atan2(-diff.x, -diff.z)
	
	# Luodaan muuttuja liikkumista varten (tätä muokataan, jos kohde on kielletty)
	var move_target_yaw = true_desired_yaw
	
	# --- 2. KIELLETYT VYÖHYKKEET (Paikallinen tarkistus asteina) ---
	# Lasketaan kohteen kulma suhteessa laivan keulaan (-180...180)
	var local_target_angle = wrapf(rad_to_deg(true_desired_yaw - ship.global_rotation.y), -180.0, 180.0)
	
	# Määritetään kielletty keskiö: Etutykille perä (180), Takatykille keula (0)
	var forbidden_center = 180.0 if is_front else 0.0
	var half_width = forbidden_width / 2.0
	
	# Lasketaan kuinka kaukana kohde on kielletyn alueen keskipisteestä
	var dist_to_forbidden = wrapf(local_target_angle - forbidden_center, -180.0, 180.0)
	
	var target_is_blocked = false
	if abs(dist_to_forbidden) < half_width:
		# Kohde ON kielletyllä alueella!
		target_is_blocked = true
		
		# Pakotetaan paikallinen tavoitekulma lähimmälle sallitulle reunalle
		var sign_dir = 1.0 if dist_to_forbidden > 0 else -1.0
		var limited_local = wrapf(forbidden_center + (half_width * sign_dir), -180.0, 180.0)
		
		# Päivitetään liikkumiseen käytettävä yaw vastaamaan tätä rajoitettua kulmaa
		move_target_yaw = ship.global_rotation.y + deg_to_rad(limited_local)
		# Päivitetään myös kääntymislogiikkaa varten käytettävä lta_rad
		local_target_angle = limited_local

	# --- 3. KÄÄNTYMISLOGIIKKA (Lyhin reitti vs. rungon läpi kiertäminen) ---
	# Lasketaan ero tykin nykyisen kulman ja (rajoitetun) tavoitteen välillä
	var yaw_diff = wrapf(move_target_yaw - global_rotation.y, -PI, PI)
	
	var local_turret_angle = wrapf(global_rotation.y - ship.global_rotation.y, -PI, PI)
	var lta_rad = deg_to_rad(local_target_angle)
	
	if is_front:
		# Etutykki: jos matka tavoitteeseen ylittää 180 astetta, se yrittäisi kääntyä perän läpi.
		# Pakotetaan kierto toiseen suuntaan.
		if abs(lta_rad - local_turret_angle) > PI:
			yaw_diff = -sign(yaw_diff) * (2.0 * PI - abs(yaw_diff))
	else:
		# Takatykki: jos tykki ja kohde ovat eri puolilla laivaa ja keulan ylitys on lyhyempi reitti.
		# Pakotetaan kierto perän kautta.
		if (lta_rad * local_turret_angle) < 0:
			if abs(lta_rad - local_turret_angle) < PI:
				yaw_diff = -sign(yaw_diff) * (2.0 * PI - abs(yaw_diff))
	
	# --- 4. TOTEUTETAAN KÄÄNTYMINEN (YAW) ---
	var step = deg_to_rad(yaw_speed * delta)
	global_rotation.y += clamp(yaw_diff, -step, step)
	
	# --- 5. PITCH (Pystysuunta) ---
	var horiz_dist = Vector2(diff.x, diff.z).length()
	var target_pitch = _calc_ballistic_pitch(horiz_dist, diff.y)
	
	# Jos kohde on kielletyllä alueella tai tykki on rajoitettu, lasketaan piippu 0-asentoon
	if target_is_blocked:
		target_pitch = 0.0
	
	var p_diff = target_pitch - gun.rotation.x
	var p_step = deg_to_rad(pitch_speed * delta)
	gun.rotation.x += clamp(p_diff, -p_step, p_step)
	
	# Rajoitetaan piippu kaliiperiasetusten mukaan
	gun.rotation.x = clamp(gun.rotation.x, deg_to_rad(current_down_max), deg_to_rad(current_up_max))
	
	# --- 6. VALMIUSTARKISTUS (Voiko ampua?) ---
	# Verrataan tykin nykyistä kulmaa TODELLISEEN tavoitteeseen (missä hiiri/target on)
	var final_error = abs(rad_to_deg(wrapf(true_desired_yaw - global_rotation.y, -PI, PI)))
	
	# Tykki saa ampua vain jos:
	# - Kohde ei ole kielletyllä vyöhykkeellä
	# - Tykki on kääntynyt alle 2 asteen päähän todellisesta kohteesta
	is_aim_ready = (not target_is_blocked) and (final_error < 2.0)


func _calc_ballistic_pitch(x: float, y: float) -> float:
	var v = projectile_speed
	var g = gravity
	
	if x <= 0.001:
		return 0.0
	
	var v2 = v * v
	
	var root = v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	
	if root < 0.0:
		return 0.0  # ei kantamaa
	
	var sqrt_root = sqrt(root)
	
	# MATALA KAARI
	var angle = atan2(v2 - sqrt_root, g * x)
	
	return angle

func _get_predicted_aim_position(target: Node3D) -> Vector3:
	var predicted_pos = target.global_position
	
	# 1. Haetaan kohteen nopeus ja kääntymisnopeus turvallisesti
	var t_speed: float = target.get("current_speed") if "current_speed" in target else 0.0
	
	var t_turn_rate: float = 0.0
	# Lasketaan kääntymisnopeus (rad/s). Oletetaan, että laiva kääntyy: steering * turn_speed
	if "current_steering_output" in target and "turn_speed" in target:
		t_turn_rate = target.current_steering_output * target.turn_speed
	elif "sync_steering_index" in target and "steering_levels" in target and "turn_speed" in target:
		# Fallback, jos current_steering_output ei ole ehtinyt päivittyä
		var steer_idx = target.sync_steering_index
		t_turn_rate = target.steering_levels[steer_idx] * target.turn_speed
		
	var tof := 0.0
	
	# 2. Iteroidaan 3 kertaa tarkemman osumapisteen löytämiseksi
	for iteration in 3:
		var diff = predicted_pos - gun.global_transform.origin
		var horiz_dist = Vector2(diff.x, diff.z).length()
		
		# Haetaan arvioitu lentoaika nykyiseen ennakkopisteeseen
		tof = _estimate_flight_time(horiz_dist, diff.y)
		
		# 3. Simuloidaan kohteen liike lentoajan yli (XZ-taso)
		predicted_pos = target.global_position
		var sim_yaw = target.global_rotation.y
		
		# Jaetaan simulointi askeleisiin (esim. 10), jotta kaarrostarkkuus pysyy hyvänä
		var steps = 10
		var dt = tof / float(steps)
		
		for i in steps:
			sim_yaw += t_turn_rate * dt
			# Oletetaan, että laivan keula on Godotin -Z suunta (Vector3.FORWARD)
			var forward = Vector3.FORWARD.rotated(Vector3.UP, sim_yaw)
			predicted_pos += forward * t_speed * dt
			
	return predicted_pos

func _estimate_flight_time(x: float, y: float) -> float:
	# Käytetään olemassa olevaa funktiotasi pitchin hakuun
	var pitch = _calc_ballistic_pitch(x, y)
	
	if x <= 0.001:
		return 0.0
		
	# Ammuksen vaakanopeus: v_x = v * cos(pitch)
	var v_xz = projectile_speed * cos(pitch)
	
	if v_xz == 0.0:
		return 0.0
		
	# Lentoaika = matka / vaakanopeus
	return x / v_xz



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
	if !is_aim_ready: return
	var shooter_id = owner.get_multiplayer_authority()
	for muzzle in muzzles:
		if muzzle.turret_control and muzzle.gun_index != -1:
			var permission = muzzle.turret_control.fire_permissions[muzzle.gun_index]
			if permission == 1 and muzzle.has_method("action_fire"):
				muzzle.action_fire(shooter_id)
		elif muzzle.has_method("action_fire"):
			muzzle.action_fire(shooter_id)


func _return_to_rest(delta: float) -> void:
	var ship = get_parent()
	if not ship:
		return
	
	# Tavoite: rest_yaw asteen suhteessa laivaan
	var target_yaw = ship.global_rotation.y + deg_to_rad(rest_yaw)
	
	# Kääntyminen lepoasentoon
	var yaw_diff = wrapf(target_yaw - global_rotation.y, -PI, PI)
	var step = deg_to_rad(yaw_speed * delta)
	global_rotation.y += clamp(yaw_diff, -step, step)
	
	# Piippu nollaan
	var p_diff = 0.0 - gun.rotation.x
	var p_step = deg_to_rad(pitch_speed * delta)
	gun.rotation.x += clamp(p_diff, -p_step, p_step)
