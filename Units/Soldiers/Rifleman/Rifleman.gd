# Rifleman.gd
extends CharacterBody3D

@export var team_id: int = 0
@export var is_player_controlled := false

@export_group("Movement")
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var swim_speed: float = 3.0
@export var gravity: float = 9.81

@export_group("Stats")
@export var health: int = 100

@export_group("Camera Settings")
@export var cam_mode_fixed: bool = false
@export var cam_offset := Vector3(0, 0, 0)
@export var cam_min_dist := 0.1
@export var cam_max_dist := 5

# Sisäiset
var can_shoot: bool = true
var fire_rate: float = 0.2
var damage_amount = 20

@onready var muzzle_flash: MeshInstance3D = $Gun.find_child("MuzzleFlash", true) if has_node("Gun") else null
@onready var gun_sound: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if is_player_controlled:
			_read_player_input()
			_handle_rotation()
		
		_apply_movement(delta)
	# Muut seuraavat MultiplayerSynchronizeria

func _read_player_input() -> void:
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var run_speed = 2.0 if Input.is_action_pressed("run") else 1.0
	
	if direction:
		velocity.x = direction.x * speed * run_speed
		velocity.z = direction.z * speed * run_speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

func _handle_rotation() -> void:
	# 1. Haetaan peliympäristön aktiivinen kamera
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	# 2. Haetaan kameraa ohjaava rigi (kameran parent)
	var rig = cam.get_parent()
	
	# 3. Varmistetaan että rigi on oikea ja se ohjaa tätä unittia
	if rig and "rotation_y" in rig and rig.controlled_unit == self:
		# Asetetaan ukon rintamasuunta samaan kuin kameran sivusuunta
		rotation.y = deg_to_rad(rig.rotation_y)
		
		# Asetetaan aseen korkeus samaan kuin kameran pystysuunta
		if has_node("Gun"):
			$Gun.rotation.x = deg_to_rad(-rig.rotation_x)

func _apply_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	move_and_slide()

func _unhandled_input(event):
	if is_multiplayer_authority() and is_player_controlled:
		if event.is_action_pressed("fire"):
			shoot()

func shoot():
	if not can_shoot: return
	can_shoot = false

	flash_muzzle_rpc.rpc()

	# Ampuminen CameraRigiä käyttäen (koska CameraData päivittyy siellä)
	var space_state = get_world_3d().direct_space_state
	var rig = get_node_or_null("/root/Main/CameraRig")
	if rig:
		var camera = rig.get_node("Camera3D") # Tai miten kamerasi on nimetty rigissä
		var ray_origin = camera.global_position
		var ray_end = ray_origin + (-camera.global_transform.basis.z * 1000.0)
		
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.exclude = [self.get_rid()]
		
		var result = space_state.intersect_ray(query)
		if result:
			if result.collider.has_method("receive_damage"):
				result.collider.receive_damage.rpc()

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

@rpc("call_local", "any_peer")
func flash_muzzle_rpc():
	if muzzle_flash:
		muzzle_flash.visible = true
		if gun_sound: gun_sound.play()
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false

@rpc("any_peer", "call_local", "reliable")
func receive_damage():
	if not is_multiplayer_authority(): return
	health -= damage_amount
	if health <= 0: die()

func die():
	health = 100
	global_position = Vector3(randf_range(-10, 10), 5, randf_range(-10, 10))
