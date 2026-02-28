# ProjectileManager.gd
extends Node

@export var scenes : Dictionary = {
	"127mm": preload("res://Projectiles/Shells/127_mm.tscn"),
	"280mm": preload("res://Projectiles/Shells/127_mm.tscn"), # Lisää nämä!
	"406mm": preload("res://Projectiles/Shells/127_mm.tscn")
}

@export var effect_scenes : Dictionary = {
	"Impact_127mm": preload("res://Projectiles/Effects/127mm/127mmImpact.tscn"),
	"Impact_280mm": preload("res://Projectiles/Effects/127mm/127mmImpact.tscn"),
	"Impact_406mm": preload("res://Projectiles/Effects/127mm/127mmImpact.tscn"),
	"water_splash": preload("res://Projectiles/Effects/WaterSplash/water_splash.tscn")
}

@rpc("any_peer", "call_local", "reliable")
func request_fire(type: String, spawn_pos: Vector3, spawn_dir: Vector3, shooter_id: int, speed: float):
	if not multiplayer.is_server(): return
	
	# Tarkistetaan löytyykö tyyppi, jos ei, kokeillaan oletusta
	if not scenes.has(type): 
		print("VAROITUS: Ammustyyppiä ", type, " ei löytynyt ProjectileManagerista!")
		return
	
	var p = scenes[type].instantiate()
	var container = get_tree().root.find_child("Projectiles", true, false)
	
	if container:
		container.add_child(p, true)
		p.global_position = spawn_pos
		
		# TÄRKEÄÄ: Ammus saa tässä vaiheessa tiedon nopeudestaan
		if p.has_method("setup"):
			p.setup(spawn_dir * speed, shooter_id)
		
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
	
	#HUOMIO! efektin täytyy itse poistaa itsensä kun se on ohi!
