extends FogVolume

@export var max_density := 0.04
@export var surface_y := 0.0 # Veden pinnan korkeus
@export var fog_height := 80.0 # Sylinterin korkeus

var camera_ref: Camera3D = null

func _ready():
	# Lukitaan Y-positio niin, että sumun yläreuna on tasan pinnassa
	# Jos korkeus on 80, keskipisteen (position) pitää olla -40
	global_position.y = surface_y - (fog_height / 2.0) -10
	
	if material is FogMaterial:
		material.density = max_density

func _process(_delta: float):
	if not camera_ref:
		camera_ref = get_viewport().get_camera_3d()
		return

	# Seurataan vain horisontaalista liikettä (X ja Z)
	# Y pidetään vakiona, jolloin sumu pysyy "kaivona" veden alla
	global_position.x = camera_ref.global_position.x
	global_position.z = camera_ref.global_position.z

func set_fog_active(active: bool):
	# Voit silti kytkeä tiheyden nollaan jos haluat poistaa 
	# sumun efektin (esim. kun pelaaja on kaukana merestä)
	if material is FogMaterial:
		material.density = max_density if active else 0.0
