#ship
extends CharacterBody3D # Käytetään CharacterBodya, se on vakaampi multiplayerissä

#auktoriteetin vaihtoa varten
var authority_cooldown := 0.0



@export_group("Camera Settings")
@export var cam_mode_fixed: bool = false
@export var cam_offset := Vector3(0, 70, 0)
@export var cam_min_dist := 10.0
@export var cam_max_dist := 150.0
@export_group("") # Tämä tyhjä merkkijono "sulkee" edellisen ryhmän

@onready var hud: Control = $HUD/ShipHUD

# --- SYNC-MUUTTUJAT ---
# Nämä muuttujat lisätään MultiplayerSynchronizeriin
@export var sync_steering_index := 3  # 0...6 (3 on suoraan)
@export var sync_speed_index := 2      # 0 ... 5
@export var is_player_controlled := false
@export var team_id: int = 0

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

var steering_levels = [
	1.0,   # Hard Port (0)
	0.6,   # Half Port (1)
	0.3,   # Small Port (2)
	0.0,   # MIDSHIPS / Neutral (3)
	-0.3,  # Small Starboard (4)
	-0.6,  # Half Starboard (5)
	-1.0   # Hard Starboard (6)
]
var rudder_speed := 0.3
var current_steering_output := 0.0
var turn_speed := 0.3
var steer_repeat_timer := 0.0
var repeat_delay := 0.5


var acceleration := 5.0
var current_speed := 0.0

var is_sinking := false

# --- AI-MUUTTUJAT ---
var ai_target_pos = null # Käytetään nullia oletuksena (Variant-tyyppi)
var follow_target: Node3D = null
var attack_target: Node3D = null # UUSI: Kohde jota kohti hyökätään
var formation_offset := Vector3.ZERO # Paikka suhteessa johtajaan
@export var formation_grid_size := 40.0 # Etäisyys "yksiköiden" välillä


func _ready():
	if hud:
		hud.visible = false

func _physics_process(delta: float) -> void:
	if is_sinking:
		global_position.y -= 5.0 * delta
		rotation.z += 0.05 * delta 
		return

	if is_multiplayer_authority():
		# Luetaan pelaajan näppäimet AINA (se haistelee keskeytystä)
		_read_player_input()
		
		# Jos pelaaja ei ole vielä koskenut ohjaimiin, ajetaan AI
		if not is_player_controlled:
			_run_ai_logic()
		
		_apply_movement(delta)

func _on_authority_changed(_new_auth: int): # Lisätty alaviiva (_) varoituksen poistamiseksi
	authority_cooldown = 0.2
	# PAKOTETAAN synchronizer seuraamaan uutta auktoriteettia
	var sync = get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_multiplayer_authority(_new_auth)


func set_hud_active(active: bool):
	if hud:
		hud.visible = active

func _read_player_input() -> void:
	# 1. Jos en ole auktoriteetti, en missään nimessä koske muuttujiin
	if not is_multiplayer_authority():
		return
		
	# 2. Jos olen vasta saanut hallinnan, odotan cooldownin loppuun
	if authority_cooldown > 0:
		return

	if UnitManager.controlled_unit != self:
		return
	
	# Vain auktoriteetti saa suorittaa input-logiikan loppuun asti
	# koska muuttujat ovat synkronoituja!
	if not is_multiplayer_authority():
		return


	var throttle_up = Input.is_action_just_pressed("forward")
	var throttle_down = Input.is_action_just_pressed("backward")
	
	# Tarkistetaan A ja D syötteet
	var steer_input = Input.get_axis("right", "left") # A positiivinen, D negatiivinen
	
	# 1. NOPEUDEN OHJAUS (Kuten ennenkin)
	if throttle_up or throttle_down:
		if not is_multiplayer_authority():
			print("!!! VAROITUS: Client yrittää muuttaa nopeutta ilman auktoriteettia!")
		else:
			is_player_controlled = true
			if throttle_up: sync_speed_index = clampi(sync_speed_index + 1, 0, 6)
			if throttle_down: sync_speed_index = clampi(sync_speed_index - 1, 0, 6)

	# 2. PERÄSIMEN OHJAUS (Uusi portaittainen logiikka)
	if steer_input != 0:
		is_player_controlled = true
		
		# Jos nappi juuri painettiin alas
		if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
			_change_steering(steer_input)
			steer_repeat_timer = 0.0 # Nollataan viive
		else:
			# Nappia pidetään pohjassa
			steer_repeat_timer += get_process_delta_time()
			if steer_repeat_timer >= repeat_delay:
				_change_steering(steer_input)
				steer_repeat_timer = 0.0 # Nollataan seuraavaa askelta varten
	else:
		steer_repeat_timer = 0.0


func _change_steering(direction: float):
	# DEBUG: Tarkistetaan onko meillä oikeus muuttaa tätä
	if not is_multiplayer_authority():
		print("!!! VAROITUS: Client yrittää muuttaa ohjausta ilman auktoriteettia!")
		return

	if direction > 0: # Vasen (A)
		sync_steering_index = clampi(sync_steering_index - 1, 0, 6)
	elif direction < 0: # Oikea (D)
		sync_steering_index = clampi(sync_steering_index + 1, 0, 6)


