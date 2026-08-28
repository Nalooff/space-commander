extends RefCounted
class_name ShapeInfo

## Tool to calculate both Centroid and Volume/Area
##
## Calculates the geometric volume/area centroid and magnitude.
##
## SUPPORTED 3D: 
##     MeshInstance3D, 
##     MultiMeshInstance3D, 
##     CSGShape3D (Box, Sphere, Cylinder, Mesh, Polygon, Combiner),
##     CollisionShape3D (Box, Sphere, Cylinder, Capsule, Convex, Concave), 
##     CollisionPolygon3D, 
##
## SUPPORTED 2D: 
##     Sprite2D, 
##     CollisionShape2D (RectangleShape2D, CircleShape2D, SegmentShape2D, CapsuleShape2D), 
##     CollisionPolygon2D.

const EPSILON: float = 0.000000001

# ============================================================================
# RESULT
# ============================================================================

class Result:
	var centroid: Vector3
	var measure: float # Volume for 3D, Area for 2D
	var dimension: int # 2 or 3

	func _init(p_centroid: Vector3 = Vector3.ZERO, p_measure: float = 0.0, p_dimension: int = 3) -> void:
		centroid = p_centroid
		measure = p_measure
		dimension = p_dimension

	func _to_string() -> String:
		var unit_label: String = "Volume" if dimension == 3 else "Area"
		if dimension == 2:
			return "(Centroid: (%.3f, %.3f), %s: %.3f, Dim: 2D)" % [
				centroid.x, centroid.y, unit_label, measure
			]
		return "(Centroid: (%.3f, %.3f, %.3f), %s: %.3f, Dim: 3D)" % [
			centroid.x, centroid.y, centroid.z, unit_label, measure
		]

# ============================================================================
# PUBLIC API
# ============================================================================

## Calculate centroid and measure of a single Node (Node3D or Node2D).
static func get_result(node: Node) -> Result:
	if node == null:
		return Result.new()

	# 3D Nodes
	if node is MeshInstance3D:
		return _get_mesh_instance(node)
	if node is MultiMeshInstance3D:
		return _get_multimesh_instance(node)
	if node is CSGShape3D:
		return _get_csg_shape_3d(node)
	if node is CollisionShape3D:
		return _get_collision_shape_3d(node)
	if node is CollisionPolygon3D:
		return _get_collision_polygon_3d(node)

	# 2D Nodes
	if node is CollisionShape2D:
		return _get_collision_shape_2d(node)
	if node is CollisionPolygon2D:
		return _get_collision_polygon_2d(node)
	if node is Sprite2D:
		return _get_sprite_2d(node)

	if node is Node3D:
		return Result.new(node.global_position, 0.0, 3)
	elif node is Node2D:
		return Result.new(Vector3(node.global_position.x, node.global_position.y, 0.0), 0.0, 2)

	push_warning("ShapeInfo: Unsupported node type: " + node.get_class())
	return Result.new()

## Calculate combined center of mass of all supported geometry under "root".
static func get_recursive(root: Node) -> Result:
	var data := {
		"measure": 0.0,
		"weighted_center": Vector3.ZERO,
		"dimension": 3
	}

	_accumulate_recursive(root, data)

	var total_measure: float = data["measure"]
	var weighted_center: Vector3 = data["weighted_center"]

	if total_measure <= EPSILON:
		if root is Node3D:
			return Result.new(root.global_position, 0.0, 3)
		elif root is Node2D:
			return Result.new(Vector3(root.global_position.x, root.global_position.y, 0.0), 0.0, 2)
		return Result.new()

	return Result.new(weighted_center / total_measure, total_measure, data["dimension"])

static func _accumulate_recursive(node: Node, data: Dictionary) -> void:
	if node is Node3D or node is Node2D:
		var result := get_result(node)
		if result.measure > EPSILON:
			data["measure"] += result.measure
			data["weighted_center"] += result.centroid * result.measure
			data["dimension"] = result.dimension
			
	for child in node.get_children():
		_accumulate_recursive(child, data)

# ============================================================================
# 3D PROCESSING
# ============================================================================

static func _get_mesh_instance(node: MeshInstance3D) -> Result:
	if node.mesh == null:
		return Result.new(node.global_position, 0.0, 3)
	return _get_mesh(node.mesh, node.global_transform)

