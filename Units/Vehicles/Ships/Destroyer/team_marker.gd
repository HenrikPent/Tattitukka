extends MeshInstance3D

@export var own_color := Color.CYAN
@export var enemy_color := Color.RED

func _ready():
	var ship = get_parent()
	var my_id = get_tree().get_multiplayer().get_unique_id() # tämä on oikea tapa!
	
	if ship.team_id == my_id:
		material_override = _create_material(own_color)
	else:
		material_override = _create_material(enemy_color)

func _create_material(c: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = c
	return mat
