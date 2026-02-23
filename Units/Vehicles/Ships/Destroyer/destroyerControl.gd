
#Destroyer.gd
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
var speed_levels = [-18.0, -8.0, 0.0, 10.0, 20.0, 38.0]
var acceleration := 5.0
var turn_speed := 0.5
var current_speed := 0.0


# --- AI-MUUTTUJAT ---
var ai_target_pos := Vector3.ZERO
var follow_target: Node3D = null
@export var follow_distance := 60.0 # Kuinka kaukana pysytään

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
			sync_speed_index = clampi(sync_speed_index + 1, 0, 5)
		if throttle_down:
			sync_speed_index = clampi(sync_speed_index - 1, 0, 5)

func _run_ai_logic() -> void:
	# 1. PÄIVITYS: Jos meillä on seurattava kohde, päivitetään maali sen sijainnin mukaan
	if is_instance_valid(follow_target):
		# OPTIO: Jos johtajamme alkaakin itse seurata jotain uutta, 
		# me voimme hypätä suoraan uuden johtajan perään
		if is_instance_valid(follow_target.get("follow_target")):
			follow_target = follow_target.follow_target
			return # Päivitetään positio seuraavassa framessa uuden kohteen mukaan

		# Pysytään seurattavan takana (tässä voit myöhemmin käyttää niitä offsetteja)
		var offset = follow_target.global_transform.basis.z * follow_distance
		ai_target_pos = follow_target.global_position + offset
		sync_speed_index = 4
	
	# 2. ETÄISYYSTARKISTUS: Jos ollaan jo perillä kohteessa, pysähdytään
	var dist_to_target = global_position.distance_to(ai_target_pos)
	if dist_to_target < 25.0: # 25 metriä on "perillä"
		sync_speed_index = 0
		sync_steering = 0
		return # Ei tarvitse ohjata enempää

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
	var final_leader = target
	
	# Tarkistetaan, seuraako kohde itse jotakuta
	# Käydään ketjua läpi niin kauan kunnes löytyy laiva, jolla ei ole follow_targetia
	# (Lisätään max_depth varmuuden vuoksi, ettei peli jää ikuiseen looppiin)
	var max_depth = 5
	while is_instance_valid(final_leader.get("follow_target")) and max_depth > 0:
		final_leader = final_leader.follow_target
		max_depth -= 1
	
	follow_target = final_leader
	is_player_controlled = false # Palautetaan AI-tilaan
	
	print(name, " muodostelma: asetettu seuraamaan johtajaa ", final_leader.name)

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