static func _get_multimesh_instance(node: MultiMeshInstance3D) -> Result:
	if node.multimesh == null or node.multimesh.mesh == null:
		return Result.new(node.global_position, 0.0, 3)

	var multimesh := node.multimesh
	var total_measure := 0.0
	var weighted_center := Vector3.ZERO

	for i in range(multimesh.instance_count):
		var instance_transform := multimesh.get_instance_transform(i)
		var global_transform := node.global_transform * instance_transform
		var result := _get_mesh(multimesh.mesh, global_transform)

		total_measure += result.measure
		weighted_center += result.centroid * result.measure

	if total_measure <= EPSILON:
		return Result.new(node.global_position, 0.0, 3)

	return Result.new(weighted_center / total_measure, total_measure, 3)

static func _get_mesh(mesh: Mesh, transform: Transform3D) -> Result:
	if mesh is PrimitiveMesh:
		var prim_res := _get_primitive_mesh_analytical(mesh, transform)
		if prim_res != null:
			return prim_res

	var total_signed_volume := 0.0
	var weighted_volume_center := Vector3.ZERO
	var total_area := 0.0
	var weighted_area_center := Vector3.ZERO

	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var has_indices: bool = not indices.is_empty()

		if has_indices:
			for i in range(0, indices.size() - 2, 3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i + 1]]
				var c := vertices[indices[i + 2]]
				
				var v_contrib := _triangle_volume_contribution(a, b, c, transform)
				total_signed_volume += v_contrib.measure
				weighted_volume_center += v_contrib.centroid * v_contrib.measure

				var a_contrib := _triangle_area_contribution(a, b, c, transform)
				total_area += a_contrib.measure
				weighted_area_center += a_contrib.centroid * a_contrib.measure
		else:
			for i in range(0, vertices.size() - 2, 3):
				var a := vertices[i]
				var b := vertices[i + 1]
				var c := vertices[i + 2]
				
				var v_contrib := _triangle_volume_contribution(a, b, c, transform)
				total_signed_volume += v_contrib.measure
				weighted_volume_center += v_contrib.centroid * v_contrib.measure

				var a_contrib := _triangle_area_contribution(a, b, c, transform)
				total_area += a_contrib.measure
				weighted_area_center += a_contrib.centroid * a_contrib.measure

	if abs(total_signed_volume) > EPSILON:
		return Result.new(weighted_volume_center / total_signed_volume, abs(total_signed_volume), 3)
	
	if total_area > EPSILON:
		return Result.new(weighted_area_center / total_area, total_area, 3)

	return Result.new(transform.origin, 0.0, 3)

static func _get_primitive_mesh_analytical(mesh: PrimitiveMesh, transform: Transform3D) -> Result:
	if mesh is BoxMesh:
		var size: Vector3 = (mesh as BoxMesh).size
		return _primitive_result_3d(transform, size.x * size.y * size.z)

	if mesh is SphereMesh:
		var r: float = (mesh as SphereMesh).radius
		return _primitive_result_3d(transform, (4.0 / 3.0) * PI * pow(r, 3))

	if mesh is CylinderMesh:
		var cyl := mesh as CylinderMesh
		if abs(cyl.top_radius - cyl.bottom_radius) < EPSILON:
			return _primitive_result_3d(transform, PI * pow(cyl.top_radius, 2) * cyl.height)

	if mesh is CapsuleMesh:
		var cap := mesh as CapsuleMesh
		var r: float = cap.radius
		var h: float = cap.height
		var cyl_h: float = max(0.0, h - 2.0 * r)
		var vol := (PI * pow(r, 2) * cyl_h) + ((4.0 / 3.0) * PI * pow(r, 3))
		return _primitive_result_3d(transform, vol)

	if mesh is PrismMesh:
		var prism := mesh as PrismMesh
		var s: Vector3 = prism.size
		var vol := 0.5 * s.x * s.y * s.z
		return _primitive_result_3d(transform, vol)

	if mesh is TorusMesh:
		var torus := mesh as TorusMesh
		var R: float = torus.inner_radius + (torus.outer_radius - torus.inner_radius) * 0.5
		var r: float = (torus.outer_radius - torus.inner_radius) * 0.5
		var vol := 2.0 * pow(PI, 2) * R * pow(r, 2)
		return _primitive_result_3d(transform, vol)

	if mesh is QuadMesh:
		var size: Vector2 = (mesh as QuadMesh).size
		return _primitive_surface_result_3d(transform, size.x * size.y)

	if mesh is PlaneMesh:
		var size: Vector2 = (mesh as PlaneMesh).size
		return _primitive_surface_result_3d(transform, size.x * size.y)

	return null

