#Projectile manager
extends Node

@export var scenes : Dictionary = {
	"127mm": preload("res://Projectiles/Shells/127_mm.tscn")
}

# Lisää nämä managerin alkuun
@export var effect_scenes : Dictionary = {
	"Impact_127mm": preload("res://Projectiles/Effects/127mm/127mmImpact.tscn"),
	"water_splash": preload("res://Projectiles/Effects/WaterSplash/water_splash.tscn")
}

# Tämä funktio on se, jota kaikki kutsuvat (niin AI kuin pelaaja)
@rpc("any_peer", "call_local", "reliable")
func request_fire(type: String, spawn_pos: Vector3, spawn_dir: Vector3, shooter_id: int, speed: float):
	# Vain palvelin spawnaa objektin, MultiplayerSpawner hoitaa loput
	if not multiplayer.is_server(): return
	
	if not scenes.has(type): return
	
	var p = scenes[type].instantiate()
	# Etsitään säiliö ammusten säilytykseen (esim. Main-skenessä oleva Node)
	var container = get_tree().root.find_child("Projectiles", true, false)
	
	if container:
		container.add_child(p, true) # true = synkronoi nimi verkon yli
		p.global_position = spawn_pos
		
		# Asetetaan ammuksen fysiikat ja ampujan tiedot
		if p.has_method("setup"):
			p.setup(spawn_dir * speed, shooter_id)
		
		# Käännetään ammus oikeaan suuntaan
		if spawn_dir.length() > 0.01:
			p.look_at(spawn_pos + spawn_dir)

@rpc("any_peer", "call_local", "reliable")
func spawn_effect(type: String, pos: Vector3):
	# Vain palvelin spawnaa (jos haluat synkronoidut efektit) 
	# TAI voit ajaa tämän kaikilla clienteilla efektien keveyden vuoksi
	if not effect_scenes.has(type): return
	
	var effect = effect_scenes[type].instantiate()
	get_tree().root.add_child(effect)
	effect.global_position = pos
	
	# Jos efekteissä on automaattinen poisto, hyvä. 
	# Jos ei, voit lisätä sen tässä:
	if effect is GPUParticles3D:
		effect.emitting = true
		get_tree().create_timer(2.0).timeout.connect(func(): effect.queue_free())
