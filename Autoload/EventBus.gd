@tool
extends Node

# ==============================================================================
# HOW TO CONFIG THE EVENT BUS VIA PROJECT SETTINGS
# ==============================================================================
# Go to: Project -> Project Settings -> Debug
# event_bus/config/...  (Controls global logger output formatting)
# event_bus/signals/... (True = Log this signal to console; False = Mute logs)
#
# HOW TO EMIT A SIGNAL TO GET DEBUG FEATURE:
#   EventBus.signal_name.emit(args (max 8))
#
# ==============================================================================

# ==============================================================================
# SIGNAL REGISTRY
# ==============================================================================
signal game_started(player_count: int)


# ==============================================================================
# ENGINE LIFECYCLE & LIVE COMPILATION
# ==============================================================================

## Godot entry point. Runs when the actual game runtime initializes.
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		_run_runtime_setup()


## Native static compiler hook. Fires instantly every time you save this script in the editor.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		_run_editor_setup_static()


# ==============================================================================
# STATIC EDITOR SETUP AUTOMATION (No memory duplication!)
# ==============================================================================

## Pure static context function to sync signals down to ProjectSettings sequentially.
static func _run_editor_setup_static() -> void:
	var script_resource: Script = load("res://AutoLoad/EventBus.gd")
	if not script_resource:
		return
		
	var settings_modified = false
	
	# 1. Sync global logger configuration settings keys
	var configs = {
		"debug/event_bus/config/show_argument_names": false,
		"debug/event_bus/config/show_emitter_line_number": true,
		"debug/event_bus/config/show_receiver_line_number": false
	}
	
	var config_index = 0
	for path in configs:
		if not ProjectSettings.has_setting(path):
			ProjectSettings.set_setting(path, configs[path])
			_add_setting_meta_static(path, TYPE_BOOL, config_index)
			settings_modified = true
		config_index += 1

	# 2. Extract valid custom signals defined in this script file
	var valid_signal_paths = []
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in script_resource.get_script_signal_list():
		var sig_name = sig_info["name"]
		if not (sig_name in base_node_signals or sig_name in ["script_changed", "property_list_changed"]):
			valid_signal_paths.append("debug/event_bus/signals/" + sig_name)

	# 3. Back up currently checked/unchecked values
	var current_values_backup = {}
	for path in valid_signal_paths:
		if ProjectSettings.has_setting(path):
			current_values_backup[path] = ProjectSettings.get_setting(path)
			
	# 4. Completely wipe out all existing custom signal entries from the config registry
	for prop in ProjectSettings.get_property_list():
		var path: String = prop["name"]
		if path.begins_with("debug/event_bus/signals/"):
			ProjectSettings.set_setting(path, null)
			
	# 5. Re-serialize them sequentially matching their file array location
	for index in range(valid_signal_paths.size()):
		var setting_path = valid_signal_paths[index]
		var saved_toggle_state = current_values_backup.get(setting_path, false)
		
		ProjectSettings.set_setting(setting_path, saved_toggle_state)
		_add_setting_meta_static(setting_path, TYPE_BOOL, index + 100)
		settings_modified = true
			
	# 6. Commit structural changes directly to project.godot
	if settings_modified:
		ProjectSettings.save()
		if ProjectSettings.has_method("notify_property_list_changed"):
			ProjectSettings.notify_property_list_changed()


## Attaches visual sorting parameters directly into the Godot Engine compilation dictionary.
static func _add_setting_meta_static(path: String, type_enum: int, order_weight: int) -> void:
	ProjectSettings.add_property_info({
		"name": path,
		"type": type_enum,
		"hint": PROPERTY_HINT_NONE,
		"order": order_weight
	})


# ==============================================================================
# RUNTIME HOOKS & PROCESSING (Runs during live gameplay)
# ==============================================================================

## Discovers custom signals at runtime launch and establishes intercepting proxy closures
func _run_runtime_setup() -> void:
	var base_node_signals = ClassDB.class_get_signal_list("Node").map(func(s): return s.name)
	
	for sig_info in get_signal_list():
		var sig_name = sig_info["name"]
		if sig_name in base_node_signals or sig_name in ["script_changed", "property_list_changed"]:
			continue
			
		_evaluate_and_hook_signal(sig_info)


## Connects an intercepting lambda macro to a signal if its debug toggle is enabled
func _evaluate_and_hook_signal(sig_info: Dictionary) -> void:
	var sig_name = sig_info["name"]
	var setting_path = "debug/event_bus/signals/" + sig_name
	
	var is_enabled = ProjectSettings.get_setting(setting_path) if ProjectSettings.has_setting(setting_path) else false
	if not is_enabled:
		return
		
	var sig: Signal = get(sig_name)
	var expected_arg_count = sig_info["args"].size()
	var arg_names = sig_info["args"].map(func(arg): return arg["name"])
	
	# Binds an 8-parameter anonymous proxy layout to support generic variable payloads cleanly
	sig.connect(func(arg1=null, arg2=null, arg3=null, arg4=null, arg5=null, arg6=null, arg7=null, arg8=null): 
		var raw_args = [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8]
		var passed_args = raw_args.slice(0, expected_arg_count)
		
		_process_signal_log(sig, passed_args, arg_names)
	)


