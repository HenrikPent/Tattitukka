#single 
extends Node

var ai_count = 1
var main_node: Node = null

func _ready():
	main_node = get_tree().root.get_node("Main")


func start_game(map_index: int):
	print("Aloitetaan Single Player...")

	if main_node == null:
		print("Main-nodea ei löytynyt!")
		return

	# 1️⃣ Offline peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	# 2️⃣ Ladataan kartta
	var seed_val = randi()
	main_node.load_map(map_index, seed_val)

	# ❗ ODOTA YKSI FRAME että mapin _ready() ehtii ajautua
	await get_tree().process_frame

	# 3️⃣ Lisää pelaaja
	main_node.add_player(1)

	# 4️⃣ Participants
	var participants = [1]
	for i in range(1, ai_count + 1):
		participants.append(-i)

	# 5️⃣ Hae MapManager dynaamisesti
	var map_container = main_node.get_node("MapContainer")

	if map_container.get_child_count() > 0:
		var current_map = map_container.get_child(0)
		var map_manager = current_map.get_node_or_null("MapManager")
		if map_manager:
			map_manager.setup(participants)

	# 6️⃣ UI
	if main_node.has_node("UI/TacticalMap"):
		main_node.get_node("UI/TacticalMap").setup(main_node.get_node("Units"))

	if main_node.has_node("UI/HelpUI"):
		main_node.get_node("UI/HelpUI").visible = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
