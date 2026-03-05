# LineLayer.gd
extends Control

@onready var map = get_parent() # Viittaus TacticalMapiin

func _process(_delta):
	if map.visible:
		# PAKOTETAAN LineLayer täsmäämään TacticalMapin kokoon ja sijaintiin
		size = map.size
		position = Vector2.ZERO
		queue_redraw()

func _draw():
	if map.units_node == null: return
	
	var my_id = multiplayer.get_unique_id()
	
	for unit in map.icon_map.keys():
		# 1. Tarkistetaan itse yksikkö (onko validi ja puussa)
		if not is_instance_valid(unit) or not unit.is_inside_tree(): 
			continue
		
		# Vain omat yksiköt piirtävät reittiviivoja
		if unit.get("team_id") != my_id: continue
		
		var start_pos = map.world_to_map(unit.global_position)
		var end_pos: Vector2
		var line_color: Color
		var has_target = false

		# 2. HYÖKKÄYS (Tarkistetaan kohteen olemassaolo maailmassa)
		var a_target = unit.get("attack_target")
		if is_instance_valid(a_target) and a_target.is_inside_tree():
			end_pos = map.world_to_map(a_target.global_position)
			line_color = Color.RED
			has_target = true
			
		# 3. SEURANTA (Tarkistetaan kohteen olemassaolo maailmassa)
		elif is_instance_valid(unit.get("follow_target")):
			var f_target = unit.get("follow_target")
			if is_instance_valid(f_target) and f_target.is_inside_tree():
				end_pos = map.world_to_map(f_target.global_position)
				line_color = Color.GREEN
				has_target = true
			
		# 4. LIIKKUMISPISTE (Tämä on Vector3, ei tarvitse is_inside_tree)
		elif unit.get("ai_target_pos") != null:
			end_pos = map.world_to_map(unit.ai_target_pos)
			line_color = Color.GRAY
			has_target = true

		if has_target:
			draw_line(start_pos, end_pos, line_color, 1.5, true)
			draw_circle(end_pos, 2.0, line_color)