static func _triangle_volume_contribution(a: Vector3, b: Vector3, c: Vector3, transform: Transform3D) -> Result:
	var local_signed_volume := a.dot(b.cross(c)) / 6.0
	var local_centroid := (a + b + c) / 3.0
	var global_centroid := transform * local_centroid
	var global_signed_volume := local_signed_volume * transform.basis.determinant()
	return Result.new(global_centroid, global_signed_volume, 3)

static func _triangle_area_contribution(a: Vector3, b: Vector3, c: Vector3, transform: Transform3D) -> Result:
	var ga := transform * a
	var gb := transform * b
	var gc := transform * c
	var area := (gb - ga).cross(gc - ga).length() * 0.5
	var centroid := (ga + gb + gc) / 3.0
	return Result.new(centroid, area, 3)

# ============================================================================
# CSG SHAPES 3D
# ============================================================================

static func _get_csg_shape_3d(node: CSGShape3D) -> Result:
	if not node.is_root_shape():
		return Result.new(node.global_position, 0.0, 3)

	var baked_mesh := node.bake_static_mesh()
	if baked_mesh == null:
		return Result.new(node.global_position, 0.0, 3)

	return _get_mesh(baked_mesh, node.global_transform)

# ============================================================================
# COLLISION SHAPE 3D
# ============================================================================

static func _get_collision_shape_3d(node: CollisionShape3D) -> Result:
	var shape := node.shape
	if shape == null:
		return Result.new(node.global_position, 0.0, 3)

	if shape is BoxShape3D:
		var size: Vector3 = shape.size
		return _primitive_result_3d(node.global_transform, size.x * size.y * size.z)

	if shape is SphereShape3D:
		var r: float = shape.radius
		return _primitive_result_3d(node.global_transform, (4.0 / 3.0) * PI * pow(r, 3))

	if shape is CylinderShape3D:
		var r: float = shape.radius
		var h: float = shape.height
		return _primitive_result_3d(node.global_transform, PI * pow(r, 2) * h)

	if shape is CapsuleShape3D:
		var r: float = shape.radius
		var h: float = shape.height
		var cyl_h: float = max(0.0, h - 2.0 * r)
		var vol := (PI * pow(r, 2) * cyl_h) + ((4.0 / 3.0) * PI * pow(r, 3))
		return _primitive_result_3d(node.global_transform, vol)

	if shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = shape.get_faces()
		return _get_triangle_faces_3d(faces, node.global_transform)

	if shape is ConvexPolygonShape3D:
		var debug_mesh := shape.get_debug_mesh()
		if debug_mesh == null:
			return Result.new(node.global_position, 0.0, 3)
		return _get_mesh(debug_mesh, node.global_transform)

	return Result.new(node.global_position, 0.0, 3)

static func _primitive_result_3d(transform: Transform3D, local_volume: float) -> Result:
	var global_volume: float = local_volume * abs(transform.basis.determinant())
	return Result.new(transform.origin, global_volume, 3)

static func _primitive_surface_result_3d(transform: Transform3D, local_area: float) -> Result:
	var scale_x := transform.basis.x.length()
	var scale_z := transform.basis.z.length()
	return Result.new(transform.origin, local_area * scale_x * scale_z, 3)

static func _get_triangle_faces_3d(faces: PackedVector3Array, transform: Transform3D) -> Result:
	if faces.size() < 3:
		return Result.new(transform.origin, 0.0, 3)

	var total_signed_volume := 0.0
	var weighted_center := Vector3.ZERO
	for i in range(0, faces.size() - 2, 3):
		var contribution := _triangle_volume_contribution(faces[i], faces[i + 1], faces[i + 2], transform)
		total_signed_volume += contribution.measure
		weighted_center += contribution.centroid * contribution.measure

	if abs(total_signed_volume) <= EPSILON:
		return Result.new(transform.origin, 0.0, 3)

	return Result.new(weighted_center / total_signed_volume, abs(total_signed_volume), 3)

