extends Node3D

@onready var water: GPUParticles3D = $Water


func _ready():
	explode()  # toistetaan heti kun lisätään pelimaailmaan eli osumassa

func explode():

	water.emitting = true
	await get_tree().create_timer(2.0).timeout
	queue_free()
