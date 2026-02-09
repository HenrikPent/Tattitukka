# UnitSpawner.gd
extends Node

@export var unit_scene: PackedScene = preload("res://Units/Unit.tscn")
@export var destroyer: PackedScene = preload("res://Units/Vehicles/Destroyer/destroyer.tscn")
@export var rifleman: PackedScene = preload("res://Units/Soldiers/Rifleman/Rifleman.tscn")
@export var testi: PackedScene = preload("res://Units/Vehicles/testi/testi.tscn")
@export var fighter: PackedScene = preload("res://Units/Vehicles/FighterV1/figterV1.tscn")

func spawn_starting_units(player_ids: Array):
	var units_node = get_node("/root/Main/Units")
	
	for id in player_ids:
		if units_node.has_node(str(id)): 
			continue
		
		var unit = fighter.instantiate()
		unit.name = str(id)
		
		units_node.add_child(unit, true)
		
		unit.global_position = Vector3(id % 10 * 15, 5, 0)
