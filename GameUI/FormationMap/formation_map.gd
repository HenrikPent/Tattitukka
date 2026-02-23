extends Control

var leader_unit: Node3D = null
var followers: Array = [] # Ne, jotka seuraavat leaderia
var dragging_unit: Node = null

@export var area_range := 500.0 # Kartan säde metreinä
@export var map_size := 600.0  # Kartan koko pikseleinä


func _process(_delta):
	if visible:
		# 1. Katsotaan, mitä unittia pelaaja ohjaa
		var active_unit = PlayerManager.controlled_unit
		
		if is_instance_valid(active_unit):
			# 2. Etsitään tämän yksikön johtaja (komentoketjun huippu)
			leader_unit = _find_ultimate_leader(active_unit)
			
			if is_instance_valid(leader_unit):
				_update_followers()
				queue_redraw()

func _find_ultimate_leader(unit: Node3D) -> Node3D:
	var current = unit
	var max_depth = 5
	# Jos yksikkö seuraa jotakuta, seurataan ketjua ylöspäin
	while is_instance_valid(current.get("follow_target")) and max_depth > 0:
		current = current.follow_target
		max_depth -= 1
	return current # Tämä on nyt se "Kuningaslaiva", jota kaikki muut seuraavat


func _update_followers():
	# Haetaan kaikki laivat, jotka seuraavat tätä johtajaa
	followers.clear()
	var units = get_node("/root/Main/Units").get_children()
	for u in units:
		if u.get("follow_target") == leader_unit:
			followers.append(u)


func _draw():
	if not is_instance_valid(leader_unit): return
	
	var center = Vector2(map_size/2, map_size/2)
	
	# Piirretään johtaja keskelle (se ei liiku Formation Mapissa)
	draw_circle(center, 8, Color.WHITE)
	draw_string(ThemeDB.fallback_font, center + Vector2(12, 5), "LEADER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

	for u in followers:
		var is_me = (u == PlayerManager.controlled_unit)
		var base_color = u.get_icon_color()
		if is_me: base_color = Color.GREEN # Korostetaan oma laiva

		# 1. Tavoitepaikka (Offset)
		var offset_pos = _offset_to_pixel(u.formation_offset) + center
		draw_rect(Rect2(offset_pos - Vector2(6,6), Vector2(12,12)), base_color)
		
		# 2. Nykyinen fyysinen sijainti (Himmeä haamu)
		var rel_pos_world = u.global_position - leader_unit.global_position
		var local_pos = leader_unit.global_transform.basis.inverse() * rel_pos_world
		var current_pixel_pos = _offset_to_pixel(Vector3(local_pos.x, 0, local_pos.z)) + center
		
		var ghost_color = base_color
		ghost_color.a = 0.4
		draw_circle(current_pixel_pos, 4, ghost_color)
		
		# 3. Yhdysviiva
		draw_line(offset_pos, current_pixel_pos, ghost_color, 1.5)


func _offset_to_pixel(offset: Vector3) -> Vector2:
	# Skaalataan metrit pikseleiksi
	return Vector2(offset.x, offset.z) * (map_size / (area_range * 2))

func _pixel_to_offset(pixel_pos: Vector2) -> Vector3:
	var centered = pixel_pos - Vector2(map_size/2, map_size/2)
	var scaled = centered / (map_size / (area_range * 2))
	return Vector3(scaled.x, 0, scaled.y)

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			# Tarkista osuiko johonkin offset-ikoniin
			for u in followers:
				var pos = _offset_to_pixel(u.formation_offset) + Vector2(map_size/2, map_size/2)
				if event.position.distance_to(pos) < 15:
					dragging_unit = u
					break
		else:
			dragging_unit = null
			
	if event is InputEventMouseMotion and dragging_unit:
		# Päivitetään offset raahauksen mukaan
		dragging_unit.formation_offset = _pixel_to_offset(event.position)