## Unpacks the active system properties to assemble a visual terminal report
func _process_signal_log(sig: Signal, args: Array, arg_names: Array) -> void:
	var time = Time.get_time_string_from_system()
	var emitter_string = _find_caller_source()
	var formatted_arguments = _format_arguments_by_config(args, arg_names)
	
	_print_signal_block(sig.get_name(), emitter_string, formatted_arguments, time, sig.get_connections())


## Walks up the active engine engine call stack to locate exactly who fired the signal
func _find_caller_source() -> String:
	var stack = get_stack()
	if stack.size() >= 4:
		var caller_info = stack[3]
		var file_name: String = caller_info["source"].get_file()
		
		var config_path = "debug/event_bus/config/show_emitter_line_number"
		var show_line = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else true
		
		if show_line:
			return str(file_name, " -> line ", caller_info["line"], " in .", caller_info["function"], "()")
		else:
			return str(file_name, " in .", caller_info["function"], "()")
			
	return "Unknown Script Source"


## Maps raw signal argument values to their script parameter names if configured to do so
func _format_arguments_by_config(args: Array, arg_names: Array) -> Variant:
	var config_path = "debug/event_bus/config/show_argument_names"
	var show_names = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else false
	
	if not show_names or arg_names.is_empty():
		return args
		
	var named_args_dict = {}
	for i in range(args.size()):
		var key = arg_names[i] if i < arg_names.size() else "param_" + str(i)
		named_args_dict[key] = args[i]
	return named_args_dict


# ==============================================================================
# CLEAN PRINT FORMATTER
# ==============================================================================

## Outputs a comprehensive, stylized diagnostic report block directly into the Godot Output console
func _print_signal_block(sig_name: String, emitter: String, args: Variant, time: String, connections: Array) -> void:
	print("\n========== SIGNAL EMITTED ==========")
	print("Signal Name : ", sig_name)
	print("Real Emitter: ", emitter)
	print("Infos/Args  : ", args)
	print("Time        : ", time)
	
	_print_receivers(connections)
	print("=======================================\n")


## Lists every object currently listening to this signal, along with their connected target method names
func _print_receivers(connections: Array) -> void:
	var active_listeners = connections.filter(func(c): return c["callable"].get_object() != self)
	
	if active_listeners.is_empty():
		print("Receivers   : None (No one is listening!)")
		return
		
	var config_path = "debug/event_bus/config/show_receiver_line_number"
	var show_line = ProjectSettings.get_setting(config_path) if ProjectSettings.has_setting(config_path) else false
	
	print("Receivers")
	for connection in active_listeners:
		var callable: Callable = connection["callable"]
		var receiver = callable.get_object()
		var receiver_name = receiver.name if (receiver and "name" in receiver) else str(receiver)
		
		var action_text = _get_callable_action_text(callable)
		var script_info = _get_receiver_script_info(receiver, callable, show_line)

		print("   -> [", receiver_name, "] (", script_info, ") ", action_text)


# ==============================================================================
# DELEGATED STRUCTURAL SUB-FUNCTIONS
# ==============================================================================

## Inspects a target callable reference to safely extract its executable label format string
func _get_callable_action_text(callable: Callable) -> String:
	if callable.is_custom():
		return "will run an: [Anonymous Lambda Function]"
	return str("will run method: .", callable.get_method(), "()")


## Locates the script location path and filename associated with a target listener object
func _get_receiver_script_info(receiver: Object, callable: Callable, show_line: bool) -> String:
	if not receiver or not receiver.has_method("get_script"):
		return "Unknown Script"
		
	var script = receiver.get_script()
	if not (script is Script):
		return "Unknown Script"
		
	var script_path = script.resource_path.get_file()
	
	if callable.is_custom():
		return script_path
		
	if show_line:
		var line_num = _find_method_line_in_script(script, callable.get_method())
		if line_num > 0:
			return str(script_path, " -> line ", line_num)
			
	return script_path


## Parses reflection arrays or raw source lines to pinpoint exactly what line a callback method starts on
func _find_method_line_in_script(script: Script, method_name: String) -> int:
	for source_loc in script.get_script_method_list():
		if source_loc.name == method_name and source_loc.has("line"):
			return source_loc["line"]
				
	var source_code = script.source_code
	if not source_code.is_empty():
		var lines = source_code.split("\n")
		var target_pattern = "func " + method_name
		for i in range(lines.size()):
			if lines[i].contains(target_pattern):
				return i + 1
	return -1
