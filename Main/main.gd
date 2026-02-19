extends Node3D

@export var player_scene: PackedScene = preload("res://Player/Player.tscn")

@export var maps : Array[PackedScene] # Vedä kartta-skenet tähän editorissa

var current_seed = 0

func _ready():
	# Kun joku yhdistää, serveri hoitaa pelaajan luomisen
	multiplayer.peer_disconnected.connect(remove_player)

func add_player(id: int):
	
	if player_scene == null:
		print("VIRHE: player_scene on null! Tarkista Main-noden asetukset Inspectorissa.")
		return
	
	if $Players.has_node(str(id)):
		print("VAROITUS: Pelaaja ", id, " on jo olemassa! Skipataan luonti.")
		return
	
	print("Lisätään pelaaja ID: ", id)
	var p = player_scene.instantiate()
	
	# 1. ASETETAAN NIMI ENNEN ADD_CHILDIA
	p.name = str(id) 
	
	var players_container = get_node_or_null("Players") 
	if players_container:
		# 2. KÄYTETÄÄN TOISENA PARAMETRINA TRUE
		# Tämä varmistaa, että nimi pysyy täsmälleen samana verkon yli
		players_container.add_child(p, true)
	else:
		print("VIRHE: Players-nodea ei löytynyt!")

func remove_player(id: int):
	if $Players.has_node(str(id)):
		$Players.get_node(str(id)).queue_free()

func _input(event):
	if event.is_action_pressed("escape"): # ESC-näppäin
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


#---  MAPIN LATAUS  ---# 
func change_map(map_index: int):
	if is_multiplayer_authority():
		# Arvotaan siemen tässä ja lähetetään se kaikille latauskäskyn mukana
		var new_seed = randi()
		load_map.rpc(map_index, new_seed)


#mapin lataus rpc:lä, jotta jokainen pelaaja lataa mapin omalta levyltä(parempi isoille mapeille)
@rpc("call_local", "reliable")
func load_map(map_index: int, seed_val: int):
	print("DEBUG: load_map alkoi. Indeksi: ", map_index, " Seed: ", seed_val)
	
	for child in $MapContainer.get_children():
		child.queue_free()
	
	if map_index >= maps.size():
		print("DEBUG VIRHE: map_index on suurempi kuin maps-listan koko!")
		return

	var new_map = maps[map_index].instantiate()
	$MapContainer.add_child(new_map)
	print("DEBUG: Karttaskene instansioitu: ", new_map.name)

	# Etsitään Mesh-node
	var terrain_mesh = new_map.find_child("Mesh", true, false)
	
	if terrain_mesh:
		print("DEBUG: Mesh-node löytyi polusta: ", terrain_mesh.get_path())
		if terrain_mesh.has_method("generate"):
			print("DEBUG: Kutsutaan generate-funktiota...")
			terrain_mesh.generate(seed_val)
		else:
			print("DEBUG VIRHE: Mesh-nodella EI OLE generate-funktiota! Tarkista skripti.")
	else:
		print("DEBUG VAROITUS: Nodeluettelosta ei löytynyt 'Mesh'-nimistä nodea.")


# Host kutsuu tätä aloittaessaan
func start_map_generation():
	current_seed = randi()
	# Generoidaan heti hostille
	$RandomMap/StaticBody3D/CollisionShape3D/Mesh.generate(current_seed)
	# Lähetetään siemenluku kaikille muille
	sync_map.rpc(current_seed)
	
	# RPC, joka kertoo kaikille mikä siemenluku on
@rpc("authority", "call_local", "reliable")
func sync_map(seed_val):
	if not multiplayer.is_server(): # Host generoi jo yllä, joten skipataan
		var map_mesh = get_node_or_null("RandomMap/StaticBody3D/CollisionShape3D/Mesh")
		if map_mesh:
			map_mesh.generate(seed_val)
