# LineLayer.gd
extends Control

@onready var map = get_parent() # Viittaus TacticalMapiin



func _process(_delta):
	if map.visible:
		queue_redraw()

func _draw():
	if map.units_node == null: return
	
	var my_id = multiplayer.get_unique_id()
	
	for unit in map.icon_map.keys():
		if not is_instance_valid(unit): continue
		if unit.get("team_id") != my_id: continue
		
		# KÄYTETÄÄN SUORAAN TÄTÄ PISTETTÄ ILMAN OFFSETIA
		var start_pos = map.world_to_map(unit.global_position)
		var end_pos: Vector2
		var line_color: Color
		var has_target = false

		if is_instance_valid(unit.get("follow_target")):
			end_pos = map.world_to_map(unit.follow_target.global_position)
			line_color = Color.GREEN_YELLOW
			has_target = true
		elif unit.get("ai_target_pos") != Vector3.ZERO:
			end_pos = map.world_to_map(unit.ai_target_pos)
			line_color = Color.GRAY
			has_target = true

		if has_target:
			draw_line(start_pos, end_pos, line_color, 1.5, true)
			draw_circle(end_pos, 2.0, line_color)
