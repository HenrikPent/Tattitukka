extends Area3D

var velocity := Vector3.ZERO
var bullet_gravity := 15.0
var shooter_id := -1
var life_time := 15.0 # Ammuksen elinikä sekunneissa

func _ready():
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(life_time).timeout.connect(func(): queue_free())

func setup(p_velocity: Vector3, p_shooter_id: int):
	velocity = p_velocity
	shooter_id = p_shooter_id

func _physics_process(delta: float):
	velocity.y -= bullet_gravity * delta
	global_position += velocity * delta
	
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized())

func _on_body_entered(body: Node):
	
	# 1. Määritetään efektin tyyppi
	var effect_type = "Impact_127mm" # Oletus: osuma laivaan/maahan
	
	# Tarkistetaan onko osuma vettä
	if body.is_in_group("Water") or body.name.to_lower().contains("water") or (body is StaticBody3D and body.collision_layer & 2):
		effect_type = "water_splash"
	
	# 2. Kutsutaan manageria
	var manager = get_node_or_null("/root/Main/ProjectileManager")
	if manager:
		manager.spawn_effect.rpc(effect_type, global_position)
	
	# 3. Ammus pois pelistä
	explode()

func explode():
	queue_free()
