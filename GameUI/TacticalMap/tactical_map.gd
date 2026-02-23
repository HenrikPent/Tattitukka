extends Control

@export var world_size := 5000.0 # Pelialueen koko (5000m x 5000m)
@export var map_size := 600.0   # Kartta-alueen koko pikseleinä (esim. Background-noden koko)

var units_node: Node3D = null
# Pidetään kirjaa: { unit_node: icon_node }
var icon_map = {}

var selected_unit: Node3D = null


func setup(n: Node3D):
	units_node = n

func _process(_delta):
	# Jos units_node on null, yritetään hakea se polulla (varmistus)
	if units_node == null:
		units_node = get_node_or_null("/root/Main/Units")
	
	if not visible or units_node == null:
		return
	
	_update_map()
	queue_redraw()

func _update_map():
	# Siivotaan kuolleet yksiköt pois kartalta
	for unit in icon_map.keys():
		if not is_instance_valid(unit):
			icon_map[unit].queue_free()
			icon_map.erase(unit)
			if selected_unit == unit:
				selected_unit = null
			continue
	
	# 1. Haetaan kaikki yksiköt
	var units = units_node.get_children()
	
	# 2. Päivitetään tai luodaan ikonit
	for unit in units:
		if not icon_map.has(unit):
			_create_icon_for_unit(unit)
		
		_update_icon_position(unit)


#----------------------------------------------------------------#
#-    Koordinaattimuutokset 3D maailman ja 2D kartan välillä    -#
#----------------------------------------------------------------#
func world_to_map(world_pos: Vector3) -> Vector2:
	# 1. Normalisoidaan sijainti välille -0.5 ... 0.5 (jos maailman nolla on keskellä)
	var x = world_pos.x / world_size
	var z = world_pos.z / world_size
	
	# 2. Siirretään välille 0.0 ... 1.0 (koska UI alkaa yläkulmasta)
	# Huom: 3D:n Z-akseli on 2D:n Y-akseli
	var map_pos = Vector2(x + 0.5, z + 0.5)
	
	# 3. Skaalataan kartan pikselikokoon
	return map_pos * map_size

func map_to_world(map_pos: Vector2) -> Vector3:
	# 1. Muutetaan pikselit välille 0.0 ... 1.0
	var normalized_pos = map_pos / map_size
	
	# 2. Muutetaan välille -0.5 ... 0.5
	var world_x = (normalized_pos.x - 0.5) * world_size
	var world_z = (normalized_pos.y - 0.5) * world_size
	
	return Vector3(world_x, 0, world_z)


#----------------------------------------------------------------#
#-                         ikonit                               -#
#----------------------------------------------------------------#
func _create_icon_for_unit(unit):
	var icon = ColorRect.new()
	icon.custom_minimum_size = Vector2(10, 10) # Varmistetaan koko
	icon.size = Vector2(10, 10)
	
	# Lisätään tämä printtaus, jotta näet konsolista luodaanko ikoneita
	print("Luodaan ikoni yksikölle: ", unit.name, " tiimi: ", unit.get("team_id"))
	
	# Väri team_id:n mukaan
	if unit.get("team_id") == multiplayer.get_unique_id():
		icon.color = Color.CYAN
	elif unit.get("team_id") < 0:
		icon.color = Color.GOLDENROD # AI
	else:
		icon.color = Color.RED # Vihollinen
	
	# tämä estää sen ettei ikonin päälle klikkaammine syö klikkausta. klikkaus siis lasketaan karttapohajasta:
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	$IconLayer.add_child(icon)
	icon_map[unit] = icon


func _update_icon_position(unit):
	var icon = icon_map[unit]
	var map_pos = world_to_map(unit.global_position)
	
	# Asetetaan paikka (vähennetään puolet koosta, jotta ikoni on keskellä pistettä)
	icon.position = map_pos - (icon.size / 2)
	
	# (Valinnainen) Käännetään ikoni vastaamaan laivan suuntaa
	icon.rotation = -unit.global_transform.basis.get_euler().y


#--------------------------------------------------------------#
# --             Unittien ohjaus klikkailemalla              --#
#--------------------------------------------------------------#
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)

func _handle_left_click(click_pos: Vector2):
	var closest_unit = null
	var min_dist = 30.0 # Kasvatetaan hieman osumisaluetta (30 pikseliä)
	
	for unit in icon_map.keys():
		var icon = icon_map[unit]
		# Käytetään icon.positionia suoraan, jos IconLayer on 0,0 kohdassa
		var icon_center = icon.position + (icon.size / 2.0)
		var dist = click_pos.distance_to(icon_center)
		
		if dist < min_dist:
			# --- TÄMÄ ON UUSI TARKISTUS ---
			var unit_team = unit.get("team_id")
			var my_id = multiplayer.get_unique_id()
			
			# Salli valinta vain jos tiimi on oma (my_id) 
			# tai jos haluat ohjata myös "neutraaleja" AI-liittolaisia (esim. team_id < 0)
			if unit_team == my_id:
				closest_unit = unit
				min_dist = dist
			else:
				print("Et voi valita vihollisen yksikköä!")
	
	selected_unit = closest_unit
	
	if selected_unit:
		print("VALITTU: ", selected_unit.name)
		_highlight_selected_icon()
		
		# Pyydetään palvelinta vaihtamaan pelaajan hallitsema yksikkö tähän klikattuun
		PlayerManager.request_possession.rpc_id(1, selected_unit.get_path())
	
	else:
		print("Klikattu tyhjää pisteessä: ", click_pos)


