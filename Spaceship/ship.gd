extends RigidBody3D

@export var modules_container: Node3D

# Array holding every Modules of the ship
var modules: Array[Module] = []
# Index map for O(1) removals without using modules.find()
var _module_indices: Dictionary = {}

func _ready() -> void:
	modules_container.child_entered_tree.connect(_on_module_added)
	modules_container.child_exiting_tree.connect(_on_module_removed)
	
	# Initial setup for modules placed directly in the scene editor
	for child in modules_container.get_children():
		if child is Module:
			_add_module(child)
			
	recalculate_physics()


# ==============================================================================
# Modules Handling
# ==============================================================================

func _add_module(module: Module) -> void:
	_module_indices[module] = modules.size()
	modules.append(module)

func _remove_module(module: Module) -> void:
	if not _module_indices.has(module):
		push_warning("Attempted to remove untracked module '%s' from %s." % [module.name, name])
		return
		
	var remove_idx: int = _module_indices[module]
	var last_idx: int = modules.size() - 1
	var last_module: Module = modules[last_idx]

	# Swap the last item into the removed item's spot (O(1) swap-pop)
	modules[remove_idx] = last_module
	_module_indices[last_module] = remove_idx

	modules.pop_back()
	_module_indices.erase(module)


# ==============================================================================
# Physics
# ==============================================================================

func recalculate_physics() -> void:
	var total_mass: float = 0.0
	var weighted_position_sum: Vector3 = Vector3.ZERO
	
	for module in modules:
		var m: float = module.mass
		var local_com: Vector3 = module.position + (module.quaternion * module.center_of_mass)
		
		weighted_position_sum += local_com * m
		total_mass += m
		
	if total_mass > 0.0:
		mass = total_mass
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = weighted_position_sum / total_mass



# ==============================================================================
# Signals Connections
# ==============================================================================

func _on_module_added(node: Node) -> void:
	if node is Module:
		_add_module(node as Module)
		recalculate_physics()

func _on_module_removed(node: Node) -> void:
	if node is Module:
		_remove_module(node as Module)
		recalculate_physics()
