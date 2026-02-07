# Rifleman.gd
extends CharacterBody3D

# --- Muuttujat ---
@export_group("Movement")
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var swim_speed: float = 3.0
@export var mouse_sensitivity: float = 0.002

@export_group("Stats")
@export var health: int = 100

@export_group("Environment")
@export var water_level: float = 0.0

@export_group("Camera Settings")
@export var cam_offset := Vector3(0, 0, 0) # Katsoo silmien korkeudelle
@export var cam_min_dist := 0.2
@export var cam_max_dist := 10


# Sisäiset muuttujat
var gravity = 0 #ProjectSettings.get_setting("physics/3d/default_gravity")
var is_map_active: bool = false
var is_swimming: bool = false
var current_vehicle: Node3D = null
var can_shoot: bool = true
var fire_rate: float = 0.2
var damage_amount = 20

# Viite ulkoiseen kameraan (Player-nodesta)
var camera: Camera3D = null

# --- Onready-viittaukset ---
@onready var muzzle_flash: MeshInstance3D = $Gun.find_child("MuzzleFlash", true)
@onready var gun_sound: AudioStreamPlayer3D = $Gun.find_child("AudioStreamPlayer3D", true)
@onready var water_overlay = find_child("WaterOverlay", true, false)

func _enter_tree():
	# Asetetaan authority heti kun unitti syntyy verkon yli
	set_multiplayer_authority(name.to_int())

func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process(false)
		return
	
	# Etsitään oma Player-nodi ("haamu") ja sen kamera
	var my_player = get_node_or_null("/root/Main/Players/" + name)
	if my_player:
		camera = my_player.get_node("CameraRig/Camera3D")
		camera.make_current()
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if muzzle_flash: muzzle_flash.hide()

func is_local_player() -> bool:
	return multiplayer.get_unique_id() == get_multiplayer_authority()

func _process(_delta):
	if not is_local_player() or not camera: return
	
	var rig = camera.get_parent() # Haetaan CameraRig
	
	# 1. Vesiefekti
	var under_water = camera.global_position.y < (water_level - 0.2)
	if water_overlay: water_overlay.visible = under_water
	
	# 2. Ukon ja aseen kääntäminen (Tämä on se tärkeä osa)
	if rig:
		# Käännetään ukko sivusuunnassa (Y)
		# Huom: CameraRigissä rotation_y on asteina -> muutetaan radiaaneiksi
		rotation.y = deg_to_rad(rig.rotation_y)
		
		# Käännetään asetta pystysuunnassa (X)
		if $Gun:
			# TÄRKEÄÄ: CameraRig käyttää kaavassa "-rotation_x", joten käytämme samaa tässä.
			# Jos ase liikkuu väärään suuntaan, poista tuo miinusmerkki.
			$Gun.rotation.x = deg_to_rad(-rig.rotation_x)


func _physics_process(delta):
	if not is_local_player(): return
	

	if current_vehicle:
		velocity = Vector3.ZERO
		return
	
	# --- FYSIKKA PÄIVITYKSET (60Hz) ---
	handle_movement(delta)
	move_and_slide()

func handle_movement(delta):
	is_swimming = global_position.y < (water_level - 0.5)
	
	if is_swimming:
		velocity.y -= (gravity * 0.2) * delta
		if Input.is_action_pressed("jump"): 
			velocity.y = swim_speed
	else:
		if not is_on_floor(): 
			velocity.y -= gravity * delta
		else: 
			velocity.y = -0.1
			if Input.is_action_just_pressed("jump"):
				velocity.y = jump_velocity

	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var run_speed = 2.0 if Input.is_action_pressed("run") else 1.0
	var cur_speed = swim_speed if is_swimming else speed
	
	if direction:
		velocity.x = direction.x * cur_speed * run_speed
		velocity.z = direction.z * cur_speed * run_speed
	else:
		velocity.x = move_toward(velocity.x, 0, cur_speed)
		velocity.z = move_toward(velocity.z, 0, cur_speed)

func _unhandled_input(event):
	if not is_local_player(): return
	
	
	if event.is_action_pressed("fire"):
		shoot()

func shoot():
	if not can_shoot or not camera: return
	can_shoot = false

	if gun_sound: gun_sound.play()
	flash_muzzle_rpc.rpc()

	# Ampuminen CameraData.hit_positioniin
	var space_state = get_world_3d().direct_space_state
	var ray_origin = camera.global_position
	var ray_end = ray_origin + (camera.global_transform.basis.z * -5000.0) # Ammutaan suoraan eteenpäin
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self.get_rid()]
	
	var result = space_state.intersect_ray(query)
	if result:
		var target = result.collider
		if target.has_method("receive_damage"):
			target.receive_damage.rpc()

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

@rpc("call_local", "any_peer")
func flash_muzzle_rpc():
	if muzzle_flash:
		muzzle_flash.visible = true
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false

@rpc("any_peer", "call_local", "reliable")
func receive_damage():
	if not is_multiplayer_authority(): return
	health -= damage_amount
	if health <= 0:
		die()

func die():
	health = 100
	global_position = Vector3(randf_range(-10, 10), 5, randf_range(-10, 10))
	print(name, " respawnasi.")
