extends Node3D

@onready var spawn_point: Marker3D = $SpawnPoint
@onready var parent_ship = get_parent() # Viittaus laivaan (Carrier/Ship)

#lenskarin spawnaus
func _unhandled_input(event: InputEvent):
	# Tarkistetaan authority parent-laivan mukaan, jos spawnerilla ei ole omaa synkkausta
	if not parent_ship.is_multiplayer_authority(): return

	if event.is_action_pressed("carrier_spawn"):
		spawn_plane_request.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func spawn_plane_request():
	if not multiplayer.is_server(): return
	
	# Haetaan team_id parent-laivalta
	var team_id = parent_ship.get("team_id")
	
	if team_id == null:
		print("VIRHE: Parent-laivalla ei ole team_id muuttujaa!")
		return
	
	var pos = spawn_point.global_position
	var rot = spawn_point.global_rotation
	
	UnitSpawner.spawn_unit("fighter", team_id, pos, "plane_" + str(Time.get_ticks_msec()), rot)
