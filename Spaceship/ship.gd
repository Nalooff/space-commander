extends RigidBody3D

@export var module_container: Node3D 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass




func recalculate_physics():
	var total_mass: float = 0.0
	var weighted_position_sum: Vector3 = Vector3.ZERO
	
	# Only loop through children inside THIS ship's container!
	for module in module_container.get_children():
		var m = module.mass
		var local_com = to_local(module.global_transform * module.center_of_mass)
		
		weighted_position_sum += local_com * m
		total_mass += m
		
	if total_mass > 0:
		mass = total_mass
		center_of_mass = weighted_position_sum / total_mass