func _run_ai_logic() -> void:
	# 1. HYÖKKÄYS (Korkein prioriteetti)
	if is_instance_valid(attack_target):
		attack_ship()

	# 2. SEURANTA
	if is_instance_valid(follow_target):
		var rotated_offset = follow_target.global_transform.basis * formation_offset
		var leader_target_pos = follow_target.global_position + rotated_offset
		_drive_towards(leader_target_pos)
		return

	# 3. PISTEESEEN AJAMINEN
	if ai_target_pos != null:
		var dist_to_target = global_position.distance_to(ai_target_pos)
		if dist_to_target < 25.0:
			ai_target_pos = null
			sync_speed_index = 2 # STOP
			sync_steering_index = 3 # MIDSHIPS
		else:
			_drive_towards(ai_target_pos)
	else:
		sync_steering_index = 3

# Apufunktio ohjaamiseen
func _drive_towards(target: Vector3):
	var to_target = global_position.direction_to(target)
	var forward = -global_transform.basis.z
	var angle_to = forward.signed_angle_to(to_target, Vector3.UP)

	# AI käyttää maksimikääntöä jos kulma on suuri
	if angle_to > 0.1:
		sync_steering_index = 0 # Hard Port
	elif angle_to < -0.1:
		sync_steering_index = 6 # Hard Starboard
	else:
		sync_steering_index = 3 # Midships
	
	sync_speed_index = 4 # 1/2 Ahead


func set_ai_target(pos: Vector3):
	ai_target_pos = pos
	follow_target = null
	attack_target = null
	# Tämä on tärkeää: Kun uusi kohde asetetaan, laiva siirtyy AI-tilaan
	is_player_controlled = false 
	
	if is_multiplayer_authority():
		sync_speed_index = 4 # Asetetaan vauhtia


func set_attack_target(target: Node3D):
	attack_target = target
	follow_target = null
	ai_target_pos = null
	is_player_controlled = false


func set_follow_target(target: Node3D):
	
	# Nollataan muut tilat, jotta uusi käsky menee läpi
	ai_target_pos = null
	attack_target = null
	
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
	var y_val = 2 * ceil(float(n) / 2.0) # Negatiivinen, koska se on johtajan takana
	
	# Asetetaan lopullinen offset metreinä
	formation_offset = Vector3(x_sign, 0, y_val) * formation_grid_size


# Apufunktio seuraajien laskemiseen
func _get_followers_of(leader: Node3D) -> Array:
	var list = []
	var units = get_parent().get_children() # Oletetaan että laivat ovat samassa nodessa
	for u in units:
		if u.get("follow_target") == leader:
			list.append(u)
	return list


func _apply_movement(delta: float) -> void:
	# 1. NOPEUS
	var target_speed = speed_levels[sync_speed_index]
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	
	# 2. PERÄSIMEN LOGIIKKA
	var target_rudder_pos = steering_levels[sync_steering_index]
	
	if is_player_controlled:
		# Pelaajalla peräsin liikkuu hitaasti (alkuperäinen logiikka)
		current_steering_output = move_toward(
			current_steering_output, 
			target_rudder_pos, 
			rudder_speed * delta
		)
	else:
		# AI:lla peräsin hyppää heti tavoitteeseen (ei aaltoilua)
		current_steering_output = target_rudder_pos
	
	# 3. KÄÄNTYMINEN JA LIIKE
	if abs(current_speed) > 0.1:
		var rotation_dir = current_steering_output
		# Jos peruutetaan, kääntö on käänteinen
		if current_speed < 0: rotation_dir *= -1
		rotate_y(rotation_dir * turn_speed * delta)
	
	# Liike
	velocity = -global_transform.basis.z * current_speed
	move_and_slide()


func attack_ship() -> void:
	if not is_instance_valid(attack_target):
		return
	
	var target_pos = attack_target.global_position
	var dist = global_position.distance_to(target_pos)
	var to_target = global_position.direction_to(target_pos)
	
	# --- 1. ETÄISYYDEN HALLINTA ---
	if dist > 700.0:
		# Liian kaukana -> Aja suoraan kohti
		_drive_towards(target_pos)
		sync_speed_index = 6 # Full Ahead
	
	elif dist < 450.0:
		# Liian lähellä -> Käänny poispäin tai peruuta
		var escape_pos = global_position - to_target * 100.0
		_drive_towards(escape_pos)
		sync_speed_index = 3 # Slow
		
	else:
		# --- 2. KYLKI KOHTI (BROADSIDE) ---
		# Lasketaan tangenttipiste vihollisen ympäriltä
		# Vector3.UP on normaali, jonka ympäri pyöräytetään 90 astetta
		var side_direction = to_target.cross(Vector3.UP).normalized()
		
		# Valitaan kumpi kylki on jo valmiiksi lähempänä vihollista
		var forward = -global_transform.basis.z
		if forward.dot(side_direction) < 0:
			side_direction = -side_direction
			
		# Kohdepiste on tangentin suunnassa
		var broadside_target = global_position + side_direction * 100.0
		
		_drive_towards(broadside_target)
		
		# Säädetään nopeutta etäisyyden mukaan optimaalisella alueella
		if dist > 600.0:
			sync_speed_index = 4 # 1/2 Ahead
		else:
			sync_speed_index = 3 # 1/4 Ahead


func start_sinking():
	if is_sinking: return # Estetään moninkertainen kutsu
	is_sinking = true
	# Jos tämä oli pelaajan hallitsema laiva, vapautetaan kamera
	if UnitManager.controlled_unit == self:
		UnitManager.controlled_unit = null 
		# Tässä kohtaa kannattaa piilottaa HUD
		set_hud_active(false)


func set_team(id: int):
	team_id = id

func get_icon_color() -> Color: #karttoja varten
	if team_id == multiplayer.get_unique_id(): return Color.CYAN
	return Color.GOLDENROD
