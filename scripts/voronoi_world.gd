class_name VoronoiWorld
extends RefCounted

## Manages a Voronoi diagram representing the world map
## Each cell corresponds to a town

# World bounds (in abstract world units)
var world_size: Vector2 = Vector2(10000, 10000)

# Town sites: StringName -> Vector2 (position in world space)
var town_sites: Dictionary = {}

# Precomputed cell polygons: StringName -> PackedVector2Array
var cell_polygons: Dictionary = {}

# Neighbor relationships: StringName -> Array[StringName]
var neighbors: Dictionary = {}

# Center positions of each cell (for labels)
var cell_centers: Dictionary = {}

## Add a town site to the Voronoi diagram
func add_site(town_id: StringName, position: Vector2) -> void:
	town_sites[town_id] = position

## Remove a town site
func remove_site(town_id: StringName) -> void:
	town_sites.erase(town_id)
	cell_polygons.erase(town_id)
	neighbors.erase(town_id)
	cell_centers.erase(town_id)

## Compute Voronoi diagram using perpendicular bisector clipping
func compute_voronoi() -> void:
	cell_polygons.clear()
	neighbors.clear()
	cell_centers.clear()

	if town_sites.is_empty():
		return

	# Compute cell polygon for each town
	for town_id in town_sites.keys():
		var polygon := _compute_cell_polygon(town_id)
		cell_polygons[town_id] = polygon
		cell_centers[town_id] = _compute_polygon_centroid(polygon)

	# Compute neighbor relationships
	_compute_neighbors()

## Get the town ID for a given world position
func get_cell_at_position(pos: Vector2) -> StringName:
	# Find nearest site (simple approach)
	var nearest_id: StringName = &""
	var nearest_dist: float = INF

	for town_id in town_sites.keys():
		var site: Vector2 = town_sites[town_id]
		var dist := pos.distance_squared_to(site)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_id = town_id

	return nearest_id

## Get the cell polygon for a town
func get_cell_polygon(town_id: StringName) -> PackedVector2Array:
	return cell_polygons.get(town_id, PackedVector2Array())

## Get all neighbor town IDs for a town
func get_neighbors(town_id: StringName) -> Array:
	return neighbors.get(town_id, [])

## Get the neighbor in a given direction from the town center
func get_neighbor_in_direction(town_id: StringName, direction: Vector2) -> StringName:
	if not town_sites.has(town_id):
		return &""

	var site: Vector2 = town_sites[town_id]
	var target_pos := site + direction.normalized() * 1000.0

	# Find which neighbor is closest to this target
	var neighbor_ids: Array = neighbors.get(town_id, [])
	var best_neighbor: StringName = &""
	var best_dot: float = -INF

	for neighbor_id in neighbor_ids:
		var neighbor_site: Vector2 = town_sites[neighbor_id]
		var to_neighbor := (neighbor_site - site).normalized()
		var dot := direction.normalized().dot(to_neighbor)
		if dot > best_dot:
			best_dot = dot
			best_neighbor = neighbor_id

	# Only return if the direction somewhat matches (dot > 0)
	if best_dot > 0.3:
		return best_neighbor
	return &""

## Get all town IDs
func get_all_town_ids() -> Array:
	return town_sites.keys()

## Get the site position for a town
func get_site_position(town_id: StringName) -> Vector2:
	return town_sites.get(town_id, Vector2.ZERO)

## Get the center of a cell (centroid of polygon)
func get_cell_center(town_id: StringName) -> Vector2:
	return cell_centers.get(town_id, town_sites.get(town_id, Vector2.ZERO))

# -------------------- Private Methods --------------------

