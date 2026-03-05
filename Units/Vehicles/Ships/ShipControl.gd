#ship
extends CharacterBody3D # Käytetään CharacterBodya, se on vakaampi multiplayerissä

#auktoriteetin vaihtoa varten
var authority_cooldown := 0.0

@export_group("Camera Settings")
@export var cam_mode_fixed: bool = false
@export var cam_offset := Vector3(0, 70, 0)
@export var cam_near := 100.0
@export var cam_far := 200.0
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
var current_sink_speed := 0.0

# --- AI-MUUTTUJAT ---
enum AIState { IDLE, ATTACK, FOLLOW, NAVIGATE }
var current_ai_state: AIState = AIState.IDLE
var previous_ai_state: AIState = AIState.IDLE
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
		_apply_sinking(delta)
		# Jatka liikkumista (hidastuu kohti nollaa tai pysyy ohjattuna AI:lla hetken)
		_apply_movement(delta)
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

func release_turrets_to_ai() -> void:
	for child in get_children():
		if child.has_method("release_to_ai"):
			child.release_to_ai()
	print("[Ship:%s] Tykit palautettu AI-hallintaan" % name)


func set_hud_active(active: bool):
	if hud:
		hud.visible = active

func _read_player_input() -> void:
	if not is_multiplayer_authority() or authority_cooldown > 0:
		return

	if UnitManager.controlled_unit != self:
		return

	# Tarkistetaan, painaako pelaaja jotain ohjausnäppäintä TÄLLÄ HETKELLÄ
	var throttle_up = Input.is_action_just_pressed("forward")
	var throttle_down = Input.is_action_just_pressed("backward")
	var steer_left = Input.is_action_pressed("left")
	var steer_right = Input.is_action_pressed("right")
	var steer_input = Input.get_axis("right", "left")

	# OTETAAN HALLINTA VAIN JOS PELAAJA SYÖTTÄÄ JOTAIN
	# (Huom: Ammuntanapit tai kamera eivät triggeröi tätä, koska ne eivät muuta liiketilaa)
	if throttle_up or throttle_down or steer_left or steer_right:
		if not is_player_controlled:
			is_player_controlled = true
			print("[Ship] Pelaaja otti manuaaliohjauksen: ", name)

	# Suoritetaan ohjauslogiikka vain jos ollaan pelaaja-moodissa
	if is_player_controlled:
		# 1. NOPEUDEN OHJAUS
		if throttle_up: sync_speed_index = clampi(sync_speed_index + 1, 0, 6)
		if throttle_down: sync_speed_index = clampi(sync_speed_index - 1, 0, 6)

		# 2. PERÄSIMEN OHJAUS
		if steer_input != 0:
			if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
				_change_steering(steer_input)
				steer_repeat_timer = 0.0
			else:
				steer_repeat_timer += get_process_delta_time()
				if steer_repeat_timer >= repeat_delay:
					_change_steering(steer_input)
					steer_repeat_timer = 0.0
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
	# Tarkistetaan prioriteetti ja vaihdetaan tila tarvittaessa
	if is_instance_valid(attack_target) and attack_target.team_id != 0:
		current_ai_state = AIState.ATTACK
	elif is_instance_valid(follow_target):
		current_ai_state = AIState.FOLLOW
	elif ai_target_pos != null:
		current_ai_state = AIState.NAVIGATE
	else:
		current_ai_state = AIState.IDLE
	
	# Jos tila muuttui ATTACK:sta pois, vapaa tykit
	if previous_ai_state == AIState.ATTACK and current_ai_state != AIState.ATTACK:
		clear_turrets_target()
	
	previous_ai_state = current_ai_state
	
	# Suorita tila
	match current_ai_state:
		AIState.IDLE:
			_ai_idle()
		AIState.ATTACK:
			_ai_attack()
		AIState.FOLLOW:
			_ai_follow()
		AIState.NAVIGATE:
			_ai_navigate()


func _ai_idle() -> void:
	sync_steering_index = 3 # MIDSHIPS
	sync_speed_index = 2    # STOP

func _ai_attack() -> void:
	attack_ship()

func _ai_follow() -> void:
	var rotated_offset = follow_target.global_transform.basis * formation_offset
	var leader_target_pos = follow_target.global_position + rotated_offset
	var dist_to_formation_spot = global_position.distance_to(leader_target_pos)
	
	var leader_is_stopped = follow_target.get("sync_speed_index") == 2
	
	if leader_is_stopped and dist_to_formation_spot < 100.0:
		sync_speed_index = 2
		sync_steering_index = 3
	else:
		_drive_towards(leader_target_pos)

func _ai_navigate() -> void:
	var dist_to_target = global_position.distance_to(ai_target_pos)
	if dist_to_target < 100.0:
		ai_target_pos = null
		sync_speed_index = 2
		sync_steering_index = 3
	else:
		_drive_towards(ai_target_pos)

