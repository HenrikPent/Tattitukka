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
		if not is_instance_valid(unit): continue
		
		# Vain omat yksiköt piirtävät reittiviivoja
		if unit.get("team_id") != my_id: continue
		
		var start_pos = map.world_to_map(unit.global_position)
		var end_pos: Vector2
		var line_color: Color
		var has_target = false

		# 1. HYÖKKÄYS (Punainen viiva viholliseen)
		if is_instance_valid(unit.get("attack_target")):
			end_pos = map.world_to_map(unit.attack_target.global_position)
			line_color = Color.RED
			has_target = true
			
		# 2. SEURANTA (Vihreä viiva liittolaiseen)
		elif is_instance_valid(unit.get("follow_target")):
			end_pos = map.world_to_map(unit.follow_target.global_position)
			line_color = Color.GREEN
			has_target = true
			
		# 3. LIIKKUMISPISTE (Harmaa viiva tyhjään mereen)
		elif unit.get("ai_target_pos") != null:
			end_pos = map.world_to_map(unit.ai_target_pos)
			line_color = Color.GRAY
			has_target = true

		if has_target:
			# Piirretään viiva start_pos (laivan ikoni) -> end_pos (kohde)
			draw_line(start_pos, end_pos, line_color, 1.5, true)
			# Piirretään pieni ympyrä päätepisteeseen selkeyden vuoksi
			draw_circle(end_pos, 2.0, line_color)
