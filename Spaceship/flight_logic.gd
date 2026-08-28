extends Node


# Inner class used purely for caching pre-calculated values per thruster
class ThrusterData:
	var node: ThrusterModule
	var local_pos: Vector3
	var default_torque: Vector3

# Target Demands set dynamically by Player UI / AI Script
var desired_linear_velocity: Vector3 = Vector3.ZERO
var desired_angular_velocity: Vector3 = Vector3.ZERO

var ship: SpaceShip
var thruster_cache: Array[ThrusterData] = []

func _ready() -> void:
	ship = get_parent() as SpaceShip
	if not ship:
		push_error("FlightComputer must be a direct child of a SpaceShip (RigidBody3D) node!")

# Call this whenever ship.recalculate_physics() runs (when modules change)
func rebuild_thruster_cache() -> void:
	thruster_cache.clear()
	if not ship:
		return
		
	for module in ship.modules:
		if module is ThrusterModule:
			var data = ThrusterData.new()
			data.node = module
			# Pre-calculate relative offset from Center of Mass once instead of every frame
			data.local_pos = module.position - ship.center_of_mass
			
			# Pre-calculate baseline max torque (r x F)
			var base_force = module.thrust_direction.normalized() * module.max_thrust
			data.default_torque = data.local_pos.cross(base_force)
			
			thruster_cache.append(data)

# --- MOTION ENVELOPE QUERY FOR PLAYER UI ARROW ---

func get_max_envelope_in_direction(desired_linear_dir: Vector3, desired_torque_dir: Vector3) -> Dictionary:
	var max_linear: float = 0.0
	var max_torque: float = 0.0
	
	for t in thruster_cache:
		var max_gimbal_rad = deg_to_rad(t.node.max_gimbal_degrees.x)
		var best_dir = t.node.thrust_direction.rotated(Vector3.UP, max_gimbal_rad).normalized()
		
		var lin_proj = best_dir.dot(desired_linear_dir)
		if lin_proj > 0.0:
			max_linear += lin_proj * t.node.max_thrust
			
		var torque_vec = t.local_pos.cross(best_dir * t.node.max_thrust)
		var torq_proj = torque_vec.normalized().dot(desired_torque_dir)
		if torq_proj > 0.0:
			max_torque += torq_proj * torque_vec.length()
			
	return {"max_force": max_linear, "max_torque": max_torque}

# --- SOLVER & PHYSICS EXECUTION ---

func _physics_process(delta: float) -> void:
	if not ship or thruster_cache.is_empty():
		return

	# 1. Compute force/torque required to reach desired velocities
	var current_local_vel = ship.transform.basis.inverse() * ship.linear_velocity
	var vel_error = desired_linear_velocity - current_local_vel
	var req_force = vel_error * ship.mass
	
	var current_local_ang = ship.transform.basis.inverse() * ship.angular_velocity
	var ang_error = desired_angular_velocity - current_local_ang
	var req_torque = ang_error * ship.inertia.length()
	
	# 2. Synchronize turn alignment with linear acceleration
	var heading_alignment: float = 1.0
	if req_torque.length() > 0.1 and req_force.length() > 0.1:
		var turn_time_est = ang_error.length() / max(0.1, req_torque.length())
		var accel_time_est = vel_error.length() / max(0.1, req_force.length())
		if turn_time_est > accel_time_est:
			heading_alignment = accel_time_est / turn_time_est
			
	req_force *= heading_alignment
	
	# 3. Distribute power to thrusters using cached values
	for t in thruster_cache:
		var tm: ThrusterModule = t.node
		var target_dir = req_force.normalized() if req_force.length() > 0.0 else tm.thrust_direction
		
		var lin_contrib = tm.get_active_thrust_dir().dot(req_force.normalized()) if req_force.length() > 0.0 else 0.0
		var t_torque = t.local_pos.cross(tm.get_active_thrust_dir() * tm.max_thrust)
		var torq_contrib = t_torque.normalized().dot(req_torque.normalized()) if req_torque.length() > 0.0 else 0.0
		
		var target_throttle = clamp((lin_contrib * 0.5) + (torq_contrib * 0.5), 0.0, 1.0)
		
		# Step nozzle gimbal and engine power spooling
		tm.update_gimbal_and_spool(target_dir, target_throttle, delta)
		
		# Apply physical force directly onto parent ship
		if tm.current_throttle > 0.0:
			var local_thrust_vector = tm.get_active_thrust_dir() * (tm.max_thrust * tm.current_throttle)
			var global_thrust_vector = ship.global_transform.basis * local_thrust_vector
			var global_force_point = ship.global_transform * t.local_pos
			
			ship.apply_force(global_thrust_vector, global_force_point - ship.global_position)