# Apufunktio ohjaamiseen (Päivitetty peruutuslogiikalla)
func _drive_towards(target: Vector3):
	var dist = global_position.distance_to(target)
	var to_target = global_position.direction_to(target)
	var forward = -global_transform.basis.z
	
	# Kulma kohteeseen (-PI ... PI)
	var angle_to = forward.signed_angle_to(to_target, Vector3.UP)
	
	# --- PERUUTUSLOGIIKKA ---
	# Jos kohde on takana (kulma > 90 astetta molemmin puolin) 
	# JA kohde on lähempänä kuin 200m
	var is_behind = abs(angle_to) > (PI * 0.5) # Yli 90 astetta
	
	if is_behind and dist < 300.0:
		# PERUUTETAAN
		sync_speed_index = 1 # Half Reverse (tai 0 Full Reverse)
		
		# INVERTOITU OHJAUS:
		# Kun peruutetaan, jos kohde on "vasemmalla takana", 
		# peräsintä pitää kääntää OIKEALLE, jotta perä kääntyy kohti kohdetta.
		# angle_to on positiivinen vasemmalle, joten käännetään logiikka:
		if angle_to > 0: # Kohde vasemmalla takana
			sync_steering_index = 6 # Hard Starboard
		else: # Kohde oikealla takana
			sync_steering_index = 0 # Hard Port
			
	else:
		# AJETAAN ETEENPÄIN (Normaali logiikka)
		sync_speed_index = 4 # 1/2 Ahead
		
		if angle_to > 0.1:
			sync_steering_index = 0 # Hard Port
		elif angle_to < -0.1:
			sync_steering_index = 6 # Hard Starboard
		else:
			sync_steering_index = 3 # Midships


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

	# Päivitä kaikki tykit
	_update_turrets_target(target)

func _update_turrets_target(target: Node3D) -> void:
	for child in get_children():
		if child.has_method("set_turret_target"):
			child.set_turret_target(target)

func clear_turrets_target() -> void:
	for child in get_children():
		if child.has_method("set_turret_target"):
			child.set_turret_target(null)
	print("[Ship:%s] Tykkien targetit nollattu" % name)


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
		if current_speed < 0: 
			rotation_dir *= -1
		rotate_y(rotation_dir * turn_speed * delta)
	
	# Liike
	velocity = -global_transform.basis.z * current_speed
	move_and_slide()


func attack_ship() -> void:
	if not is_instance_valid(attack_target):
		return
	
	var target_pos = attack_target.global_position
	var dist = global_position.distance_to(target_pos)
	
	# 1. Lasketaan suunta viholliseen
	var to_target = global_position.direction_to(target_pos)
	var forward = -global_transform.basis.z
	
	# Lasketaan kulma viholliseen (radiaaneina, -PI ... PI)
	# 0 = vihollinen edessä, PI/-PI = vihollinen takana, PI/2 = vihollinen sivulla
	var angle_to_enemy = forward.signed_angle_to(to_target, Vector3.UP)
	
	# --- TILA: LIIAN KAUKANA (Aja kohti) ---
	if dist > 800.0:
		_drive_towards(target_pos)
		sync_speed_index = 6 # Täysi vauhti
		
	# --- TILA: LIIAN LÄHELLÄ (Aja poispäin) ---
	elif dist < 300.0:
		var escape_pos = global_position - to_target * 100.0
		_drive_towards(escape_pos)
		sync_speed_index = 4 # Puolivauhti
		
	# --- TILA: TAISTELUETÄISYYS (Broadside) ---
	else:
		# Päätetään kumpi kylki on lähempänä (Vasen vai Oikea)
		# Tavoitekulma on joko 90 astetta (PI/2) tai -90 astetta (-PI/2)
		var target_angle = PI/2 if angle_to_enemy > 0 else -PI/2
		
		# Jos halutaan "sulkea etäisyyttä" samalla kun käännytään kylki edellä, 
		# voidaan tavoitekulmaa hieman pienentää (esim. 70 astetta 90 sijaan)
		if dist > 600.0:
			target_angle *= 0.8 # Kääntyy hieman enemmän vihollista KOHTI
		elif dist < 450.0:
			target_angle *= 1.2 # Kääntyy hieman enemmän POISPÄIN
			
		# Lasketaan kuinka paljon meidän täytyy kääntyä saavuttaaksemme tavoitekulman
		var steer_error = angle_to_enemy - target_angle
		
		# Ohjataan peräsintä virheen mukaan
		if steer_error > 0.1:
			sync_steering_index = 0 # Hard Port
		elif steer_error < -0.1:
			sync_steering_index = 6 # Hard Starboard
		else:
			sync_steering_index = 3 # Midships
			
		sync_speed_index = 4 # Taistelunopeus

# UUSI: Uppoamislogiikka
func _apply_sinking(delta: float) -> void:
	# 1. Pystysuora uppoaminen kiihdytyksellä
	# Tavoitenopeus esim. 5.0, kiihdytys sama kuin laivalla (tai oma)
	current_sink_speed = move_toward(current_sink_speed, 5.0, acceleration * 0.2 * delta)
	global_position.y -= current_sink_speed * delta
	
	# 2. Kallistuminen (Z-akseli)
	rotation.z += 0.05 * delta 

@rpc("any_peer", "call_local", "reliable")
func start_sinking():
	if is_sinking: return 
	is_sinking = true
	
	# --- ASETETAAN LOPPUTILA ---
	sync_speed_index = 2 # STOP (Nopeus alkaa laskea accelerationin mukaan)
	
	# Peräsimen asettaminen pyyntösi mukaan:
	# Jos > 3 (Oikealle), asetetaan 4 (Pieni oikealle)
	# Jos < 3 (Vasemmalle), asetetaan 2 (Pieni vasemmalle)
	# Jos 3, pysyy 3:ssa.
	if sync_steering_index < 3:
		sync_steering_index = 2
	elif sync_steering_index > 3:
		sync_steering_index = 4
	
	# Vapautetaan kamera ja poistetaan hallinta
	is_player_controlled = false
	if UnitManager.controlled_unit == self:
		UnitManager.controlled_unit = null 
		set_hud_active(false)
	
	# Ryhmämuutokset (estää muita tekoälyjä hyökkäämästä hylkyyn)
	if is_in_group("Units"):
		remove_from_group("Units")
	add_to_group("Sinking")


func set_team(id: int):
	team_id = id

func get_icon_color() -> Color: #karttoja varten
	if team_id == multiplayer.get_unique_id(): return Color.CYAN
	return Color.GOLDENROD
