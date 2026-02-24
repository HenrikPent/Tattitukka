extends Control

@onready var roller: VBoxContainer = $Speed
@export var label_height : float = 27.0 

func _process(delta: float) -> void:
	var ship = PlayerManager.controlled_unit
	
	if is_instance_valid(ship) and ship.is_player_controlled:
		visible = true
		_update_speed_roller(ship, delta)
	else:
		visible = false

func _update_speed_roller(ship: Node3D, delta: float) -> void:
	var index = ship.get("sync_speed_index") # Arvo 0-6
	
	if index != null:
		var total_labels = roller.get_child_count()
		var reversed_index = (total_labels - 1) - index
		
		# Jos haluat, että valittu teksti on ikkunan KESKELLÄ, 
		# ja ikkuna on 3 labelia korkea, target_y pitää siirtää yhden labelin verran alemmas
		# jotta reversed_index 0 ei ole ikkunan yläreunassa vaan keskellä.
		var offset_to_center = label_height # Tämä jättää yhden tyhjän paikan yläpuolelle
		var target_y = -(reversed_index * label_height) + offset_to_center
		
		# Sulava rullaus
		roller.position.y = lerp(roller.position.y, target_y, 12.0 * delta)
		
		var labels = roller.get_children()
		for i in range(labels.size()):
			# Lasketaan kuinka kaukana tämä label on valitusta (0 = valittu, 1 = naapuri)
			var distance = abs(i - reversed_index)
			
			if distance == 0:
				# VALITTU (Keskellä)
				labels[i].modulate = Color.WHITE
				labels[i].modulate.a = lerp(labels[i].modulate.a, 1.0, 15.0 * delta)
				labels[i].scale = lerp(labels[i].scale, Vector2(1.1, 1.1), 15.0 * delta)
			elif distance == 1:
				# YLÄ- JA ALAPUOLI
				labels[i].modulate = Color.WHITE
				labels[i].modulate.a = lerp(labels[i].modulate.a, 0.3, 15.0 * delta) # Himmeämpi
				labels[i].scale = lerp(labels[i].scale, Vector2(0.9, 0.9), 15.0 * delta)
			else:
				# MUUT (Näkymättömät)
				labels[i].modulate.a = lerp(labels[i].modulate.a, 0.0, 15.0 * delta)
				labels[i].scale = lerp(labels[i].scale, Vector2(0.7, 0.7), 15.0 * delta)
