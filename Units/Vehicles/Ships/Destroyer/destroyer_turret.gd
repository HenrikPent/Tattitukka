extends Node3D


@export var gun: Node3D
@export var muzzles: Array[Node3D] = [] # Vedä Muzzle-nodet tähän listaan editorissa
@export var yaw_speed := 60.0
@export var pitch_speed := 60.0
@export var up_max_pitch := 40.0  # ylös (negatiivinen)
@export var down_max_pitch := -10.0     # alas (positiivinen)


func _process(delta: float) -> void:
	# 1. VAIN OHJAAJA LASKEE TAVOITTEET
	if is_multiplayer_authority() and get_parent().is_player_controlled:
		if not gun:
			return

		# Suuntavektori barrelista kohti hiiren osumaa
		var target_pos = CameraData.hit_position
		var gun_global = gun.global_transform.origin
		var dir = (target_pos - gun_global).normalized()

		#  Pitch (ylös/alas)
		var horizontal_dist = sqrt(dir.x * dir.x + dir.z * dir.z)
		var base_pitch = atan2(dir.y, horizontal_dist)

		# Smooth pitch
		var pitch_diff = base_pitch - gun.rotation.x
		gun.rotation.x += clamp(pitch_diff, -deg_to_rad(pitch_speed * delta), deg_to_rad(pitch_speed * delta))
		gun.rotation.x = clamp(gun.rotation.x, deg_to_rad(down_max_pitch), deg_to_rad(up_max_pitch))

		# 3️⃣ Yaw (vasen/oikea)
		var desired_yaw = atan2(-dir.x, -dir.z)
		var yaw_diff = wrapf(desired_yaw - global_rotation.y, -PI, PI)
		global_rotation.y += clamp(yaw_diff, -deg_to_rad(yaw_speed * delta), deg_to_rad(yaw_speed * delta))


		# 2. AMMUNTA (Pelaajan input)
		if Input.is_action_pressed("fire"):
			fire_all_muzzles()


func fire_all_muzzles() -> void:
	var shooter_id = owner.get_multiplayer_authority()
	for muzzle in muzzles:
		# 1. Tarkistetaan onko piippuun määritetty lupajärjestelmä (TurretManagerilta)
		# muzzle.gun_index on se ID, jota TurretManager käyttää taulukossaan
		if muzzle.turret_control and muzzle.gun_index != -1:
			var permission = muzzle.turret_control.fire_permissions[muzzle.gun_index]
			
			# Jos lupa on 1, saa ampua. Jos se on 0, tykki on esim. latautumassa.
			if permission == 1:
				if muzzle.has_method("action_fire"):
					muzzle.action_fire(shooter_id)
		else:
			# Varajärjestelmä: jos TurretManageria ei ole, ammutaan silti
			muzzle.action_fire(shooter_id)
