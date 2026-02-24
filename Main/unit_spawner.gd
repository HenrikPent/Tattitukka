#unit spawner
extends Node

# Rekisteröidään yksiköt, jotta MultiplayerSpawner osaa ne synkronoida
@onready var scenes = {
	"destroyer": preload("res://Units/Vehicles/Ships/Destroyer/destroyer.tscn"),
	"fighter": preload("res://Units/Vehicles/Planes/FighterV1/figterV1.tscn"),
	"carrier": preload("res://Units/Vehicles/Ships/Carrier/Carrier.tscn"),
	"rifleman": preload("res://Units/Soldiers/Rifleman/Rifleman.tscn")
	}

func spawn_starting_units(player_ids: Array):
	if not multiplayer.is_server(): return

	for id in player_ids:
		var first_unit = null
		
		# Luodaan pelaajalle "paikka" maailmassa (0-4)
		# Käytetään jakojäännöstä 5:llä ja kerrotaan se 100:lla (väliä 100m)
		var player_slot = player_ids.find(id) # Tai: id % 5
		var base_x = player_slot * 1000.0
		
		# 1. Destroyerit
		for i in range(6):
			var unit_name = "dest_" + str(id) + "_" + str(i)
			var spawn_pos = Vector3(base_x + 20, 0, i * 200) # Pieni offset carrieriin
			var unit = spawn_unit("destroyer", id, spawn_pos, unit_name)
			
			if first_unit == null:
				first_unit = unit
		
		# 2. Carrier
		for i in range(1):
			var unit_name = "carrier_" + str(id) + "_" + str(i)
			var spawn_pos = Vector3(base_x, 0, -500) 
			var unit = spawn_unit("carrier", id, spawn_pos, unit_name)
			
			# Asetetaan Carrier oletukseksi
			first_unit = unit
		
		# Hallinnan vaihto viiveellä
		var final_unit = first_unit
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(final_unit):
				PlayerManager._perform_switch(id, final_unit)
		)


func spawn_unit(type: String, team: int, pos: Vector3, nime: String, rot: Vector3 = Vector3.ZERO):
	if not multiplayer.is_server(): return null # Vain serveri saa spawnata
	
	var unit = scenes[type].instantiate()
	
	# 1. NIMI: Tämän on oltava SAMA kaikilla, jotta synkronointi toimii.
	unit.name = nime 
	
	# 2. LISÄYS: Lisätään puuhun ENNEN kuin asetetaan position
	# (Tämä triggeröi MultiplayerSpawnerin lähettämään paketin klienteille)
	var units_node = get_node("/root/Main/Units")
	units_node.add_child(unit, true)
	
	# 3. TRANSFORMAATIO: Asetetaan vasta kun unitti on "sisällä"
	unit.global_position = pos
	unit.global_rotation = rot
	
	# 4. DATA: Authority ja tiimi
	if unit.has_method("set_team"):
		unit.set_team(team)
	
	# Oletuksena authority on palvelin (AI)
	unit.set_multiplayer_authority(1)
	
	return unit
