extends Module
class_name ThrusterModule

# ==============================================================================================================
# REAL-WORLD ROCKET ENGINE REFERENCE METRICS:
# --------------------------------------------------------------------------------------------------------------
# 1. Micro RCS (Cold Gas):        0.05 kN  | Up: 5-15 ms    | Down: 2-5 ms    | Curve: Linear / Step
# 2. Heavy RCS (Hypergolic):      3.8 kN   | Up: 50-100 ms  | Down: 10-30 ms  | Curve: Step w/ sharp cut
# 3. Orbital Engine (RL10/AJ10):  110 kN   | Up: 300-1000ms | Down: 100-250ms | Curve: Ease-In / Fast cut
# 4. Medium Engine (Merlin 1D):   845 kN   | Up: 1800 ms    | Down: 300-500ms | Curve: S-Curve / Tailoff
# 5. Heavy Engine (Raptor/F-1):   6700 kN  | Up: 3000-5000ms| Down: 500-800ms | Curve: Deep S-Curve / Tailoff
# ==============================================================================================================

@export_group("Thrust Performance")
## Maximum force output in Kilonewtons (kN).
## Convert internally to Newtons (1 kN = 1000 N) for Godot physics calculations.
@export_custom(PROPERTY_HINT_NONE, "suffix:kN") var max_thrust: float = 850.0
## Local thrust direction relative to nozzle origin (Default: forward/-Z).
@export var thrust_direction: Vector3 = Vector3(0, 0, -1)

@export_group("Spool Times")
## Time required to spool from 0% to 100% thrust in milliseconds (ms).
@export_custom(PROPERTY_HINT_NONE, "suffix:ms") var ramp_up_time_ms: float = 1800.0
## Time required to bleed thrust from 100% to 0% in milliseconds (ms).
@export_custom(PROPERTY_HINT_NONE, "suffix:ms") var ramp_down_time_ms: float = 500.0

@export_group("Spool Curves")
## Thrust output curve during startup mapped from 0.0 (time) to 1.0 (thrust).
@export var accel_curve: Curve
## Thrust output curve during shutdown mapped from 0.0 (time) to 1.0 (thrust).
@export var decel_curve: Curve

@export_group("Gimbal Settings")
## Maximum gimbal angle deviation limits in degrees (Pitch, Yaw, Roll).
@export_custom(PROPERTY_HINT_NONE, "suffix:deg") var max_gimbal_degrees: Vector3 = Vector3(10.0, 10.0, 0.0)
## Actuator rotation speed limit in degrees per second (°/s).
@export_custom(PROPERTY_HINT_NONE, "suffix:deg_s") var gimbal_speed_deg_s: float = 20.0

# Runtime State variables
var normalized_spool: float = 0.0  # Spool timer progress (0.0 to 1.0)
var current_throttle: float = 0.0  # Output throttle after applying curves (0.0 to 1.0)
var current_gimbal_rad: Vector3 = Vector3.ZERO # Active gimbal state in radians

## Max thrust in Newtons (N) ready for physics engine calculations.
var max_thrust_n: float:
	get:
		return max_thrust * 1000.0


func _ready() -> void:
	# Fallback linear response curves if none assigned in Inspector
	if not accel_curve:
		accel_curve = Curve.new()
		accel_curve.add_point(Vector2(0, 0))
		accel_curve.add_point(Vector2(1, 1))
	if not decel_curve:
		decel_curve = Curve.new()
		decel_curve.add_point(Vector2(0, 1))
		decel_curve.add_point(Vector2(1, 0))


func update_gimbal_and_spool(target_dir: Vector3, target_throttle: float, delta: float) -> void:
	# -------------------------------------------------------------------------
	# 1. GIMBAL ACTUATOR CALCULATIONS
	# Convert local target direction into pitch (X-axis) and yaw (Y-axis) angles
	# -------------------------------------------------------------------------
	var local_target := (transform.basis.inverse() * target_dir).normalized()
	
	var target_pitch := atan2(-local_target.y, -local_target.z)
	var target_yaw := atan2(local_target.x, -local_target.z)
	
	var max_pitch_rad := deg_to_rad(max_gimbal_degrees.x)
	var max_yaw_rad := deg_to_rad(max_gimbal_degrees.y)
	
	var desired_euler := Vector3(
		clamp(target_pitch, -max_pitch_rad, max_pitch_rad),
		clamp(target_yaw, -max_yaw_rad, max_yaw_rad),
		0.0
	)
	
	current_gimbal_rad = current_gimbal_rad.move_toward(
		desired_euler, 
		deg_to_rad(gimbal_speed_deg_s) * delta
	)
	
	# -------------------------------------------------------------------------
	# 2. SPOOLING & TURBOPUMP RAMP CALCULATIONS
	# -------------------------------------------------------------------------
	target_throttle = clamp(target_throttle, 0.0, 1.0)
	
	if target_throttle > normalized_spool:
		var ramp_up_sec: float = max(0.001, ramp_up_time_ms / 1000.0)
		normalized_spool = move_toward(normalized_spool, target_throttle, delta / ramp_up_sec)
		current_throttle = accel_curve.sample(normalized_spool)
	else:
		var ramp_down_sec: float = max(0.001, ramp_down_time_ms / 1000.0)
		normalized_spool = move_toward(normalized_spool, target_throttle, delta / ramp_down_sec)
		current_throttle = decel_curve.sample(1.0 - normalized_spool)


## Returns active directional vector of thrust with gimbal offset in local space.
func get_active_thrust_dir() -> Vector3:
	return Basis.from_euler(current_gimbal_rad) * thrust_direction.normalized()


## Returns total calculated thrust force vector in Newtons (N) for RigidBody3D.apply_force().
func get_current_thrust_force_n() -> Vector3:
	return get_active_thrust_dir() * (max_thrust_n * current_throttle)
