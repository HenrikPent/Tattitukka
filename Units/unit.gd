# Unit.gd
extends Node3D

@export var speed: float = 10.0
@export var rotation_speed: float = 10.0

func _physics_process(delta):
	if not is_multiplayer_authority():
		return

	# 1. Haetaan input
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	if input_dir == Vector2.ZERO:
		return

	# 2. Haetaan kameran suunta (maailmassa)
	# Etsitään pelaajan kamera (CameraRig on Player-noden lapsi)
	var camera = get_viewport().get_camera_3d()
	var move_dir = Vector3.ZERO
	
	if camera:
		# Lasketaan suunta kameran tasossa (ei huomioida ylös/alas katsomista)
		var cam_forward = -camera.global_transform.basis.z
		var cam_right = camera.global_transform.basis.x
		cam_forward.y = 0
		cam_right.y = 0
		move_dir = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
	else:
		# Fallback jos kameraa ei löydy
		move_dir = Vector3(input_dir.x, 0, input_dir.y).normalized()

	# 3. Liikutetaan unittia
	global_position += move_dir * speed * delta

	# 4. Käännetään unitti katsomaan liikesuuntaan
	if move_dir.length() > 0.01:
		var target_quat = Quaternion(Basis.looking_at(move_dir, Vector3.UP))
		global_transform.basis = Basis(Quaternion(global_transform.basis).slerp(target_quat, rotation_speed * delta))




func _enter_tree():
	# Haetaan authority nimen perusteella (koska annoimme nimeksi ID:n)
	var id = name.to_int()
	if id > 0:
		set_multiplayer_authority(id)
		print("Unit ", id, " authority asetettu _enter_tree:ssä")


func _ready():
	# Otetaan synkronointi pois päältä aluksi
	var synchro = get_node_or_null("MultiplayerSynchronizer")
	if synchro:
		synchro.public_visibility = false # Ei huudeta muille vielä
	
	# Odotetaan, että pöly laskeutuu (0.5s on varma LAN-verkossa)
	await get_tree().create_timer(0.5).timeout
	
	# Nyt kun kaikki on varmasti valmista, kytketään päälle
	if synchro:
		synchro.public_visibility = true
		if is_multiplayer_authority():
			synchro.set_visibility_for(0, true)
