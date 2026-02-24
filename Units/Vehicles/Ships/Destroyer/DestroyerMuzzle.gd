extends Node3D

@export var projectile_type: String = "127mm"
@export var speed: float = 200.0
@export var fire_rate: float = 0.5

@onready var sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D # Varmista nimi!
@onready var flash: Node3D = $MuzzleFlash

var turret_control: Node = null
var gun_index: int = -1
var can_fire := true

func action_fire(shooter_id: int):
	if not can_fire: return
	can_fire = false
	
	var pos = global_position
	var dir = -global_transform.basis.z.normalized()
	
	var manager = get_node_or_null("/root/Main/ProjectileManager")
	if manager:
		manager.request_fire.rpc(projectile_type, pos, dir, shooter_id, speed)
		
		# Kutsutaan ääniefektiä kaikille (myös itselle)
		play_fire_effects.rpc()
	
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true

# Tämä suoritetaan kaikilla koneilla verkon yli
@rpc("any_peer", "call_local", "unreliable")
func play_fire_effects():
	# 1. ÄÄNI
	if sfx:
		sfx.pitch_scale = randf_range(0.95, 1.05)
		sfx.play()
	
	# 2. VÄLÄHDYS
	if flash:
		if flash is GPUParticles3D or flash is CPUParticles3D:
			flash.restart() # Käynnistää efektin alusta
			flash.emitting = true
		elif flash.has_method("play"):
			flash.play() # Jos se on esim. AnimationPlayer tai sprite-animaatio
