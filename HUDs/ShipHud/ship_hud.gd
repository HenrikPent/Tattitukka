# shipHud.gd
extends Control

@onready var speed_roller: VBoxContainer = $Speed/VBoxContainer
@onready var steer_roller: HBoxContainer = $Steering/HBoxContainer 

@export var label_height : float = 27.0 
@export var label_width : float = 27.0 # Yhden ohjaustekstin varattu leveys

@onready var ship = get_parent().get_parent() 

func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	
	_update_speed_roller(ship, delta)
	_update_steering_roller(ship, delta)

func _update_speed_roller(ship_ref: Node3D, delta: float) -> void:
	var index = ship_ref.get("sync_speed_index")
	if index == null: return
	
	var total_labels = speed_roller.get_child_count()
	var reversed_index = (total_labels - 1) - index
	
	var target_y = -(reversed_index * label_height) + label_height
	speed_roller.position.y = lerp(speed_roller.position.y, target_y, 12.0 * delta)
	
	_apply_effects(speed_roller.get_children(), reversed_index, delta)


func _update_steering_roller(ship_ref: Node3D, delta: float) -> void:
	var index = ship_ref.get("sync_steering_index")
	if index == null: return
	
	# Ohjausindeksissä 0 on vasen ja 6 on oikea, joten emme tarvitse kääntämistä (reverse)
	# Kohde on negatiivinen x, jotta rulla liikkuu vasemmalle kun valinta menee oikealle
	var target_x = -(index * label_width) + label_width
	
	steer_roller.position.x = lerp(steer_roller.position.x, target_x, 12.0 * delta)
	
	_apply_effects(steer_roller.get_children(), index, delta)

# Yleiskäyttöinen funktio labelien korostamiseen
func _apply_effects(labels: Array, active_index: int, delta: float) -> void:
	for i in range(labels.size()):
		var distance = abs(i - active_index)
		
		if distance == 0:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 1.0, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(1.1, 1.1), 15.0 * delta)
		elif distance == 1:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 0.4, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(0.9, 0.9), 15.0 * delta)
		else:
			labels[i].modulate.a = lerp(labels[i].modulate.a, 0.0, 15.0 * delta)
			labels[i].scale = lerp(labels[i].scale, Vector2(0.7, 0.7), 15.0 * delta)
