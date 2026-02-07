# CameraRig.gd
extends Node3D

@export var rotate_speed := 0.15 # Hieman nopeampi tuntuu yleensä paremmalta
@export var zoom_speed := 2.0

var offset_distance := 5.0  # Alustetaan järkevään oletukseen
var rotation_x := 0.0
var rotation_y := 0.0

var controlled_unit: Node3D = null
var last_unit: Node3D = null # Käytetään tunnistamaan milloin unitti vaihtuu

func _unhandled_input(event: InputEvent) -> void:
	if not get_parent().is_multiplayer_authority():
		return
	
	if event is InputEventMouseMotion:
		rotation_y -= event.relative.x * rotate_speed
		rotation_x += event.relative.y * rotate_speed
		rotation_x = clamp(rotation_x, -85, 85)

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			offset_distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			offset_distance += zoom_speed

func _process(_delta: float) -> void:
	if controlled_unit == null:
		controlled_unit = get_parent().controlled_unit
		if controlled_unit == null: return

	# TARKISTUS: Jos unitti vaihtui (esim. sotilaasta laivaan), resetoidaan etäisyys
	if controlled_unit != last_unit:
		_on_unit_switched()
		last_unit = controlled_unit

	# 1. Haetaan unitin säädöt
	var unit_pivot = controlled_unit.get("cam_offset") if "cam_offset" in controlled_unit else Vector3(0, 1.5, 0)
	var min_dist = controlled_unit.get("cam_min_dist") if "cam_min_dist" in controlled_unit else 2.0
	var max_dist = controlled_unit.get("cam_max_dist") if "cam_max_dist" in controlled_unit else 100.0
	
	# 2. Pidetään huoli rajoista
	offset_distance = clamp(offset_distance, min_dist, max_dist)

	# 3. Lasketaan paikka
	var quat = Quaternion.from_euler(Vector3(deg_to_rad(-rotation_x), deg_to_rad(rotation_y), 0))
	# Huom: Käytetään positiivista Z:taa, koska katsomme -Z suuntaan (look_at hoitaa loput)
	var rotated_offset = quat * Vector3(0, 0, offset_distance)

	var target_center = controlled_unit.global_position + unit_pivot
	global_position = target_center + rotated_offset

	# 4. Katsotaan kohteeseen
	look_at(target_center, Vector3.UP)

	# 5. Päivitetään CameraData
	var ray_direction = -global_transform.basis.z.normalized()
	CameraData.hit_position = global_position + ray_direction * 1000.0

# Funktio joka säästää hiiren rullaamiselta unittia vaihtaessa
func _on_unit_switched():
	if "cam_min_dist" in controlled_unit:
		# Asetetaan kamera "sopivaan" alkupisteeseen (min + 20% välivaraa)
		var d_min = controlled_unit.cam_min_dist
		var d_max = controlled_unit.cam_max_dist
		offset_distance = d_min + (d_max - d_min) * 0.2
		print("Kamera resetoitu yksikölle: ", controlled_unit.name)
