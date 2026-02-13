
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

func _physics_process(delta: float) -> void:
	# 1. VAIN authority (se joka ajaa laivaa) laskee liikkeen
	if is_multiplayer_authority():
		if is_player_controlled:
			_read_player_input()
		else:
			_run_ai_logic()
		
		_apply_movement(delta)
	else:
		# 2. MUUT (clientit) vain seuraavat palvelimen asettamaa paikkaa
		# Jos haluat sulavan liikkeen ilman tökkimistä, voit lisätä tähän lerppauksen.
		pass

func _read_player_input() -> void:
	sync_steering = Input.get_axis("right", "left")
	
	if Input.is_action_just_pressed("forward"):
		sync_speed_index = clampi(sync_speed_index + 1, 0, 5)
	if Input.is_action_just_pressed("backward"):
		sync_speed_index = clampi(sync_speed_index - 1, 0, 5)

func _run_ai_logic() -> void:
	# Tähän myöhemmin AI:n ohjaus (esim. sync_steering = 0.2)
	pass

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
