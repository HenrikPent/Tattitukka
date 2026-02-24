extends CharacterBody3D # Käytetään CharacterBodya, se on vakaampi multiplayerissä

@export var team_id: int = 0

@export_group("Camera Settings")
@export var cam_mode_fixed: bool = false
@export var cam_offset := Vector3(0, 70, 0)
@export var cam_min_dist := 10.0
@export var cam_max_dist := 150.0
@export_group("") # Tämä tyhjä merkkijono "sulkee" edellisen ryhmän


# --- SYNC-MUUTTUJAT ---
# Nämä muuttujat lisätään MultiplayerSynchronizeriin
@export var sync_steering := 0.0      # -1.0 ... 1.0
@export var sync_speed_index := 2      # 0 ... 5
@export var is_player_controlled := false


# --- FYSIIKKA-ASETUKSET ---
# Esimerkki: 7 porrasta (0-6)
var speed_levels = [
	-20.0, # Full Reverse (0)
	-10.0,  # Half Reverse (1)
	0.0,   # STOP (2)
	10.0,  # 1/4 Ahead (3)
	20.0,  # 1/2 Ahead (4)
	30.0,  # 3/4 Ahead (5)
	40.0   # FULL AHEAD (6)
]
var acceleration := 5.0
var turn_speed := 0.5
var current_speed := 0.0


# --- AI-MUUTTUJAT ---
var ai_target_pos := Vector3.ZERO
var follow_target: Node3D = null
@export var follow_distance := 60.0 # Kuinka kaukana pysytään
var formation_offset := Vector3.ZERO # Paikka suhteessa johtajaan
@export var formation_grid_size := 40.0 # Etäisyys "yksiköiden" välillä

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		# Luetaan pelaajan näppäimet AINA (se haistelee keskeytystä)
		_read_player_input()
		
		# Jos pelaaja ei ole vielä koskenut ohjaimiin, ajetaan AI
		if not is_player_controlled:
			_run_ai_logic()
		
		_apply_movement(delta)

func _read_player_input() -> void:
	# --- TÄMÄ ON TÄRKEIN LISÄYS ---
	# Tarkistetaan, onko tämä nimenomaan se laiva, jonka PlayerManager sanoo olevan hallinnassa
	if PlayerManager.controlled_unit != self:
		return

	var steering_input = Input.get_axis("right", "left")
	var throttle_up = Input.is_action_just_pressed("forward")
	var throttle_down = Input.is_action_just_pressed("backward")

	# Jos pelaaja tekee jotain, otetaan täysi kontrolli (AI pois)
	if steering_input != 0 or throttle_up or throttle_down:
		if not is_player_controlled:
			is_player_controlled = true
			follow_target = null
			print(name, " ohjaus otettu pelaajalle (AI deaktivoitu).")

	# Suoritetaan ohjaus vain jos ollaan pelaaja-ohjauksessa
	if is_player_controlled:
		sync_steering = steering_input
		if throttle_up:
			sync_speed_index = clampi(sync_speed_index + 1, 0, 6)
		if throttle_down:
			sync_speed_index = clampi(sync_speed_index - 1, 0, 6)

func _run_ai_logic() -> void:
	# 1. PÄIVITYS: Jos meillä on seurattava kohde, päivitetään maali sen sijainnin mukaan
	if is_instance_valid(follow_target):
		# OPTIO: Jos johtajamme alkaakin itse seurata jotain uutta, 
		# me voimme hypätä suoraan uuden johtajan perään
		if is_instance_valid(follow_target.get("follow_target")):
			follow_target = follow_target.follow_target
			return # Päivitetään positio seuraavassa framessa uuden kohteen mukaan

		# Päivitetään kohde johtajan mukaan + huomioidaan johtajan suunta (rotaatio)
		# Tällöin "vasen puoli" pysyy vasempana, vaikka johtaja kääntyy
		var rotated_offset = follow_target.global_transform.basis * formation_offset
		ai_target_pos = follow_target.global_position + rotated_offset
		sync_speed_index = 4
	
	# 2. ETÄISYYSTARKISTUS: Jos ollaan jo perillä kohteessa, pysähdytään ja unohdetaan kohde
	var dist_to_target = global_position.distance_to(ai_target_pos)
	if dist_to_target < 25.0: 
		sync_speed_index = 2 # Asetetaan nollavauhti (speed_levels[2] on 0.0)
		sync_steering = 0
		
		# TÄMÄ LISÄYS:
		if not is_instance_valid(follow_target):
			# Jos emme seuraa ketään (eli olimme matkalla vain pisteeseen), nollataan kohde
			ai_target_pos = Vector3.ZERO
			
			
		return

	# 3. OHJAUSLOGIIKKA (pidetään ennallaan, se toimi hyvin)
	var to_target = global_position.direction_to(ai_target_pos)
	var forward = -global_transform.basis.z
	var angle_to = forward.signed_angle_to(to_target, Vector3.UP)

	if abs(angle_to) > 0.1:
		sync_steering = clamp(angle_to * 2.0, -1.0, 1.0)
	else:
		sync_steering = 0.0


func set_ai_target(pos: Vector3):
	ai_target_pos = pos
	sync_speed_index = 4 
	is_player_controlled = false # Palautetaan AI-tilaan, kun uusi käsky annetaan

func set_follow_target(target: Node3D):
	# 1. Etsitään lopullinen johtaja
	var final_leader = target
	var max_depth = 5
	while is_instance_valid(final_leader.get("follow_target")) and max_depth > 0:
		final_leader = final_leader.follow_target
		max_depth -= 1
	
	follow_target = final_leader
	is_player_controlled = false
	
	# 2. Lasketaan monesko seuraaja ollaan (n)
	var followers = _get_followers_of(final_leader)
	var n = followers.size() # Jos olet ensimmäinen, n = 1 (koska olet jo listalla)
	
	# 3. Lasketaan offset kaavasi mukaan:
	# Pariton x = 1, Parillinen x = -1
	var x_sign = 1 if (n % 2 != 0) else -1
	
	# y = n/2 pyöristettynä ylös
	var y_val = ceil(float(n) / 2.0) # Negatiivinen, koska se on johtajan takana
	
	# Asetetaan lopullinen offset metreinä
	formation_offset = Vector3(x_sign, 0, y_val) * formation_grid_size
	
	print(name, " liittyi muodostelmaan paikalle ", n, " offsetilla: ", formation_offset)

# Apufunktio seuraajien laskemiseen
func _get_followers_of(leader: Node3D) -> Array:
	var list = []
	var units = get_parent().get_children() # Oletetaan että laivat ovat samassa nodessa
	for u in units:
		if u.get("follow_target") == leader:
			list.append(u)
	return list

func _apply_movement(delta: float) -> void:
	# Lasketaan nopeus
	var target_speed = speed_levels[sync_speed_index]
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	
	# Kääntyminen (vain jos liikutaan)
	if abs(current_speed) > 0.1:
		var rotation_dir = sync_steering
		if current_speed < 0: rotation_dir *= -1
		rotate_y(rotation_dir * turn_speed * delta)
	
	# Liike
	velocity = -global_transform.basis.z * current_speed
	move_and_slide() # Käytetään tätä, jotta törmäykset saariin toimivat

func set_team(id: int):
	team_id = id

func get_icon_color() -> Color: #karttoja varten
	if team_id == multiplayer.get_unique_id(): return Color.CYAN
	return Color.GOLDENROD
