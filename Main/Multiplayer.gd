#multiplayer
extends Node

const PORT = 42069
var peer = ENetMultiplayerPeer.new()
var game_ready := false
var all_player_ids := []


func host_game():
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	all_player_ids.append(1) # <--- hostin id
	print("Hostaus alkanut")

func join_game(ip):
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	print("Yritetään liittyä: ", ip)

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id):
	if not all_player_ids.has(id):
		all_player_ids.append(id)
		print("Pelaaja yhdistetty listaan: ", id)
	
	# Jos pelaajia on tarpeeksi (esim. vähintään 1 muukin), peli voi alkaa
	if all_player_ids.size() >= 1: # Voit säätää tätä
		game_ready = true

func _on_peer_disconnected(id):
	all_player_ids.erase(id)


# TÄMÄ AJETAAN VAIN CLIENTEILLA (koska serveri kutsuu tätä RPC:llä)
@rpc("authority", "reliable")
func start_game_rpc():
	print("Client vastaanotti aloitusviestin!")
	_setup_game_world_locally()



# TÄMÄ AJETAAN SERVERILLÄ (kun host painaa nappia)
# Päivitetty start_game ottamaan map_index
func start_game(map_index: int):
	if not multiplayer.is_server(): 
		return
	
	
	# Piilottaa valikon heti hostilta
	_setup_game_world_locally()
	
	
	var main_node = get_tree().root.get_node("Main")
	
	# 1. Käsketään kaikkia (myös hostia) lataamaan kartta
	main_node.change_map(map_index)
	
	# 2. ANNETAAN AIKAA: Kartan lataus voi kestää hetken.
	# Odotetaan sekunti ennen pelaajien luomista, jotta maa on jalkojen alla.
	await get_tree().create_timer(1.0).timeout
	
	# 3. JOS valittu kartta on se satunnainen mappi, generoidaan se
	# Etsitään maastoskripti LevelContainerin sisältä
	var terrain = main_node.get_node("MapContainer").find_child("*", true, false)
	if terrain and terrain.has_method("setup_and_generate"):
		var random_seed = randi() # Keksitään satunnainen luku
		terrain.setup_and_generate.rpc(random_seed) # Lähetetään luku kaikille
		print("Lähetetty siemenluku: ", random_seed)

	# 4. Luodaan pelaajat vasta kun maa on jalkojen alla
	for id in all_player_ids:
		main_node.add_player(id)
	
	if main_node.has_node("UnitSpawner"):
		main_node.get_node("UnitSpawner").spawn_starting_units(all_player_ids)
	
	# Viimeinen varmistusviive ja peli käyntiin clienteilla
	await get_tree().create_timer(0.2).timeout
	start_game_rpc.rpc()

# Yhteinen funktio kaikille (ajetaan sekä hostilla että clientilla)
func _setup_game_world_locally():
	var main_node = get_tree().root.get_node("Main")
	
	# Piilotetaan MainMenu
	var menu = main_node.get_node_or_null("MainMenu")
	if menu:
		menu.hide()
		print("Valikko piilotettu!")
	
	# Lukitaan hiiri
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