func _handle_right_click(click_pos: Vector2):
	if not selected_unit:
		return

	# 1. Katsotaan osuiko oikea klikkaus johonkin ikoniin
	var clicked_unit = null
	var min_dist = 30.0
	
	for unit in icon_map.keys():
		if unit == selected_unit: continue # Ei voi seurata itseään
		
		var icon = icon_map[unit]
		var icon_center = icon.position + (icon.size / 2.0)
		if click_pos.distance_to(icon_center) < min_dist:
			clicked_unit = unit
			break
	
	# 2. Toiminta osuman perusteella
	if clicked_unit:
		var my_id = multiplayer.get_unique_id()
		var target_team = clicked_unit.get("team_id")
		
		if target_team == my_id or target_team < 0:
			# YSTÄVÄ -> SEURAA
			if selected_unit.has_method("set_follow_target"):
				selected_unit.set_follow_target(clicked_unit)
				print("KOMENTO: Seuraa liittolaista ", clicked_unit.name)
		else:
			# VIHÖLLINEN -> HYÖKKÄÄ (voidaan toteuttaa myöhemmin)
			print("KOMENTO: Hyökkää vihollisen kimppuun! (Toteuttamatta)")
	
	else:
		# TYHJÄ MERI -> LIIKU JA LOPETA SEURAAMINEN
		var target_3d = map_to_world(click_pos)
		if selected_unit.has_method("set_ai_target"):
			# Nollataan seuranta, jos annetaan uusi liikkumispiste
			if "follow_target" in selected_unit:
				selected_unit.follow_target = null 
			selected_unit.set_ai_target(target_3d)
	
	# Poistetaan valinta käskyn jälkeen
	_clear_selection()



func _highlight_selected_icon():
	# Nollataan muiden värit ensin (valinnainen, jos haluat vain yhden kerrallaan)
	for unit in icon_map.keys():
		var icon = icon_map[unit]
		# Palautetaan perusväri (tämä on vähän purkka-ratkaisu, 
		# parempi olisi tallentaa alkuperäinen väri)
		if unit.get("team_id") == multiplayer.get_unique_id():
			icon.color = Color.CYAN
		else:
			icon.color = Color.RED
			
	# Korostetaan valittu
	if selected_unit and icon_map.has(selected_unit):
		icon_map[selected_unit].color = Color.WHITE

func _clear_selection():
	if selected_unit:
		_reset_icon_color(selected_unit)
		selected_unit = null
	print("Valinta tyhjennetty")

func _reset_icon_color(unit: Node3D):
	# Varmistetaan, että yksikkö on yhä olemassa ja sille on ikoni
	if is_instance_valid(unit) and icon_map.has(unit):
		var icon = icon_map[unit]
		var my_id = multiplayer.get_unique_id()
		var team = unit.get("team_id")
		
		# Palautetaan alkuperäinen värikoodaus
		if team == my_id:
			icon.color = Color.CYAN
		elif team < 0:
			icon.color = Color.GOLDENROD
		else:
			icon.color = Color.RED



func _draw():
	if units_node == null:
		return

	var my_id = multiplayer.get_unique_id()

	for unit in icon_map.keys():
		if not is_instance_valid(unit): continue
		
		# Piirretään viivoja vain omille yksiköille (tai kaikille, jos haluat debugata)
		if unit.get("team_id") != my_id: continue

		var start_pos = world_to_map(unit.global_position)
		var end_pos: Vector2
		var line_color: Color

		# Tarkistetaan, mitä laiva on tekemässä
		if is_instance_valid(unit.get("follow_target")):
			# SEURAA (Vaaleanvihreä)
			end_pos = world_to_map(unit.follow_target.global_position)
			line_color = Color.GREEN_YELLOW
		elif unit.ai_target_pos != Vector3.ZERO:
			# LIIKKUU (Harmaa)
			end_pos = world_to_map(unit.ai_target_pos)
			line_color = Color.GRAY
		elif is_instance_valid(unit.get("attack_target")):
			# HYÖKKÄÄ (punainen)
			end_pos = world_to_map(unit.attack_target.global_position)
			line_color = Color.RED
		else:
			continue # Ei kohdetta, ei piirretä viivaa

		# Piirretään viiva (alkupiste, loppupiste, väri, paksuus, pehmennys)
		draw_line(start_pos, end_pos, line_color, 2.0, true)
		
		# (Valinnainen) Piirretään pieni pallo viivan päähän kohteeksi
		draw_circle(end_pos, 3.0, line_color)
