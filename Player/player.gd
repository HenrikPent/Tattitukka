# Player.gd
extends Node3D

@onready var camera_rig = $CameraRig
var controlled_unit: Node3D = null

func _ready():
	set_multiplayer_authority(name.to_int())
	
	if is_multiplayer_authority():
		$CameraRig/Camera3D.current = true
		# Ei etsitä nimen perusteella, vaan kytkeydytään manageriin
		sync_with_manager()

func sync_with_manager():
	var my_id = multiplayer.get_unique_id()
	
	while true:
		# Tarkistetaan onko managerilla jo tieto meidän yksiköstä
		if UnitManager.controlled_units.has(my_id):
			var unit = UnitManager.controlled_units[my_id]
			if is_instance_valid(unit):
				controlled_unit = unit
				camera_rig.controlled_unit = unit
				# Jos kamera on jo kerran lukittu, voimme lopettaa loopin 
				# TAI jättää tämän päälle, jos haluat että kamera seuraa vaihtoa automaattisesti
		
		await get_tree().create_timer(0.2).timeout
