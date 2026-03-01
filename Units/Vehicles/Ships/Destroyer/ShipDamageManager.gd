extends Node

@export var max_health: float = 500.0
var current_health: float

@export var ship_owner_id: int # Asetetaan kun laiva spawnataan

func _ready():
	current_health = max_health
	# Kytkeydytään laivan hitboxiin
	var hitbox = get_parent().get_node("HitBox")
	hitbox.area_entered.connect(_on_hit_received)

func _on_hit_received(area: Area3D):
	# Tarkistetaan onko osuja ammus (eikä esim. vesi-alue)
	if area.has_method("setup"): 
		# Estetään ettei oma ammus tee vauriota
		if area.get("shooter_id") == ship_owner_id:
			return
			
		take_damage(50.0, area.global_position)

func take_damage(amount: float, hit_pos: Vector3):
	current_health -= amount
	print(get_parent().name, " HP: ", current_health, " / ", max_health)
	
	# Tarkistetaan erikoisvauriot moduuleille osumakohdan perusteella
	check_module_damage(hit_pos)
	
	if current_health <= 0:
		sink_ship()

func check_module_damage(_hit_pos: Vector3):
	# Tässä kohtaa vertaat hit_pos:ia laivan moottorin tai tykkien sijaintiin
	# Jos etäisyys on pieni, vaurioita kyseistä osaa
	pass

func sink_ship():
	var ship = get_parent()
	if not ship or ship.get_meta("is_sinking", false): 
		return
	
	ship.set_meta("is_sinking", true) # Varmistetaan, ettei uppoamista kutsuta kahdesti
	ship.team_id = 0
	
	if ship.has_method("start_sinking"):
		ship.start_sinking()
	
	# RATKAISU: Älä käytä lambdaa, joka kaappaa 'ship'-muuttujan.
	# Sen sijaan luodaan ajastin ja kytketään se laivaan itseensä.
	var timer = get_tree().create_timer(10.0)
	timer.timeout.connect(ship.queue_free)