static func _get_collision_polygon_3d(node: CollisionPolygon3D) -> Result:
	var polygon := node.polygon
	if polygon.size() < 3 or node.depth <= EPSILON:
		return Result.new(node.global_position, 0.0, 3)

	var area: float = abs(_polygon_signed_area(polygon))
	if area <= EPSILON:
		return Result.new(node.global_position, 0.0, 3)

	var center_2d := _polygon_centroid(polygon)
	var local_centroid := Vector3(center_2d.x, center_2d.y, 0.0)
	var local_volume: float = area * node.depth
	var global_volume: float = local_volume * abs(node.global_transform.basis.determinant())

	return Result.new(node.global_transform * local_centroid, global_volume, 3)

# ============================================================================
# 2D PROCESSING
# ============================================================================

static func _get_collision_shape_2d(node: CollisionShape2D) -> Result:
	var shape := node.shape
	if shape == null:
		return _to_result_2d(node.global_position, 0.0)

	var xform := node.global_transform

	if shape is RectangleShape2D:
		var size: Vector2 = shape.size
		return _primitive_result_2d(xform, size.x * size.y)

	if shape is CircleShape2D:
		var r: float = shape.radius
		return _primitive_result_2d(xform, PI * pow(r, 2))

	if shape is CapsuleShape2D:
		var r: float = shape.radius
		var h: float = shape.height
		var rect_h: float = max(0.0, h - 2.0 * r)
		var area := (2.0 * r * rect_h) + (PI * pow(r, 2))
		return _primitive_result_2d(xform, area)

	if shape is SegmentShape2D:
		var g_a: Vector2 = xform * shape.a
		var g_b: Vector2 = xform * shape.b
		var g_mid: Vector2 = (g_a + g_b) * 0.5
		return _to_result_2d(g_mid, g_a.distance_to(g_b))

	return _to_result_2d(node.global_position, 0.0)

static func _get_collision_polygon_2d(node: CollisionPolygon2D) -> Result:
	var polygon := node.polygon
	if polygon.size() < 3:
		return _to_result_2d(node.global_position, 0.0)

	var signed_area := _polygon_signed_area(polygon)
	var area: float = abs(signed_area)
	if area <= EPSILON:
		return _to_result_2d(node.global_position, 0.0)

	var local_center := _polygon_centroid(polygon)
	var global_center := node.global_transform * local_center
	var scale_factor: float = abs(node.global_transform.x.cross(node.global_transform.y))
	return _to_result_2d(global_center, area * scale_factor)

static func _get_sprite_2d(node: Sprite2D) -> Result:
	if node.texture == null:
		return _to_result_2d(node.global_position, 0.0)

	var rect := node.get_rect()
	var local_center := rect.get_center()
	var area := rect.size.x * rect.size.y
	var global_center := node.global_transform * local_center
	var scale_factor: float = abs(node.global_transform.x.cross(node.global_transform.y))

	return _to_result_2d(global_center, area * scale_factor)

static func _primitive_result_2d(transform: Transform2D, local_area: float) -> Result:
	var scale_factor: float = abs(transform.x.cross(transform.y))
	return _to_result_2d(transform.origin, local_area * scale_factor)

static func _to_result_2d(pos_2d: Vector2, area: float) -> Result:
	return Result.new(Vector3(pos_2d.x, pos_2d.y, 0.0), area, 2)

# ============================================================================
# 2D POLYGON MATH
# ============================================================================

static func _polygon_signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += (a.x * b.y - b.x * a.y)
	return area * 0.5

static func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	var signed_area := 0.0
	var center := Vector2.ZERO
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var cross := (a.x * b.y - b.x * a.y)
		signed_area += cross
		center.x += (a.x + b.x) * cross
		center.y += (a.y + b.y) * cross

	signed_area *= 0.5
	if abs(signed_area) <= EPSILON:
		var average := Vector2.ZERO
		for point in points:
			average += point
		return average / points.size()

	center /= (6.0 * signed_area)
	return center
