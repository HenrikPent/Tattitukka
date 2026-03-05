extends Node

var participants: Array = []
var spawn_list: Array[Vector3] = []
var rotation_list: Array[Vector3] = [] # Tallennetaan spawn-pisteiden rotaatiot

func _ready():
	_cache_spawn_points()

func setup(players: Array):
	participants = players
	print("MapManager setup: osallistujat = ", participants)
	if multiplayer.is_server():
		spawn_initial_units(participants)

# Kerätään spawn-pointit ja niiden rotaatiot
func _cache_spawn_points():
	var spawns_root = get_node_or_null("SpawnPoints")
	if not spawns_root:
		spawns_root = get_parent().get_node_or_null("SpawnPoints")
	
	if not spawns_root:
		print("VIRHE: SpawnPoints-nodea ei löytynyt!")
		return

	spawn_list.clear()
	rotation_list.clear()
	
	var children = spawns_root.get_children()
	# Järjestetään nimen mukaan (Spawn1, Spawn2...), jotta järjestys on vakio
	children.sort_custom(func(a, b): return a.name < b.name)

	for child in children:
		spawn_list.append(child.global_position)
		rotation_list.append(child.global_rotation)
		print("Spawn-piste: ", child.name, " Pos: ", child.global_position, " Rot: ", child.global_rotation)

func spawn_initial_units(player_ids: Array):
	if not multiplayer.is_server():
		return

	print("MapManager: Aloitetaan yksiköiden haku rotaatiolla...")

	for i in range(player_ids.size()):
		var p_id = player_ids[i]
		
		# Haetaan spawn-tiedot indeksillä
		var base_pos = Vector3.ZERO
		var base_rot = Vector3.ZERO
		
		if spawn_list.size() > 0:
			var idx = i % spawn_list.size()
			base_pos = spawn_list[idx]
			base_rot = rotation_list[idx]
		else:
			base_pos = Vector3(i * 400, 0, 0)

		# Luodaan apu-quaternion, jolla käännetään muodostelman offsetit
		var q = Quaternion.from_euler(base_rot)
		var first_unit = null

		# --- 1. DESTROYERIT (Sivulla/Edessä) ---
		for j in range(3):
			var unit_name = "dest_" + str(p_id) + "_" + str(j)
			
			# Määritetään offset suhteessa suoraan linjaan (x = sivu, z = etu/taka)
			var raw_offset = Vector3((j - 1) * 60.0, 0, 100.0) 
			# Käännetään offset vastaamaan spawn-pisteen suuntaa
			var rotated_offset = q * raw_offset
			var final_pos = base_pos + rotated_offset
			
			var unit = UnitSpawner.spawn_unit("destroyer", p_id, final_pos, unit_name, base_rot)
			if first_unit == null: first_unit = unit

		# --- 2. CARRIER (Keskellä) ---
		var carrier_name = "carrier_" + str(p_id)
		# Carrier hieman taakse (Z-akselilla negatiivinen luku on usein taaksepäin Godotissa)
		var carrier_offset = q * Vector3(0, 0, -150.0)
		var carrier_pos = base_pos + carrier_offset
		
		var carrier_unit = UnitSpawner.spawn_unit("carrier", p_id, carrier_pos, carrier_name, base_rot)
		
		# Asetetaan hallinta ensisijaisesti Carrieriin
		if carrier_unit:
			first_unit = carrier_unit
	
		# --- 2. SUBMARINE ---
		var submarine_name = "submarine_" + str(p_id)
		# Carrier hieman taakse (Z-akselilla negatiivinen luku on usein taaksepäin Godotissa)
		var submarine_offset = q * Vector3(150, 0, -150.0)
		var submarine_pos = base_pos + submarine_offset
		
		var _submarine_unit = UnitSpawner.spawn_unit("submarine", p_id, submarine_pos, submarine_name, base_rot)
		
		
		# --- 3. HALLINNAN ASSETUS ---
		# AI (ID -1) ei tarvitse kameran vaihtoa
		if first_unit and p_id != -1:
			_apply_control_with_delay(p_id, first_unit)

func _apply_control_with_delay(player_id: int, unit: Node):
	# Viive varmistaa, että objektit ovat ehtineet syntyä kaikkialla
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(unit):
		print("MapManager: Vaihdetaan hallinta -> Pelaaja ", player_id)
		UnitManager._perform_switch(player_id, unit)

# Apufunktio, jos tarvitset spawnia muualta (valinnainen)
func gets_spawn_data(index: int) -> Dictionary:
	if spawn_list.size() > 0:
		var idx = index % spawn_list.size()
		return {"pos": spawn_list[idx], "rot": rotation_list[idx]}
	return {"pos": Vector3.ZERO, "rot": Vector3.ZERO}
