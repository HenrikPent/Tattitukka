extends Node3D

@export var rotation_speed: float = 2.0



func _physics_process(delta):
	# Vain laivan omistaja ohjaa tykkejä
	if not is_multiplayer_authority():
		return
	
	var target_pos = CameraData.hit_position
	
	# Lasketaan suunta kohteeseen
	var direction = (target_pos - global_position).normalized()
	
	# Horisontaalinen kääntyminen (Y-akseli)
	# Käytetään slerp-kääntymistä, jotta tykki ei käänny välittömästi
	var target_basis = Basis.looking_at(direction, Vector3.UP)
	var target_quat = target_basis.get_rotation_quaternion()
	
	# Muutetaan vain Y-rotaatiota tornille
	var current_quat = global_transform.basis.get_rotation_quaternion()
	var next_quat = current_quat.slerp(target_quat, rotation_speed * delta)
	
	# Jos haluat rajoittaa tornin kääntymään vain Y-akselilla:
	var euler = next_quat.get_euler()
	global_rotation.y = euler.y