## Compute the cell polygon for a single town using perpendicular bisector clipping
func _compute_cell_polygon(town_id: StringName) -> PackedVector2Array:
	var site: Vector2 = town_sites[town_id]

	# Start with world bounds as initial polygon
	var polygon: Array[Vector2] = [
		Vector2(0, 0),
		Vector2(world_size.x, 0),
		Vector2(world_size.x, world_size.y),
		Vector2(0, world_size.y)
	]

	# Clip by perpendicular bisector with each other site
	for other_id in town_sites.keys():
		if other_id == town_id:
			continue
		var other: Vector2 = town_sites[other_id]
		polygon = _clip_polygon_by_bisector(polygon, site, other)
		if polygon.is_empty():
			break

	return PackedVector2Array(polygon)

## Clip a polygon by the perpendicular bisector between two points
## Keeps the half closer to 'keep_point'
func _clip_polygon_by_bisector(polygon: Array[Vector2], keep_point: Vector2, other_point: Vector2) -> Array[Vector2]:
	if polygon.size() < 3:
		return []

	# Perpendicular bisector: midpoint and normal
	var midpoint := (keep_point + other_point) / 2.0
	var direction := other_point - keep_point
	# Normal pointing toward keep_point
	var normal := -direction.normalized()

	# Sutherland-Hodgman clipping
	var output: Array[Vector2] = []

	for i in range(polygon.size()):
		var current := polygon[i]
		var next_idx := (i + 1) % polygon.size()
		var next := polygon[next_idx]

		var current_inside := _is_inside_halfplane(current, midpoint, normal)
		var next_inside := _is_inside_halfplane(next, midpoint, normal)

		if current_inside:
			output.append(current)
			if not next_inside:
				# Edge exits the half-plane
				var intersection: Variant = _line_halfplane_intersection(current, next, midpoint, normal)
				if intersection != null:
					output.append(intersection as Vector2)
		elif next_inside:
			# Edge enters the half-plane
			var intersection: Variant = _line_halfplane_intersection(current, next, midpoint, normal)
			if intersection != null:
				output.append(intersection as Vector2)

	return output

## Check if a point is inside a half-plane defined by point and normal
func _is_inside_halfplane(point: Vector2, plane_point: Vector2, plane_normal: Vector2) -> bool:
	return (point - plane_point).dot(plane_normal) >= 0

## Find intersection of line segment with half-plane boundary
func _line_halfplane_intersection(p1: Vector2, p2: Vector2, plane_point: Vector2, plane_normal: Vector2) -> Variant:
	var d1 := (p1 - plane_point).dot(plane_normal)
	var d2 := (p2 - plane_point).dot(plane_normal)

	if abs(d1 - d2) < 0.0001:
		return null  # Parallel

	var t := d1 / (d1 - d2)
	if t < 0 or t > 1:
		return null

	return p1 + (p2 - p1) * t

## Compute neighbors by checking which cells share edges
func _compute_neighbors() -> void:
	neighbors.clear()

	var town_ids := town_sites.keys()
	for town_id in town_ids:
		neighbors[town_id] = []

	# Two cells are neighbors if their sites' perpendicular bisector
	# intersects both of their cell polygons
	for i in range(town_ids.size()):
		for j in range(i + 1, town_ids.size()):
			var id_a: StringName = town_ids[i]
			var id_b: StringName = town_ids[j]

			if _cells_are_neighbors(id_a, id_b):
				neighbors[id_a].append(id_b)
				neighbors[id_b].append(id_a)

## Check if two cells share an edge
func _cells_are_neighbors(id_a: StringName, id_b: StringName) -> bool:
	var poly_a: PackedVector2Array = cell_polygons.get(id_a, PackedVector2Array())
	var poly_b: PackedVector2Array = cell_polygons.get(id_b, PackedVector2Array())

	if poly_a.is_empty() or poly_b.is_empty():
		return false

	# Check if any edge of poly_a is shared with poly_b
	# Two edges share if they have two points very close together
	var tolerance := 1.0
	var shared_points := 0

	for point_a in poly_a:
		for point_b in poly_b:
			if point_a.distance_to(point_b) < tolerance:
				shared_points += 1
				if shared_points >= 2:
					return true

	return false

## Compute centroid of a polygon
func _compute_polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO

	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	return centroid / polygon.size()
