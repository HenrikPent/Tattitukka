extends Node3D


@export var gun: Node3D
@export var yaw_speed := 60.0
@export var pitch_speed := 60.0
@export var down_max_pitch := -40.0  # alas (negatiivinen)
@export var up_max_pitch := 10.0     # ylös (positiivinen)


func _process(delta: float) -> void:
	# 1. VAIN OHJAAJA LASKEE TAVOITTEET
	if is_multiplayer_authority() and get_parent().is_player_controlled:
		if not gun:
			return

		# 1️⃣ Suuntavektori barrelista kohti hiiren osumaa
		var target_pos = CameraData.hit_position
		var gun_global = gun.global_transform.origin
		var dir = (target_pos - gun_global).normalized()

		# 2️⃣ Pitch (ylös/alas)
		var horizontal_dist = sqrt(dir.x * dir.x + dir.z * dir.z)
		var base_pitch = atan2(dir.y, horizontal_dist)
		base_pitch = -base_pitch  # Godotin merkki ylös/alas

		# Smooth pitch
		var pitch_diff = base_pitch - gun.rotation.x
		gun.rotation.x += clamp(pitch_diff, -deg_to_rad(pitch_speed * delta), deg_to_rad(pitch_speed * delta))
		gun.rotation.x = clamp(gun.rotation.x, deg_to_rad(down_max_pitch), deg_to_rad(up_max_pitch))

		# 3️⃣ Yaw (vasen/oikea)
		var desired_yaw = atan2(-dir.x, -dir.z)
		var yaw_diff = wrapf(desired_yaw - global_rotation.y, -PI, PI)
		global_rotation.y += clamp(yaw_diff, -deg_to_rad(yaw_speed * delta), deg_to_rad(yaw_speed * delta))
