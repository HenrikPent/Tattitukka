# MainMenu.gd
extends Control

# Menun eri valikot omina tiloinaan, jokaisella tilalla oma container(control tai box container) jonka 
# sisällä kaikki valikon jutut, napit yms. go_to_state funktiolla liikutaan tilojen välillä


# Määritellään tilat nimillä
enum MenuState { MAIN, SINGLE, MULTI, HOST, JOIN, FULL }

var current_state = MenuState.MAIN


@onready var main_panel: Control = $Main
@onready var multiplayer_button: Button = $Main/Multiplayer
@onready var singleplayer_button: Button = $Main/Singleplayer


@onready var multiplayer_panel: Control = $Multiplayer
@onready var host_button: Button = $Multiplayer/Host
@onready var join_button: Button = $Multiplayer/Join


@onready var host_panel: Control = $HostPanel
@onready var map_selector: OptionButton = $HostPanel/MapSelector
@onready var start_multi_button: Button = $HostPanel/StartMulti
@onready var joined_count_label: Label = $HostPanel/JoinedCount # Varmista polku


@onready var join_panel: Control = $JoinPanel
@onready var ip_input: LineEdit = $JoinPanel/IP
@onready var connect_button: Button = $JoinPanel/ConnectButton
@onready var joined_count: Label = $HostPanel/JoinedCount
@onready var spin_box: SpinBox = $HostPanel/SpinBox
@onready var full_panel: Control = $GameFull


@onready var singleplayer_panel: Control = $Singleplayer
@onready var map_selector_2: OptionButton = $Singleplayer/MapSelector2


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Varmista että menu toimii vaikka peli olisi pausella
	get_viewport().set_input_as_handled()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Alustetaan näkymä
	go_to_state(MenuState.MAIN)
	start_multi_button.disabled = true
	
	# Yhdistetään Multiplayer-singletonin signaali tähän skriptiin
	Multiplayer.player_count_updated.connect(_on_player_count_changed)
	
	# Asetetaan alkutilanne (1/X)
	_on_player_count_changed(Multiplayer.all_player_ids.size())
	
	
	Multiplayer.connection_lost.connect(_on_connection_lost)

func _on_connection_lost():
	# Tuodaan valikko takaisin näkyviin ja palataan pääsivulle
	self.show()
	go_to_state(MenuState.FULL)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_player_count_changed(new_count: int):
	if new_count == 1:
		joined_count_label.text = "1 (Host)"
	else:
		joined_count_label.text = str(new_count)


# Yleinen funktio tilan vaihtoon
func go_to_state(new_state):
	# Piilotetaan kaikki aluksi, jotta ei jää päällekkäisyyksiä
	main_panel.hide()
	singleplayer_panel.hide()
	multiplayer_panel.hide()
	host_panel.hide()
	join_panel.hide()
	full_panel.hide()
	
	current_state = new_state
	
	# Paljastetaan oikea osa case-rakenteella (match)
	match current_state:
		MenuState.MAIN: main_panel.show()
		MenuState.SINGLE: singleplayer_panel.show()
		MenuState.MULTI: multiplayer_panel.show()
		MenuState.HOST: host_panel.show()
		MenuState.JOIN: join_panel.show()
		MenuState.FULL: full_panel.show()

func _on_multiplayer_pressed():
	go_to_state(MenuState.MULTI)

func _on_singleplayer_pressed():
	go_to_state(MenuState.SINGLE)

func _on_host_pressed():
	go_to_state(MenuState.HOST)
	# Aloitetaan hostaus
	Multiplayer.host_game()

func _on_spin_box_value_changed(value: float):
	# Päivitetään tieto singletoniin aina kun lukua muutetaan
	Multiplayer.max_players = int(value)

func _on_join_pressed():
	go_to_state(MenuState.JOIN)

#tää on nappi jolla pääsee "server full" ruudusta pois
func _on_button_pressed() -> void: 
	go_to_state(MenuState.MAIN) 

func _on_connect_button_pressed():
	var target_ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	Multiplayer.join_game(target_ip)
	# Piilotetaan menu, mutta hiiri pidetään vielä vapaana kunnes ladataan
	self.hide()

func _on_start_multi_pressed():
	if multiplayer.is_server():
		# Haetaan valitun kartan indeksi (0, 1, 2...)
		var selected_map = map_selector.get_selected_id()
		Multiplayer.start_game(selected_map)


func _on_start_single_pressed():
	## 1. Haetaan valitun kartan indeksi OptionButtonista
	var selected_map = map_selector_2.get_selected_id()
	
	# 2. Etsitään Main-node (jos MainMenu on sen lapsi, käytä get_parent())
	# Jos MainMenu on eri skenessä, voit käyttää esim. get_tree().root.get_node("Main")
	var main_node = get_parent() 
	
	if main_node and main_node.has_method("start_singleplayer"):
		main_node.start_singleplayer(selected_map)
		# 3. Piilotetaan valikko
		self.hide()
	else:
		print("VIRHE: Main-nodea ei löytynyt tai siinä ei ole start_singleplayer-funktiota!")


func _on_back_button_pressed():
	match current_state:
		MenuState.SINGLE, MenuState.MULTI:
			go_to_state(MenuState.MAIN)
		MenuState.HOST, MenuState.JOIN:
			go_to_state(MenuState.MULTI)
		MenuState.MAIN:
			# Tässä voisi vaikkapa kysyä lopetetaanko peli
			pass



func _process(_delta):
	# TÄMÄ RIVI ESTÄÄ KAATUMISEN:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	# tarkistetaan yhteys
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	
	
	if multiplayer.is_server():
		start_multi_button.disabled = not Multiplayer.game_ready


func _on_kyyrymeri_pressed():
	var main_node = get_parent()
	if main_node and main_node.has_method("start_singleplayer"):
		main_node.start_singleplayer(0)
		# 3. Piilotetaan valikko
		self.hide()
	else:
		print("VIRHE: Main-nodea ei löytynyt tai siinä ei ole start_singleplayer-funktiota!")


func _on_random_mappi_pressed() -> void:
	var main_node = get_parent()
	if main_node and main_node.has_method("start_singleplayer"):
		main_node.start_singleplayer(1)
		# 3. Piilotetaan valikko
		self.hide()
	else:
		print("VIRHE: Main-nodea ei löytynyt tai siinä ei ole start_singleplayer-funktiota!")
