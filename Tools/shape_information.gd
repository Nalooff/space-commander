extends RefCounted
class_name ShapeInfo

# will need to add the possibility to work for 2D shape

## ============================================================================
## ShapeInfo
## Calculates the geometric volume centroid.
##
## SUPPORTED:
##
##     MeshInstance3D
##     MultiMeshInstance3D
##     CollisionShape3D:
##         BoxShape3D
##         SphereShape3D
##         CylinderShape3D
##         CapsuleShape3D
##         ConvexPolygonShape3D
##         ConcavePolygonShape3D
##     CollisionPolygon3D
##
## The returned centroid is in GLOBAL coordinates.
##
## IMPORTANT:
## Mesh-based geometry must describe a CLOSED solid.
## A mesh with holes, missing faces, or inconsistent triangle winding
## does not have a well-defined result with the signed-tetrahedron method.
##
## ============================================================================


const EPSILON: float = 0.000000001


# ============================================================================
# RESULT
# ============================================================================

class Result:
	var centroid: Vector3
	var volume: float

	func _init(p_centroid: Vector3 = Vector3.ZERO, p_volume: float = 0.0) -> void:
		centroid = p_centroid
		volume = p_volume


# ============================================================================
# PUBLIC API
# ============================================================================


## Calculate the centroid and volume of one supported Node3D.
static func get_result(node: Node3D) -> Result:
	if node == null:
		return Result.new()

	if node is MeshInstance3D:
		return _get_mesh_instance(node)

	if node is MultiMeshInstance3D:
		return _get_multimesh_instance(node)

	if node is CollisionShape3D:
		return _get_collision_shape(node)

	if node is CollisionPolygon3D:
		return _get_collision_polygon(node)

	push_warning("CenterOfMass3D: Unsupported node type: " + node.get_class())
	return Result.new(node.global_position, 0.0)

# ============================================================================
# PUBLIC API - RECURSIVE
# ============================================================================

## Calculate the combined center of mass of all supported geometry underneath "root".
##
## Example:
##     RigidBody3D
##     ├── MeshInstance3D
##     ├── CollisionShape3D
##     ├── CollisionShape3D
##     └── CollisionPolygon3D
##
## NOTE:
##
## Do NOT put both a MeshInstance3D and its corresponding CollisionShape3D
## in the recursive hierarchy if you intend to count the physical object only once.
## Both will be counted.
static func get_recursive(root: Node) -> Result:
	var data := {
		"volume": 0.0,
		"weighted_center": Vector3.ZERO
	}

	_accumulate_recursive(root, data)

	var total_volume: float = data["volume"]
	var weighted_center: Vector3 = data["weighted_center"]

	if total_volume <= EPSILON:
		if root is Node3D:
			return Result.new(root.global_position, 0.0)

		return Result.new()

	return Result.new(weighted_center / total_volume, total_volume)


static func _accumulate_recursive(node: Node, data: Dictionary) -> void:
	if node is Node3D:
		var result := get_result(node)
		if result.volume > EPSILON:
			
			data["volume"] += result.volume
			data["weighted_center"] += (
				result.centroid
				* result.volume
			)
			
	for child in node.get_children():
		_accumulate_recursive(child, data)

# ============================================================================
# MESH INSTANCE 3D
# ============================================================================

static func _get_mesh_instance(node: MeshInstance3D) -> Result:
	if node.mesh == null:
		return Result.new(node.global_position, 0.0)

	return _get_mesh(node.mesh, node.global_transform)

# ============================================================================
# MULTIMESH INSTANCE 3D
# ============================================================================

static func _get_multimesh_instance(node: MultiMeshInstance3D) -> Result:
	if node.multimesh == null:
		return Result.new(node.global_position, 0.0)

	var multimesh := node.multimesh
	if multimesh.mesh == null:
		return Result.new(node.global_position, 0.0)

	var total_volume := 0.0
	var weighted_center := Vector3.ZERO
	for i in range(multimesh.instance_count):
		var instance_transform := (multimesh.get_instance_transform(i))
		var global_transform := (node.global_transform * instance_transform)
		var result := _get_mesh(multimesh.mesh, global_transform)

		total_volume += result.volume
		weighted_center += (result.centroid * result.volume)

	if total_volume <= EPSILON:
		return Result.new(node.global_position, 0.0)

	return Result.new(weighted_center / total_volume, total_volume)

