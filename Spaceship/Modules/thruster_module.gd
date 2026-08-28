extends Module
class_name ThrusterModule


@export_group("Thrust Performance")
@export var max_thrust: float = 50000.0 # Force in Newtons
@export var thrust_direction: Vector3 = Vector3(0, 0, -1) # Default forward thrust relative to nozzle

@export_group("Spool Curves")
@export var ramp_up_time: float = 0.5 # Seconds from 0% to 100%
@export var ramp_down_time: float = 0.3 # Seconds from 100% to 0%
@export var accel_curve: Curve
@export var decel_curve: Curve

@export_group("Gimbal Settings")
@export var max_gimbal_degrees: Vector3 = Vector3(15.0, 15.0, 0.0) # Pitch, Yaw, Roll limits
@export var gimbal_speed_deg: float = 60.0 # Nozzle rotation speed in degrees/sec

# Runtime State
var current_throttle: float = 0.0
var current_gimbal: Vector3 = Vector3.ZERO # Euler angles in radians

func _ready() -> void:
	# Fallback linear curves if none assigned in Inspector
	if not accel_curve:
		accel_curve = Curve.new()
		accel_curve.add_point(Vector2(0, 0))
		accel_curve.add_point(Vector2(1, 1))
	if not decel_curve:
		decel_curve = Curve.new()
		decel_curve.add_point(Vector2(0, 1))
		decel_curve.add_point(Vector2(1, 0))

func update_gimbal_and_spool(target_dir: Vector3, target_throttle: float, delta: float) -> void:
	# 1. Rotate Gimbal toward target direction within limits
	var local_target = (transform.basis.inverse() * target_dir).normalized()
	var max_pitch = deg_to_rad(max_gimbal_degrees.x)
	var max_yaw = deg_to_rad(max_gimbal_degrees.y)
	
	var desired_euler = Vector3(
		clamp(local_target.x, -max_pitch, max_pitch),
		clamp(local_target.y, -max_yaw, max_yaw),
		0.0
	)
	
	current_gimbal = current_gimbal.move_toward(desired_euler, deg_to_rad(gimbal_speed_deg) * delta)
	
	# 2. Spooling Logic
	if target_throttle == 0.0:
		# Instant Cutoff
		current_throttle = 0.0
	elif target_throttle > current_throttle:
		# Ramping Up
		var step = delta / max(0.001, ramp_up_time)
		var progress = clamp(current_throttle + step, 0.0, 1.0)
		current_throttle = accel_curve.sample(progress)
	else:
		# Ramping Down
		var step = delta / max(0.001, ramp_down_time)
		var progress = clamp(current_throttle - step, 0.0, 1.0)
		current_throttle = decel_curve.sample(progress)

func get_active_thrust_dir() -> Vector3:
	return Basis.from_euler(current_gimbal) * thrust_direction.normalized()
