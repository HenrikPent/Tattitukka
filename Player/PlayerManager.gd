#player manager
extends Node

# Kirjanpito: { pelaaja_id: laiva_node }
var controlled_units = {}
var controlled_unit: Node3D = null

func _process(_delta: float) -> void:
	# Pidetään paikallinen controlled_unit -muuttuja puhtaana
	if controlled_unit != null and not is_instance_valid(controlled_unit):
		controlled_unit = null


# 1. PYYNTÖ: Pelaaja pyytää päästä laivaan (RPC-kutsu palvelimelle)
@rpc("any_peer", "call_local", "reliable")
func request_possession(unit_path: NodePath):
	if not multiplayer.is_server(): return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var unit = get_node_or_null(unit_path)
	
	# Tarkistetaan kuuluuko yksikkö pelaajan tiimiin
	if unit and unit.get("team_id") == sender_id:
		_perform_switch(sender_id, unit)

# 2. TOTEUTUS: Palvelin vaihtaa oikeudet
func _perform_switch(player_id: int, new_unit: Node3D):
	if not multiplayer.is_server(): return

	# --- VANHAN YKSIKÖN VAPAUTUS ---
	if controlled_units.has(player_id):
		var old_unit = controlled_units[player_id]
		if is_instance_valid(old_unit):
			# TÄRKEÄÄ: Asetetaan authority takaisin palvelimelle (1) ja pois pelaajalta
			old_unit.set_multiplayer_authority(1)
			old_unit.is_player_controlled = false
			# Päivitetään muille clientteille, että tämä unitti on nyt AI (p_id 0 tai 1)
			_update_controlled_unit_list.rpc(0, old_unit.get_path())
	
	# --- UUDEN YKSIKÖN HALTUUNOTTO ---
	new_unit.set_multiplayer_authority(player_id)
	new_unit.is_player_controlled = true
	
	# Päivitetään lista kaikille
	_update_controlled_unit_list.rpc(player_id, new_unit.get_path())

# 3. SYNKRONOINTI: Päivitetään tieto kaikille klienteille
@rpc("authority", "call_local", "reliable")
func _update_controlled_unit_list(p_id: int, u_path: NodePath):
	var unit = get_node_or_null(u_path)
	
	# --- TURVALLINEN SIIVOUS ---
	var dead_ids = []
	for key in controlled_units.keys():
		if not is_instance_valid(controlled_units[key]):
			dead_ids.append(key)
	
	for id in dead_ids:
		controlled_units.erase(id)
	
	if p_id == 0:
		# Yksikkö vapautui AI:lle
		unit.set_multiplayer_authority(1) # AI on aina palvelimen (1) alla
		unit.is_player_controlled = false
		# Poistetaan vanha kytkös listasta jos sellainen oli
		for key in controlled_units.keys():
			if controlled_units[key] == unit:
				controlled_units.erase(key)
	else:
		# Yksikkö meni pelaajalle
		controlled_units[p_id] = unit
		unit.set_multiplayer_authority(p_id)
		
		# Jos minä olen se, joka sai tämän yksikön
		if p_id == multiplayer.get_unique_id():
			controlled_unit = unit
			unit.is_player_controlled = true
		else:
			# Jos joku muu sai tämän yksikön, se ei ole minun AI:ni eikä pelaajani
			unit.is_player_controlled = true 
			# (Tämä pidetään true:na, jotta _physics_process ei aja AI-logiikkaa muilla kuin authoritylla)

# --- NÄPPÄIMET 1 JA 2 ---
func _unhandled_input(event: InputEvent):
	# Vain authority (paikallinen pelaaja) saa lähettää näppäinkomentoja
	if not is_multiplayer_authority(): return
	
	if event.is_action_pressed("unit_next"):
		_cycle_units(1)
	elif event.is_action_pressed("unit_prev"):
		_cycle_units(-1)

func _cycle_units(direction: int):
	var my_id = multiplayer.get_unique_id()
	var units_node = get_node_or_null("/root/Main/Units")
	if not units_node: return
	
	# 1. Suodatetaan VAIN elossa olevat ja oikean tiimin yksiköt
	var my_units = units_node.get_children().filter(func(u): 
		return is_instance_valid(u) and u.get("team_id") == my_id
	)
	
	if my_units.size() < 1: 
		controlled_unit = null
		return
	
	# 2. Haetaan nykyinen yksikkö turvallisesti
	var current_unit = controlled_units.get(my_id)
	
	# Jos nykyinen unitti on kuollut, asetetaan se nulliksi find-operaatiota varten
	if not is_instance_valid(current_unit):
		current_unit = null
	
	# 3. Etsitään indeksi
	var current_index = my_units.find(current_unit)
	
	# Jos nykyistä unittia ei löytynyt (oli esim. kuollut), aloitetaan nollasta
	if current_index == -1:
		current_index = 0
	
	# 4. Lasketaan seuraava indeksi
	var next_index = (current_index + direction) % my_units.size()
	if next_index < 0: next_index = my_units.size() - 1
	
	# 5. Varmistetaan vielä kerran kohteen validiteetti ennen RPC-kutsua
	var target_unit = my_units[next_index]
	if is_instance_valid(target_unit):
		request_possession.rpc_id(1, target_unit.get_path())
