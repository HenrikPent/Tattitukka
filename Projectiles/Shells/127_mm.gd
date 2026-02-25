extends Area3D

var velocity := Vector3.ZERO
var bullet_gravity := 15.0
var shooter_id := -1
var life_time := 15.0

func _ready():
	# Kytketään signaalit
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# Vain palvelin hallitsee elinikää
	if is_multiplayer_authority():
		get_tree().create_timer(life_time).timeout.connect(explode)

func setup(p_velocity: Vector3, p_shooter_id: int):
	velocity = p_velocity
	shooter_id = p_shooter_id

func _physics_process(delta: float):
	velocity.y -= bullet_gravity * delta
	global_position += velocity * delta
	
	# Korjaus look_at varoitukseen:
	if velocity.length() > 0.1:
		var target_pos = global_position + velocity.normalized()
		# Jos liikesuunta on pystysuora, käytetään vaihtoehtoista UP-vektoria (esim. Vector3.RIGHT)
		var up_vec = Vector3.UP
		if abs(velocity.normalized().dot(Vector3.UP)) > 0.99:
			up_vec = Vector3.RIGHT
		look_at(target_pos, up_vec)

func _on_area_entered(area: Area3D):
	_handle_collision(area)

func _on_body_entered(body: Node):
	_handle_collision(body)

func _handle_collision(victim: Node):
	# TÄRKEÄ: Clientit eivät tee osumalogiikkaa ollenkaan!
	# Ne vain näyttävät ammuksen liikkeen. Palvelin hoitaa kaiken muun.
	if not is_multiplayer_authority(): return
	
	# 1. Määritetään efekti
	var effect_type = "Impact_127mm"
	if victim.is_in_group("Water") or victim.name.to_lower().contains("water"):
		effect_type = "water_splash"
	
	# 2. Kutsutaan efekti-RPC (ProjectileManager hoitaa)
	var manager = get_node_or_null("/root/Main/ProjectileManager")
	if manager:
		manager.spawn_effect.rpc(effect_type, global_position)
	
	# 3. ILMOITUS DAMAGE MANAGERILLE (Uusi työnjako)
	# Etsitään damage manager joko uhrista tai sen vanhemmasta
	var dm = victim.get_node_or_null("DamageManager")
	if not dm and victim.get_parent(): 
		dm = victim.get_parent().get_node_or_null("DamageManager")
		
	if dm and dm.has_method("take_damage"):
		dm.take_damage(50.0, global_position, shooter_id)

	# 4. Tuhoaminen (Vain palvelin kutsuu tätä)
	explode()

func explode():
	if is_multiplayer_authority() and is_inside_tree():
		queue_free()
