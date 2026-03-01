#multiplayer
extends Node

signal player_count_updated(count: int)
signal connection_lost # Uusi signaali

var last_disconnect_reason = "GENERIC"

const PORT = 42069
var peer = ENetMultiplayerPeer.new()
var game_ready := false
var all_player_ids := []
var max_players = 2:
	set(value):
		max_players = value
		# Aina kun arvo muuttuu, ajetaan tarkistus
		check_game_ready()


func host_game():
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	all_player_ids.append(1) # <--- hostin id
	check_game_ready() # Tämä lähettää signaalin (1) menu UI:lle 
	print("Hostaus alkanut")

func join_game(ip):
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer
	print("Yritetään liittyä: ", ip)

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Napataan kiinni kättelyvaiheen epäonnistuminen (esim. IP väärin tai portti kiinni)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id):
	# Tarkistetaan ylittyykö pelaajaraja
	# Palvelin tarkistaa rajan
	if all_player_ids.size() >= max_players:
		print("Peli on täynnä! Ilmoitetaan pelaajalle: ", id)
		# Lähetetään tieto VAIIN tälle uudelle pelaajalle ennen potkuja
		notify_server_full.rpc_id(id)
		
		# Pieni viive, jotta RPC-viesti ehtii perille ennen yhteyden katkeamista
		get_tree().create_timer(0.2).timeout.connect(func():
			peer.disconnect_peer(id)
		)
		return
	
	if not all_player_ids.has(id):
		all_player_ids.append(id)
		print("Pelaaja yhdistetty listaan: ", id)
	
	# katotaan onko kaikki joinannu
	check_game_ready()

@rpc("authority", "reliable")
func notify_server_full():
	print("Serveri ilmoitti: Peli on täynnä!")
	last_disconnect_reason = "SERVER_FULL"
	# Tässä vaiheessa voimme jo lähettää tiedon UI:lle
	connection_lost.emit("SERVER_FULL")

func _on_peer_disconnected(id):
	all_player_ids.erase(id)
	check_game_ready()

func _on_connection_failed():
	var error_code = peer.get_last_error()
	print("YHTEYS EPÄONNISTUI. Virhekoodi: ", error_code)
	# ENet-virhekoodit auttavat debuggauksessa
	connection_lost.emit("FAILED")

func _on_server_disconnected():
	# Jos syy on jo asetettu RPC:llä, käytetään sitä, muuten DISCONNECTED
	var final_reason = last_disconnect_reason if last_disconnect_reason != "GENERIC" else "DISCONNECTED"
	
	print("Lopullinen katkaisun syy: ", final_reason)
	
	# Nollataan tila seuraavaa kertaa varten
	last_disconnect_reason = "GENERIC"
	
	# Välitetään tieto valikolle
	connection_lost.emit(final_reason)


# TÄMÄ AJETAAN VAIN CLIENTEILLA (koska serveri kutsuu tätä RPC:llä)
@rpc("authority", "reliable")
func start_game_rpc():
	print("Client vastaanotti aloitusviestin!")
	_setup_game_world_locally()

func check_game_ready():
	if all_player_ids.size() == max_players:
		game_ready = true
	else:
		game_ready = false
	print("Game ready tila: ", game_ready, " (Pelaajia: ", all_player_ids.size(), "/", max_players, ")")
	
	# Lähetetään tieto uudesta määrästä käyttöliittymälle
	player_count_updated.emit(all_player_ids.size())

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
	
	# 4. Luodaan pelaajat
	for id in all_player_ids:
		main_node.add_player(id)

	# 5. Kerrotaan MapManagerille ketkä osallistuu (Vain serveri tekee spawnin)
	var map_container = main_node.get_node("MapContainer")

	if map_container.get_child_count() > 0:
		var current_map = map_container.get_child(0)
		var map_manager = current_map.get_node_or_null("MapManager")
		if map_manager:
			map_manager.setup(all_player_ids)

	# 6. Käynnistetään clientit
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
