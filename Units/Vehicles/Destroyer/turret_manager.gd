extends Node

@export var guns: Array[Node] = []      # kaikki gun-node
@export var fire_interval: float = 0.3

var fire_permissions: Array[int] = []
var current_index := 0

func _ready():
	if guns.is_empty():
		return

	# luodaan lupa-array (aluksi kaikki 0)
	fire_permissions.resize(guns.size())
	for i in fire_permissions.size():
		fire_permissions[i] = 0

	# annetaan eka vuoro
	fire_permissions[0] = 1

	# kerrotaan jokaiselle gunille sen indeksi ja manager
	for i in guns.size():
		guns[i].gun_index = i
		guns[i].turret_control = self

	# timer vuorotteluun
	var t := Timer.new()
	t.wait_time = fire_interval
	t.autostart = true
	add_child(t)
	t.timeout.connect(_next_turn)

func _next_turn():
	# nollaa kaikki
	for i in fire_permissions.size():
		fire_permissions[i] = 0

	# seuraava saa luvan
	current_index = (current_index + 1) % fire_permissions.size()
	fire_permissions[current_index] = 1
