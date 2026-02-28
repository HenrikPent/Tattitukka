#ship
extends CharacterBody3D # Käytetään CharacterBodya, se on vakaampi multiplayerissä

#auktoriteetin vaihtoa varten
var authority_cooldown := 0.0
var _last_authority := 1


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
@export var follow_distance := 60.0 # Kuinka kaukana pysytään
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
	print(name, " hallinta vaihtui -> ", _new_auth)


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
			print(name, " Nopeus muutettu: ", sync_speed_index)

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

	var old_index = sync_steering_index
	if direction > 0: # Vasen (A)
		sync_steering_index = clampi(sync_steering_index - 1, 0, 6)
	elif direction < 0: # Oikea (D)
		sync_steering_index = clampi(sync_steering_index + 1, 0, 6)
	
	if old_index != sync_steering_index:
		print(name, " Ohjaus muutettu: ", sync_steering_index, " (Auktoriteetti: ", is_multiplayer_authority(), ")")


func _run_ai_logic() -> void:
	# 1. SEURANTA (Johtajan seuraaminen menee pisteen edelle)
	if is_instance_valid(follow_target):
		var rotated_offset = follow_target.global_transform.basis * formation_offset
		var leader_target_pos = follow_target.global_position + rotated_offset
		
		# Ohjataan kohti johtajan paikkaa
		_drive_towards(leader_target_pos)
		return

	# 2. PISTEESEEN AJAMINEN
	if ai_target_pos != null:
		var dist_to_target = global_position.distance_to(ai_target_pos)
		
		# Jos ollaan perillä (25m säteellä)
		if dist_to_target < 25.0:
			#print(name, " saavutti kohteensa ja pysähtyy.")
			ai_target_pos = null # NOLLAUS: Ei enää kohdetta
			sync_speed_index = 2 # STOP
			sync_steering_index = 3
		else:
			# Jos matkaa on vielä, ajetaan
			_drive_towards(ai_target_pos)
	else:
		# 3. EI KOHDETTA: Varmistetaan että laiva ei jää kääntymään ikuisesti
		# Jos haluat että laiva vain rullaa pysähdyksiin, kun kohde poistuu:
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


@rpc("any_peer", "call_local", "reliable")
func set_ai_target(pos: Vector3):
	ai_target_pos = pos
	follow_target = null
	# Tämä on tärkeää: Kun uusi kohde asetetaan, laiva siirtyy AI-tilaan
	is_player_controlled = false 
	
	if is_multiplayer_authority():
		sync_speed_index = 4 # Asetetaan vauhtia

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
	# 1. NOPEUS (Kuten ennenkin)
	var target_speed = speed_levels[sync_speed_index]
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	
	# 2. PERÄSIMEN SMOOTH LIIKE
	# Haetaan tavoitekulma valitun indeksin perusteella
	var target_rudder_pos = steering_levels[sync_steering_index]
	
	# Siirretään peräsintä kohti tavoitetta vakionopeudella
	current_steering_output = move_toward(
		current_steering_output, 
		target_rudder_pos, 
		rudder_speed * delta
	)
	
	# 3. KÄÄNTYMINEN JA LIIKE
	if abs(current_speed) > 0.1:
		# Käytetään nyt tasoitettua outputia kääntymiseen
		var rotation_dir = current_steering_output
		if current_speed < 0: rotation_dir *= -1
		rotate_y(rotation_dir * turn_speed * delta)
	
	# Liike
	velocity = -global_transform.basis.z * current_speed
	move_and_slide()

func start_sinking():
	is_sinking = true


func set_team(id: int):
	team_id = id

func get_icon_color() -> Color: #karttoja varten
	if team_id == multiplayer.get_unique_id(): return Color.CYAN
	return Color.GOLDENROD