static func _get_mesh(mesh: Mesh, transform: Transform3D) -> Result:
	if mesh == null:
		return Result.new(transform.origin, 0.0)

	var total_signed_volume := 0.0
	var weighted_center := Vector3.ZERO
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)

		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var indices = arrays[Mesh.ARRAY_INDEX]
		var has_indices: bool = (indices != null and not indices.is_empty())

		# ================================================================
		# INDEXED TRIANGLES
		# ================================================================
		
		if has_indices:
			if indices.size() % 3 != 0:
				push_warning("CenterOfMass3D: Mesh surface has an index count that is not divisible by 3.")

			for i in range(0, indices.size() - 2, 3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i + 1]]
				var c := vertices[indices[i + 2]]
				var contribution := _triangle_contribution(a, b, c, transform)

				total_signed_volume += (contribution.volume)
				weighted_center += (contribution.centroid * contribution.volume)

		# ================================================================
		# NON-INDEXED TRIANGLES
		# ================================================================

		else:
			if vertices.size() % 3 != 0:
				push_warning("CenterOfMass3D: Mesh surface has a vertex count that is not divisible by 3.")

			for i in range(0, vertices.size() - 2, 3):
				var a := vertices[i]
				var b := vertices[i + 1]
				var c := vertices[i + 2]
				var contribution := _triangle_contribution(a, b, c, transform)

				total_signed_volume += (contribution.volume)
				weighted_center += (contribution.centroid * contribution.volume)

	if abs(total_signed_volume) <= EPSILON:
		push_warning("CenterOfMass3D: Mesh has zero volume. Make sure it is a closed triangle mesh.")
		return Result.new(transform.origin, 0.0)

	return Result.new(weighted_center / total_signed_volume,abs(total_signed_volume))

# ============================================================================
# TRIANGLE CONTRIBUTION
# ============================================================================
#
# Every triangle ABC forms a tetrahedron with the origin.
#
#
# Signed volume:
#
#     V = dot(A, cross(B, C)) / 6
#
#
# Tetrahedron centroid:
#
#     C = (A + B + C) / 4
#
#
# We calculate the volume in local coordinates and multiply by the
# determinant of the transform basis.
#
# ============================================================================

static func _triangle_contribution(a: Vector3, b: Vector3, c: Vector3, transform: Transform3D) -> Result:
	var local_signed_volume := (a.dot(b.cross(c))/ 6.0)
	var local_centroid := (a + b + c) / 4.0
	var global_centroid := (transform * local_centroid)

	# A transform changes volume by determinant(Basis).
	#
	# Rotation:
	#     determinant = 1
	#
	# Uniform scale s:
	#     determinant = s³
	#
	# Non-uniform scale (sx, sy, sz):
	#     determinant = sx * sy * sz
	var determinant := (transform.basis.determinant())
	var global_signed_volume := (local_signed_volume * determinant)
	
	return Result.new(global_centroid, global_signed_volume)

# ============================================================================
# COLLISION SHAPE
# ============================================================================

static func _get_collision_shape(node: CollisionShape3D) -> Result:
	var shape := node.shape
	if shape == null:
		return Result.new(node.global_position, 0.0)

	# ========================================================================
	# BOX
	# ========================================================================

	if shape is BoxShape3D:
		var size: Vector3 = shape.size
		var volume := (size.x * size.y * size.z)
		return _primitive_result(node.global_transform, volume)

	# ========================================================================
	# SPHERE
	# ========================================================================

	if shape is SphereShape3D:
		var r: float = shape.radius
		var volume := (4.0 / 3.0 * PI * r**3)
		return _primitive_result(node.global_transform, volume)

	# ========================================================================
	# CYLINDER
	# ========================================================================

	if shape is CylinderShape3D:
		var r: float = shape.radius
		var h: float = shape.height
		var volume := (PI * r**2 * h)
		return _primitive_result(node.global_transform, volume)

	# ========================================================================
	# CAPSULE
	# ========================================================================

	if shape is CapsuleShape3D:
		var r: float = shape.radius
		var h: float = shape.height
		var cylinder_height: float = max(0.0, h - 2.0 * r)
		var cylinder_volume := (PI * r**2 * cylinder_height)
		var sphere_volume := (4.0 / 3.0 * PI * r**3)
		return _primitive_result(node.global_transform, cylinder_volume + sphere_volume)

	# ========================================================================
	# CONCAVE POLYGON
	# ========================================================================

	if shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = shape.get_faces()
		return _get_triangle_faces(faces, node.global_transform)

	# ========================================================================
	# CONVEX POLYGON
	# ========================================================================
	#
	# ConvexPolygonShape3D exposes its points but not its triangle faces.
	#
	# Shape3D.get_debug_mesh() returns an ArrayMesh representing the shape,
	# so we use that mesh and run the SAME exact tetrahedral integration.
	#
	# ========================================================================

	if shape is ConvexPolygonShape3D:
		var debug_mesh := shape.get_debug_mesh()
		if debug_mesh == null:
			push_warning("CenterOfMass3D: ConvexPolygonShape3D did not provide a debug mesh.")
			return Result.new(node.global_position, 0.0)

		return _get_mesh(debug_mesh, node.global_transform)

	# ========================================================================
	# UNKNOWN SHAPE
	# ========================================================================

	push_warning("CenterOfMass3D: Unsupported Shape3D: " + shape.get_class())
	return Result.new(node.global_position, 0.0)

