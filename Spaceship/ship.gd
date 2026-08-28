extends RigidBody3D
class_name SpaceShip

@export var modules_container: Node3D

var modules: Array[Module] = []
var _module_indices: Dictionary = {} # Module -> index in modules array

# Type Registry: Script/Class -> Array[Module]
var _typed_modules: Dictionary = {}
# Type Index Registry: Module -> index in its specific type array
var _typed_module_indices: Dictionary = {}

func _ready() -> void:
	modules_container.child_entered_tree.connect(_on_module_added)
	modules_container.child_exiting_tree.connect(_on_module_removed)
	
	for child in modules_container.get_children():
		if child is Module:
			_add_module(child)
			
	recalculate_physics()


# ==============================================================================
# Modules Handling
# ==============================================================================

func _add_module(module: Module) -> void:
	# 1. Standard global array tracking
	_module_indices[module] = modules.size()
	modules.append(module)
	
	# 2. Type-based dictionary tracking
	var type_key: Script = module.get_script()
	if not _typed_modules.has(type_key):
		_typed_modules[type_key] = []
	
	var type_array: Array = _typed_modules[type_key]
	_typed_module_indices[module] = type_array.size()
	type_array.append(module)

func _remove_module(module: Module) -> void:
	if not _module_indices.has(module):
		push_warning("Attempted to remove untracked module '%s' from %s." % [module.name, name])
		return
		
	# 1. Global O(1) swap-pop
	var remove_idx: int = _module_indices[module]
	var last_idx: int = modules.size() - 1
	var last_module: Module = modules[last_idx]

	modules[remove_idx] = last_module
	_module_indices[last_module] = remove_idx

	modules.pop_back()
	_module_indices.erase(module)

	# 2. Type-based O(1) swap-pop
	var type_key: Script = module.get_script()
	var type_array: Array = _typed_modules[type_key]
	var typed_remove_idx: int = _typed_module_indices[module]
	var typed_last_idx: int = type_array.size() - 1
	var typed_last_module: Module = type_array[typed_last_idx]

	type_array[typed_remove_idx] = typed_last_module
	_typed_module_indices[typed_last_module] = typed_remove_idx

	type_array.pop_back()
	_typed_module_indices.erase(module)


# ==============================================================================
# API
# ==============================================================================

## Returns an array of modules matching the requested class/script in O(1) time.
func get_modules_of_type(target_script: Script) -> Array:
	return _typed_modules.get(target_script, [])


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
# Signals
# ==============================================================================

func _on_module_added(node: Node) -> void:
	if node is Module:
		_add_module(node as Module)
		recalculate_physics()

func _on_module_removed(node: Node) -> void:
	if node is Module:
		_remove_module(node as Module)
		recalculate_physics()
