# MainMenu.gd
extends Control

@onready var host_panel: VBoxContainer = $HostPanel
@onready var join_panel: VBoxContainer = $JoinPanel
@onready var map_selector: OptionButton = $HostPanel/MapSelector
@onready var start_button: Button = $HostPanel/StartButton
@onready var ip_input: LineEdit = $JoinPanel/IP

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Varmista että menu toimii vaikka peli olisi pausella
	get_viewport().set_input_as_handled()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	host_panel.hide()
	join_panel.hide()
	start_button.disabled = true

func _on_host_pressed():
	host_panel.show()
	join_panel.hide()
	# Aloitetaan hostaus
	Multiplayer.host_game()

func _on_join_pressed():
	join_panel.show()
	host_panel.hide()

func _on_connect_button_pressed():
	var target_ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	Multiplayer.join_game(target_ip)
	# Piilotetaan menu, mutta hiiri pidetään vielä vapaana kunnes ladataan
	self.hide()

# MainMenu.gd
func _on_start_button_pressed():
	if multiplayer.is_server():
		# Haetaan valitun kartan indeksi (0, 1, 2...)
		var selected_map = map_selector.get_selected_id()
		Multiplayer.start_game(selected_map)


func _process(_delta):
	# Varmistetaan ensin, että verkko on pystyssä
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			start_button.disabled = not Multiplayer.game_ready
