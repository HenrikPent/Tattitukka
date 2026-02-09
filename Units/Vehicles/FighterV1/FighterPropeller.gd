extends MeshInstance3D 

@export var max_rpm: float = 5000.0 # pyörimisnopeus rad/s maksimithrustilla
@export var plane_node_path: NodePath = "../" # viittaa CharacterBody3D:hen

var plane_node
var current_thrust := 0.0
var max_thrust := 300.0

func _ready():
	plane_node = get_node_or_null(plane_node_path)
	if plane_node and "current_thrust" in plane_node:
		current_thrust = plane_node.current_thrust
		max_thrust = plane_node.max_thrust

func _process(delta):
	if plane_node:
		# Tarkistetaan että muuttuja on olemassa
		if "current_thrust" in plane_node and "max_thrust" in plane_node:
			current_thrust = plane_node.current_thrust
			max_thrust = plane_node.max_thrust
			# laske pyörimisnopeus suhteessa thrustiini
			var thrust_ratio = current_thrust / max_thrust
			var rotation_amount = thrust_ratio * max_rpm * delta
			rotate_z(rotation_amount) 
