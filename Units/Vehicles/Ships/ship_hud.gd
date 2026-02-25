extends Control

@onready var roller: VBoxContainer = $Speed
@export var label_height : float = 27.0 

# Haetaan viittaus laivaan kerran (Ship -> HUD -> ShipHUD)
@onready var ship = get_parent().get_parent() 

func _process(delta: float) -> void:
	# 1. Turvatarkistus: Jos laiva katoaa, ei tehdä mitään
	if not is_instance_valid(ship):
		return
	
	# 2. HUDin oma logiikka: Päivitetään rullaa
	# (Näkyvyyttä ei enää hallita tässä, PlayerManager hoitaa sen)
	_update_speed_roller(ship, delta)

func _update_speed_roller(ship_ref: Node3D, delta: float) -> void:
	var index = ship_ref.get("sync_speed_index")
	if index == null: return
	
	var total_labels = roller.get_child_count()
	var reversed_index = (total_labels - 1) - index
	
	var offset_to_center = label_height 
	var target_y = -(reversed_index * label_height) + offset_to_center
	
	# Animaatiot
	roller.position.y = lerp(roller.position.y, target_y, 12.0 * delta)
	
	var labels = roller.get_children()
	for i in range(labels.size()):
		var distance = abs(i - reversed_index)
		
		if distance == 0:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 1.0, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(1.1, 1.1), 15.0 * delta)
		elif distance == 1:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 0.3, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(0.9, 0.9), 15.0 * delta)
		else:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 0.0, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(0.7, 0.7), 15.0 * delta)
