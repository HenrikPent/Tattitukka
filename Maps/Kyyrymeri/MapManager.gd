extends Node

var participants : Array = [] # tässä voi olla sekä Host, clientit että AI pelaajat

func setup(players: Array):
	participants = players
	
	if multiplayer.is_server():
		spawn_initial_units(participants)


func gets_spawn(team: int) -> Vector3:
	var nodes = get_tree().get_nodes_in_group("spawns_team_" + str(team))
	if nodes.size() > 0:
		return nodes.pick_random().global_position
	return Vector3.ZERO

func spawn_initial_units(player_ids: Array):
	if not multiplayer.is_server(): return

	for id in player_ids:
		var first_unit = null
		
		# Luodaan pelaajalle "paikka" maailmassa (0-4)
		# Käytetään jakojäännöstä 5:llä ja kerrotaan se 100:lla (väliä 100m)
		var player_slot = player_ids.find(id) # Tai: id % 5
		var base_x = player_slot * 400.0
		
		# 1. Destroyerit
		for i in range(6):
			var unit_name = "dest_" + str(id) + "_" + str(i)
			var spawn_pos = Vector3(base_x + 20, -5, i * 200) # Pieni offset carrieriin
			var unit = UnitSpawner.spawn_unit("destroyer", id, spawn_pos, unit_name)
			
			if first_unit == null:
				first_unit = unit
		
		# 2. Carrier
		for i in range(2):
			var unit_name = "carrier_" + str(id) + "_" + str(i)
			var spawn_pos = Vector3(base_x + i*300, 0, -500) 
			var unit = UnitSpawner.spawn_unit("carrier", id, spawn_pos, unit_name)
			
			# Asetetaan Carrier oletukseksi
			first_unit = unit
		
		# Hallinnan vaihto viiveellä
		var final_unit = first_unit
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(final_unit):
				UnitManager._perform_switch(id, final_unit)
		)

func _process(_delta):
	# Tässä voit hallita esim. sään muutoksia tai voittolaskentaa
	pass
