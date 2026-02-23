extends Node3D

@export var fire_rate: float = 1.0
@export var muzzle: Node3D
@export var muzzle_flash: GPUParticles3D
@export var fire_sound: AudioStreamPlayer3D

var turret_control: Node = null
var gun_index: int = -1
var can_fire := true


func fire() -> void:
	if not can_fire:
		return
	if turret_control == null:
		return
	if turret_control.fire_permissions[gun_index] == 0:
		return


	if muzzle_flash:
		muzzle_flash.restart()
		muzzle_flash.emitting = true

	# --- Ääni ---
	if fire_sound:
		fire_sound.play()

	can_fire = false
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return  # ei aktiivisen veneen tykki → ei tee mitään

	if Input.is_action_pressed("fire"):
		fire()
