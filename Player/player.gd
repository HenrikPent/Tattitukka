# Player.gd
extends Node3D

@onready var camera_rig = $CameraRig
var controlled_unit: Node3D = null

func _ready():
	# Asetetaan authority nimen perusteella
	set_multiplayer_authority(name.to_int())
	
	if is_multiplayer_authority():
			$CameraRig/Camera3D.current = true
			# Aloitetaan haku
			find_my_unit_loop()

func find_my_unit_loop():
	var my_id = multiplayer.get_unique_id()
	
	# Odotetaan hetki, että Spawner ehtii tehdä työnsä rauhassa
	await get_tree().create_timer(0.5).timeout 
	
	var units_node = get_node_or_null("/root/Main/Units")
	if not units_node:
		return

	# Etsitään unittia, kunnes se löytyy
	var my_unit = null
	while my_unit == null:
		my_unit = units_node.get_node_or_null(str(my_id))
		if my_unit:
			controlled_unit = my_unit
			$CameraRig.controlled_unit = my_unit
			print("Kamera lukittu unittiin: ", my_unit.name)
			break
		await get_tree().process_frame
