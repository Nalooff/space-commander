extends Node3D
class_name Module

@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D


enum CENTER_OF_MASS_MODE {AUTO, CUSTOM}

@export var mass: float = 100.0
@export var mode_center_of_mass: CENTER_OF_MASS_MODE = CENTER_OF_MASS_MODE.AUTO
@export var center_of_mass: Vector3 = Vector3.ZERO
var centroid
var volume

func _ready() -> void:
	var shape_info = ShapeInfo.get_result(collision_shape_3d)
	
	centroid = shape_info.centroid
	volume = shape_info.measure
	
	if mode_center_of_mass == CENTER_OF_MASS_MODE.AUTO:
		center_of_mass = centroid
