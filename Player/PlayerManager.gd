#player manager
extends Node

# Kirjanpito: { pelaaja_id: laiva_node }
var controlled_units = {}
var controlled_unit: Node3D = null


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

	# Vapautetaan vanha unit takaisin AI:lle
	if controlled_units.has(player_id):
		var old_unit = controlled_units[player_id]
		if is_instance_valid(old_unit):
			old_unit.is_player_controlled = false
			old_unit.set_multiplayer_authority(1)
			# Kerrotaan muillekin että tämä unitti vapautui AI:lle (ID 1)
			_update_controlled_unit_list.rpc(0, old_unit.get_path()) # 0 p_id:lle voi merkitä vapautusta
	
	# Otetaan uusi unit haltuun
	new_unit.set_multiplayer_authority(player_id)
	new_unit.is_player_controlled = true
	
	# Päivitetään lista kaikille, jotta Player.gd löytää uuden yksikön
	_update_controlled_unit_list.rpc(player_id, new_unit.get_path())

# 3. SYNKRONOINTI: Päivitetään tieto kaikille klienteille
@rpc("authority", "call_local", "reliable")
func _update_controlled_unit_list(p_id: int, u_path: NodePath):
	var unit = get_node_or_null(u_path)
	if unit:
		controlled_units[p_id] = unit
		
		# TÄMÄ RIVI PUUTTUU:
		# Asetetaan yksikön authority vastaamaan uutta omistajaa jokaisen clientin pelissä
		unit.set_multiplayer_authority(p_id) 
		
		if p_id == multiplayer.get_unique_id():
			controlled_unit = unit
			unit.is_player_controlled = true # Varmistetaan että tämä on päällä paikallisesti
			print("Paikallinen ohjaus asetettu yksikölle: ", unit.name)

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
	
	# Haetaan kaikki omat yksiköt
	var my_units = units_node.get_children().filter(func(u): return u.get("team_id") == my_id)
	if my_units.size() < 1: return
	
	var current_unit = controlled_units.get(my_id)
	var current_index = my_units.find(current_unit)
	
	# Lasketaan seuraava indeksi
	var next_index = (current_index + direction) % my_units.size()
	if next_index < 0: next_index = my_units.size() - 1
	
	# Pyydetään palvelinta vaihtamaan yksikkö
	request_possession.rpc_id(1, my_units[next_index].get_path())