# ============================================================================
# ANALYTIC PRIMITIVE
# ============================================================================
#
# Box, sphere, cylinder and capsule are all centered around local origin.
#
# Therefore:
#
#     local Centroid = Vector3.ZERO
#
# and:
#
#     global Centroid = global_transform * Vector3.ZERO
#                = global_position
#
# ============================================================================

static func _primitive_result(transform: Transform3D, local_volume: float) -> Result:
	var determinant: float = abs(transform.basis.determinant())
	var global_volume := (local_volume * determinant)
	return Result.new(transform.origin, global_volume)

# ============================================================================
# CONCAVE TRIANGLE FACES
# ============================================================================
#
# ConcavePolygonShape3D.get_faces() returns:
#
#     A B C A B C A B C ...
#
# Every 3 vertices = one triangle.
#
# ============================================================================

static func _get_triangle_faces(faces: PackedVector3Array, transform: Transform3D) -> Result:
	if faces.size() < 3:
		return Result.new(transform.origin, 0.0)

	var total_signed_volume := 0.0
	var weighted_center := Vector3.ZERO
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var contribution := _triangle_contribution(a, b, c, transform)

		total_signed_volume += (contribution.volume)
		weighted_center += (contribution.centroid * contribution.volume)

	if abs(total_signed_volume) <= EPSILON:
		push_warning("CenterOfMass3D: ConcavePolygonShape3D has zero volume. Make sure the surface is closed and triangle winding is consistent.")
		return Result.new(transform.origin, 0.0)

	return Result.new(weighted_center / total_signed_volume,abs(total_signed_volume))

# ============================================================================
# COLLISION POLYGON 3D
# ============================================================================
#
# CollisionPolygon3D represents an extruded 2D polygon.
# The polygon may be convex or concave.
# Its center of mass is:
#     polygon centroid in XY
#     center of extrusion in Z
#
# Godot describes depth as the length that the collision extends in either
# direction perpendicular to the polygon. Therefore the total thickness is 2 * depth.
#
# ============================================================================

static func _get_collision_polygon(node: CollisionPolygon3D) -> Result:
	var polygon := node.polygon
	if polygon.size() < 3:
		return Result.new(node.global_position, 0.0)

	var depth := node.depth
	if depth <= EPSILON:
		return Result.new(node.global_position, 0.0)

	# ========================================================================
	# 2D AREA
	# ========================================================================
	var signed_area := _polygon_signed_area(polygon)
	var area: float = abs(signed_area)
	if area <= EPSILON:
		return Result.new(node.global_position, 0.0)

	# ========================================================================
	# 2D CENTROID
	# ========================================================================
	var center_2d := _polygon_centroid(polygon)

	# ========================================================================
	# LOCAL 3D CENTROID
	# ========================================================================
	#
	# The extrusion is symmetric around the polygon plane, so:
	#     Z = 0
	#
	var local_centroid := Vector3(center_2d.x, center_2d.y, 0.0)

	# ========================================================================
	# VOLUME
	# ========================================================================
	#
	# Total thickness = 2 * depth.
	#
	var local_volume: float = (area * depth * 2.0)
	var determinant: float = abs(node.global_transform.basis.determinant())
	var global_volume := (local_volume * determinant)
	return Result.new(node.global_transform * local_centroid, global_volume)

# ============================================================================
# 2D POLYGON SIGNED AREA
# ============================================================================

static func _polygon_signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1)% points.size()]
		
		area += (a.x * b.y - b.x * a.y)
	return area * 0.5

# ============================================================================
# 2D POLYGON CENTROID
# ============================================================================
#
# Works for convex and concave SIMPLE polygons.
# Does NOT work for self-intersecting polygons.
#
# ============================================================================

static func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	var signed_area := 0.0
	var center := Vector2.ZERO
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1)% points.size()]
		var cross := (a.x * b.y - b.x * a.y)

		signed_area += cross
		center.x += (a.x + b.x) * cross
		center.y += (a.y + b.y) * cross

	signed_area *= 0.5
	if abs(signed_area) <= EPSILON:
		# Degenerate polygon.
		var average := Vector2.ZERO
		for point in points:
			average += point
			
		return average / points.size()

	center /= (6.0 * signed_area)
	return center
