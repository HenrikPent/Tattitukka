#turret
extends Node3D

@export var gun: Node3D
@export var yaw_speed := 60.0
@export var pitch_speed := 60.0
@export var down_max_pitch := -40.0  # alas (negatiivinen)
@export var up_max_pitch := 10.0     # ylös (positiivinen)

@export var sync_yaw: float = 0.0   # näillä saatiin tykit osottaan molemilla 
@export var sync_pitch: float = 0.0 # pelaajilla samaan suuntaan

# Lisää nämä uudet exportit (voit poistaa vanhat min/max jos haluat)
@export_group("Kielletty Sektori")
@export var forbidden_center := 0.0  # komentosilta on 0
@export var forbidden_width := 60.0   # 60 asteen siivu (eli -30 ... 30)

var debug_timer := 0.0

func _process(delta: float) -> void:

	if is_multiplayer_authority():

		var target_pos = CameraData.hit_position
		var local_target = to_local(target_pos)

		# =====================================================
		# 1. TARGET YAW (absoluuttinen kulma)
		# =====================================================
		var target_yaw = atan2(local_target.x, local_target.z)
		target_yaw = wrapf(target_yaw, -PI, PI)

		var current_yaw = sync_yaw


		# =====================================================
		# 2. SELVITETÄÄN KUMMALLA PUOLELLA LAAIVAA OLLAAN
		# =====================================================
		# forbidden_center = runkolinja (0 = keula / 180 = perä)
		# Tätä käytetään jakamaan alus vasen/oikea

		var current_deg = rad_to_deg(current_yaw)
		var target_deg  = rad_to_deg(target_yaw)

		var diff_current = wrapf(current_deg - forbidden_center, -180, 180)
		var diff_target  = wrapf(target_deg  - forbidden_center, -180, 180)

		var current_side = sign(diff_current) # -1 = vasen, +1 = oikea
		var target_side  = sign(diff_target)


		# =====================================================
		# 3. LASKETAAN LYHYIN KULMAERO NORMAALISTI
		# =====================================================
		var yaw_diff = wrapf(target_yaw - current_yaw, -PI, PI)


		# =====================================================
		# 4. KIERTOSUUNNAN PÄÄTÖS
		# =====================================================
		# Jos target samalla puolella → normaali lyhin reitti
		# Jos eri puolella → pakotetaan pitkä reitti

		if current_side != 0 and target_side != 0:
			if current_side != target_side:
				# Käännetään kulmaero → pitkä reitti
				if yaw_diff > 0:
					yaw_diff -= TAU
				else:
					yaw_diff += TAU


		# =====================================================
		# 5. LIIKE KOHTI TARGETTIA
		# =====================================================
		var max_step = deg_to_rad(yaw_speed) * delta

		yaw_diff = clamp(yaw_diff, -max_step, max_step)

		sync_yaw += yaw_diff
		sync_yaw = wrapf(sync_yaw, -PI, PI)


		# =====================================================
		# 6. FORBIDDEN SECTOR HARD LIMIT
		# =====================================================
		var half = forbidden_width / 2.0
		var new_deg = rad_to_deg(sync_yaw)

		var diff_to_forbidden = wrapf(new_deg - forbidden_center, -180, 180)

		if abs(diff_to_forbidden) < half:

			if diff_to_forbidden > 0:
				new_deg = forbidden_center + half
			else:
				new_deg = forbidden_center - half

			sync_yaw = deg_to_rad(new_deg)


		# =====================================================
		# 7. PITCH (ennallaan)
		# =====================================================
		if gun:
			var piippu_local = gun.get_parent().to_local(target_pos)
			var dist_3d = piippu_local.length()

			if dist_3d > 0.1:
				var target_pitch_angle = asin(piippu_local.y / dist_3d)

				target_pitch_angle = clamp(
					target_pitch_angle,
					deg_to_rad(down_max_pitch),
					deg_to_rad(up_max_pitch)
				)

				sync_pitch = move_toward(
					sync_pitch,
					-target_pitch_angle,
					deg_to_rad(pitch_speed) * delta
				)


	# =========================================================
	# APPLY
	# =========================================================
	rotation.y = sync_yaw

	if gun:
		gun.rotation.x = sync_pitch
