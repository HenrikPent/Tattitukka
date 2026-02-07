#camera data (autoload)
extends Node

# Tämä muuttuja tallentaa kohdan, johon hiiri osoittaa maailmassa
var hit_position: Vector3 = Vector3.ZERO

func _process(_delta):
	# Päivitetään hit_position pelaajan kameran perusteella
	var camera = get_viewport().get_camera_3d()
	if camera:
		var mouse_pos = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_direction = camera.project_ray_normal(mouse_pos)
		
		# Luodaan taso (esim. veden pinta), johon tykki tähtää oletuksena
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(ray_origin, ray_direction)
		
		if intersection:
			hit_position = intersection
