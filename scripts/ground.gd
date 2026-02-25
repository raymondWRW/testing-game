extends TileMapLayer

@export var width := 160
@export var height := 100

@export var world_seed: int = 12345
@export var use_random_seed := false

## When true, generate() is called automatically in _ready().
## Set to false when the World node manages generation.
@export var auto_generate: bool = true

@export var source_id := 0
@export var wheat_source_id := 1

# Pick atlas coords that exist in your TileSet
# Grass tiles - plain and detailed variants
@export var grass_plain: Vector2i = Vector2i(0, 0)
@export var grass_detail: Vector2i = Vector2i(1, 0)  # 10% chance
@export var grass_detail_chance: float = 0.1

# Wheat tile settings (uses 8x8 grid of 16x16 tiles from wheat.jpg)
@export var wheat_tile_size: Vector2i = Vector2i(8, 8)  # grid size in the wheat atlas

# Dirt/road center tile
@export var dirt_center: Vector2i = Vector2i(1, 2)

# Road edge tiles (grass-to-dirt transitions) - based on tilemap layout
# These are the tiles that smooth corners/edges
@export var road_top: Vector2i = Vector2i(1, 1)       # dirt with grass above
@export var road_bottom: Vector2i = Vector2i(1, 3)   # dirt with grass below (if exists, else use center)
@export var road_left: Vector2i = Vector2i(0, 2)     # dirt with grass left
@export var road_right: Vector2i = Vector2i(2, 2)    # dirt with grass right
@export var road_corner_tl: Vector2i = Vector2i(0, 1)  # top-left corner
@export var road_corner_tr: Vector2i = Vector2i(2, 1)  # top-right corner
@export var road_corner_bl: Vector2i = Vector2i(0, 3)  # bottom-left corner (if exists)
@export var road_corner_br: Vector2i = Vector2i(2, 3)  # bottom-right corner (if exists)

# Track road cells for smoothing pass
var road_cells := {}

# Tree tiles (from tilemap_packed.png)
@export var tree_tile_1: Vector2i = Vector2i(5, 0)  # First tree variant
@export var tree_tile_2: Vector2i = Vector2i(5, 1)  # Second tree variant

# Tree settings
@export var num_decoration_trees := 20  # Trees near roads for decoration
@export var num_logging_trees := 30     # Trees at edges for logging
@export var tree_road_distance := 3     # Max distance from road for decoration trees

# Plot sizes (W x H in tiles)
const HOUSE_SIZE := Vector2i(8, 12)
const FARM_SIZE  := Vector2i(12, 21)
const MARKET_SIZE := Vector2i(6, 8)  # Smaller than house

@export var num_houses := 6
@export var num_farms := 4
@export var plot_margin := 2      # spacing between plots
@export var road_width := 2       # thickness of roads in tiles

var house_scene := preload("res://scenes/house.tscn")
var npc_scene := preload("res://scenes/npc.tscn")
var market_scene := preload("res://scenes/market.tscn")

var rng := RandomNumberGenerator.new()
var all_plots: Array[Plot] = []  # Store all plots for intersection checking

# occupied cells (plots + roads)
var occupied := {} # Dictionary used like a set: occupied[cell] = true

# Track tree positions for navigation obstacles
var tree_cells: Array[Vector2i] = []
var decoration_tree_cells: Array[Vector2i] = []  # Trees near roads (decoration only)
var logging_tree_cells: Array[Vector2i] = []     # Trees at edges (for woodcutters)

# Grid-based pathfinding
var astar_grid: AStarGrid2D

# Track NPC to farm mapping (NPC instance -> farm Plot)
var npc_farm_map: Dictionary = {}

# Market data
var market_plot: Plot = null
var market_position: Vector2 = Vector2.ZERO
var market_wheat_stock: int = 0  # Wheat available for purchase

class Plot:
	var rect: Rect2i
	var center: Vector2i
	var type: String  # "house" or "farm"
	var door_position: Vector2i  # for houses only
	var _map_center: Vector2i
	func _init(r: Rect2i, plot_type: String = "house", map_center: Vector2i = Vector2i(80, 50)):
		rect = r
		center = r.position + (r.size / 2)
		type = plot_type
		_map_center = map_center
		if type == "house":
			_calculate_door_position()

	func _calculate_door_position():
		# Place door on the side closest to map center
		var map_center := _map_center
		var distances := []
		
		# Check all four sides
		var sides := [
			Vector2i(rect.position.x + rect.size.x / 2, rect.position.y),  # top
			Vector2i(rect.position.x + rect.size.x, rect.position.y + rect.size.y / 2),  # right
			Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y),  # bottom
			Vector2i(rect.position.x, rect.position.y + rect.size.y / 2)   # left
		]
		
		var closest_side := 0
		var min_distance: float = sides[0].distance_to(map_center)
		for i in range(1, sides.size()):
			var distance: float = sides[i].distance_to(map_center)
			if distance < min_distance:
				min_distance = distance
				closest_side = i
		
		door_position = sides[closest_side]

func _ready():
	if not auto_generate:
		return

	if use_random_seed:
		rng.randomize()
		world_seed = rng.randi()
	else:
		rng.seed = world_seed

	generate()

func generate(town: TownData = null) -> void:
	if town != null:
		width = town.width
		height = town.height
		world_seed = town.town_seed
		use_random_seed = false
		num_houses = town.num_houses
		num_farms = town.num_farms
		plot_margin = town.plot_margin
		road_width = town.road_width

	rng.seed = world_seed

	clear()
	occupied.clear()
	all_plots.clear()
	road_cells.clear()
	tree_cells.clear()
	decoration_tree_cells.clear()
	logging_tree_cells.clear()

	# 1) Fill entire map with grass first (10% chance for detailed grass)
	for y in range(height):
		for x in range(width):
			var grass_tile: Vector2i
			if rng.randf() < grass_detail_chance:
				grass_tile = grass_detail
			else:
				grass_tile = grass_plain
			set_cell(Vector2i(x, y), source_id, grass_tile)

	# 2) Generate main roads first (straight lines through center)
	_create_main_roads()

	# 3) Place farms on outer boundaries (avoiding roads)
	var plots: Array = []
	_place_farms_in_edge_zones(plots)

	# 4) Place houses near center (avoiding roads)
	_place_houses_in_center_zone(plots)

	# 5) Place market near center (avoiding houses and roads)
	_place_market(plots)

	# Store plots for later reference
	all_plots.assign(plots)

	# Paint plots as dirt
	for p in plots:
		_fill_rect(p.rect, dirt_center, true)

	# 6) Connect houses and market to main roads (avoiding other buildings)
	for plot in all_plots:
		if plot.type == "house" or plot.type == "market":
			_connect_to_main_road(plot)

	# 7) Smooth road edges and corners
	_smooth_roads()

	# 8) Spawn trees (decoration near roads, logging at edges)
	_spawn_decoration_trees()
	_spawn_logging_trees()

	# Move player to map center (if player exists)
	var player := get_node_or_null("../../player") as Node2D
	if player:
		var center_cell := Vector2i(width / 2, height / 2)
		player.global_position = to_global(map_to_local(center_cell))

	# Add collision to house walls, market, and trees
	_add_house_collisions()
	_add_market_collision()
	_add_tree_collisions()

	# Spawn house and market visuals
	_spawn_houses()
	_spawn_market()

	# Set up navigation mesh for pathfinding (includes trees as obstacles)
	# Note: _setup_navigation now handles spawning NPCs after navigation is ready
	_setup_navigation()

# ---------- main road system ----------

# Store main road positions for connecting houses later
var main_road_h_y: int = 0
var main_road_v_x: int = 0

func _create_main_roads() -> void:
	# Horizontal road through center (left to right)
	main_road_h_y = height / 2
	for x in range(width):
		for w in range(road_width):
			var cell := Vector2i(x, main_road_h_y + w)
			if cell.y < height:
				road_cells[cell] = true
				occupied[cell] = true

	# Vertical road through center (top to bottom)
	main_road_v_x = width / 2
	for y in range(height):
		for w in range(road_width):
			var cell := Vector2i(main_road_v_x + w, y)
			if cell.x < width:
				road_cells[cell] = true
				occupied[cell] = true

func _connect_to_main_road(plot: Plot) -> void:
	var door := plot.door_position

	# Find closest main road
	var dist_to_h: int = abs(door.y - main_road_h_y)
	var dist_to_v: int = abs(door.x - main_road_v_x)

	var target: Vector2i
	if dist_to_h <= dist_to_v:
		target = Vector2i(door.x, main_road_h_y)
	else:
		target = Vector2i(main_road_v_x, door.y)

	# Try to carve a path that doesn't go through buildings
	_carve_connecting_road(door, target, plot)

# ---------- zoned placement system ----------

func _place_farms_in_edge_zones(plots: Array) -> void:
	# Define edge zones (outer 20% of map on each side)
	var edge_width := width / 5
	var edge_height := height / 5
	
	var edge_zones := [
		Rect2i(0, 0, width, edge_height),  # top edge
		Rect2i(0, height - edge_height, width, edge_height),  # bottom edge
		Rect2i(0, edge_height, edge_width, height - 2 * edge_height),  # left edge
		Rect2i(width - edge_width, edge_height, edge_width, height - 2 * edge_height)  # right edge
	]
	
	var farms_placed := 0
	var attempts := 0
	
	while farms_placed < num_farms and attempts < 5000:
		attempts += 1
		
		# Pick random edge zone
		var zone: Rect2i = edge_zones[rng.randi_range(0, edge_zones.size() - 1)]
		
		# Try to place farm in this zone
		var x := rng.randi_range(zone.position.x, zone.position.x + zone.size.x - FARM_SIZE.x)
		var y := rng.randi_range(zone.position.y, zone.position.y + zone.size.y - FARM_SIZE.y)
		var rect := Rect2i(Vector2i(x, y), FARM_SIZE)
		
		if _rect_free(rect, plot_margin):
			plots.append(Plot.new(rect, "farm", Vector2i(width / 2, height / 2)))
			_mark_rect(rect, plot_margin)
			farms_placed += 1

func _place_houses_in_center_zone(plots: Array) -> void:
	# Define center zone (inner 60% of map)
	var center_margin_x := width / 5
	var center_margin_y := height / 5
	var center_zone := Rect2i(
		center_margin_x, 
		center_margin_y,
		width - 2 * center_margin_x,
		height - 2 * center_margin_y
	)
	
	var houses_placed := 0
	var attempts := 0
	
	while houses_placed < num_houses and attempts < 5000:
		attempts += 1
		
		# Try to place house in center zone
		var x := rng.randi_range(center_zone.position.x, center_zone.position.x + center_zone.size.x - HOUSE_SIZE.x)
		var y := rng.randi_range(center_zone.position.y, center_zone.position.y + center_zone.size.y - HOUSE_SIZE.y)
		var rect := Rect2i(Vector2i(x, y), HOUSE_SIZE)
		
		if _rect_free(rect, plot_margin):
			plots.append(Plot.new(rect, "house", Vector2i(width / 2, height / 2)))
			_mark_rect(rect, plot_margin)
			houses_placed += 1

func _place_market(plots: Array) -> void:
	# Place market near center of map (close to road intersection)
	var center_x := width / 2
	var center_y := height / 2

	# Try positions near center, spiraling outward
	var attempts := 0
	var search_radius := 5

	while attempts < 1000:
		attempts += 1

		# Try random position near center
		var x := center_x + rng.randi_range(-search_radius, search_radius) - MARKET_SIZE.x / 2
		var y := center_y + rng.randi_range(-search_radius, search_radius) - MARKET_SIZE.y / 2

		# Clamp to valid range
		x = clamp(x, 0, width - MARKET_SIZE.x)
		y = clamp(y, 0, height - MARKET_SIZE.y)

		var rect := Rect2i(Vector2i(x, y), MARKET_SIZE)

		if _rect_free(rect, plot_margin):
			market_plot = Plot.new(rect, "market", Vector2i(width / 2, height / 2))
			plots.append(market_plot)
			_mark_rect(rect, plot_margin)
			market_position = map_to_local(market_plot.center)
			market_wheat_stock = 0
			print("Market placed at: ", market_plot.center)
			return

		# Expand search radius every 100 attempts
		if attempts % 100 == 0:
			search_radius += 5

	print("Warning: Could not place market!")

func _carve_connecting_road(from: Vector2i, to: Vector2i, source_plot: Plot) -> void:
	# Ensure coordinates are within bounds
	from.x = clamp(from.x, 0, width - 1)
	from.y = clamp(from.y, 0, height - 1)
	to.x = clamp(to.x, 0, width - 1)
	to.y = clamp(to.y, 0, height - 1)

	if from == to:
		return

	# Try horizontal-first L-shaped path
	var mid1 := Vector2i(to.x, from.y)
	if not _path_intersects_plots(from, mid1, source_plot) and not _path_intersects_plots(mid1, to, source_plot):
		_carve_straight_road(from, mid1)
		_carve_straight_road(mid1, to)
		return

	# Try vertical-first L-shaped path
	var mid2 := Vector2i(from.x, to.y)
	if not _path_intersects_plots(from, mid2, source_plot) and not _path_intersects_plots(mid2, to, source_plot):
		_carve_straight_road(from, mid2)
		_carve_straight_road(mid2, to)
		return

	# Both L-paths blocked - try routing around with extra segments
	var offsets: Array[int] = [10, -10, 20, -20, 30, -30]
	for offset in offsets:
		# Try horizontal detour
		var detour_y: int = from.y + offset
		if detour_y >= 0 and detour_y < height:
			var p1 := from
			var p2 := Vector2i(from.x, detour_y)
			var p3 := Vector2i(to.x, detour_y)
			var p4 := to
			if not _path_intersects_plots(p1, p2, source_plot) and \
			   not _path_intersects_plots(p2, p3, source_plot) and \
			   not _path_intersects_plots(p3, p4, source_plot):
				_carve_straight_road(p1, p2)
				_carve_straight_road(p2, p3)
				_carve_straight_road(p3, p4)
				return

		# Try vertical detour
		var detour_x: int = from.x + offset
		if detour_x >= 0 and detour_x < width:
			var p1 := from
			var p2 := Vector2i(detour_x, from.y)
			var p3 := Vector2i(detour_x, to.y)
			var p4 := to
			if not _path_intersects_plots(p1, p2, source_plot) and \
			   not _path_intersects_plots(p2, p3, source_plot) and \
			   not _path_intersects_plots(p3, p4, source_plot):
				_carve_straight_road(p1, p2)
				_carve_straight_road(p2, p3)
				_carve_straight_road(p3, p4)
				return

	# No valid path found - skip this connection to avoid cutting through buildings

func _path_intersects_plots(start: Vector2i, end: Vector2i, exclude_plot: Plot) -> bool:
	if start == end:
		return false
	
	var step := (end - start).sign()
	var current := start
	var max_iterations: int = abs((end - start).x) + abs((end - start).y) + 1
	var iterations := 0
	
	while current != end and iterations < max_iterations:
		iterations += 1
		# Check if this point intersects any plot (except the source plot)
		for plot in all_plots:
			if plot == exclude_plot:
				continue
			# Check if current point is within plot boundaries (including margin)
			var expanded_rect := Rect2i(
				plot.rect.position - Vector2i(plot_margin, plot_margin),
				plot.rect.size + Vector2i(plot_margin * 2, plot_margin * 2)
			)
			if expanded_rect.has_point(current):
				return true
		current += step
	
	return false

func _carve_straight_road(from: Vector2i, to: Vector2i) -> void:
	# Ensure we don't go outside bounds
	from.x = clamp(from.x, 0, width - road_width)
	from.y = clamp(from.y, 0, height - road_width)
	to.x = clamp(to.x, 0, width - road_width)
	to.y = clamp(to.y, 0, height - road_width)
	
	if from == to:
		_paint_road_cell(from)
		return
	
	var step := (to - from).sign()
	var current := from
	
	while current != to:
		_paint_road_cell(current)
		current += step
	
	# Include the end point
	_paint_road_cell(to)

# ---------- placement helpers ----------

func _place_many(plots: Array, size: Vector2i, count: int) -> void:
	var attempts := 0
	while _count_plots_of_size(plots, size) < count and attempts < 5000:
		attempts += 1

		var x := rng.randi_range(0, width - size.x)
		var y := rng.randi_range(0, height - size.y)
		var rect := Rect2i(Vector2i(x, y), size)

		if _rect_free(rect, plot_margin):
			plots.append(Plot.new(rect))
			_mark_rect(rect, plot_margin)


func _count_plots_of_size(plots: Array, size: Vector2i) -> int:
	var n := 0
	for p in plots:
		if p.rect.size == size:
			n += 1
	return n

func _rect_free(r: Rect2i, margin: int) -> bool:
	var expanded := Rect2i(r.position - Vector2i(margin, margin), r.size + Vector2i(margin*2, margin*2))
	for y in range(expanded.position.y, expanded.position.y + expanded.size.y):
		for x in range(expanded.position.x, expanded.position.x + expanded.size.x):
			var c := Vector2i(x, y)
			if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
				return false
			if occupied.has(c):
				return false
	return true

func _mark_rect(r: Rect2i, margin: int) -> void:
	var expanded := Rect2i(r.position - Vector2i(margin, margin), r.size + Vector2i(margin*2, margin*2))
	for y in range(expanded.position.y, expanded.position.y + expanded.size.y):
		for x in range(expanded.position.x, expanded.position.x + expanded.size.x):
			occupied[Vector2i(x, y)] = true

func _fill_rect(r: Rect2i, atlas: Vector2i, mark: bool) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var c := Vector2i(x, y)
			set_cell(c, source_id, atlas)
			if mark:
				occupied[c] = true

# ---------- utility ----------

func _paint_road_cell(c: Vector2i) -> void:
	# Mark a road_width x road_width block as road (will be painted in smooth pass)
	for dy in range(road_width):
		for dx in range(road_width):
			var p := c + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
				continue
			road_cells[p] = true
			occupied[p] = true

func _smooth_roads() -> void:
	# Paint all road cells with appropriate edge/corner tiles
	for cell in road_cells.keys():
		var tile := _get_road_tile_for_cell(cell)
		set_cell(cell, source_id, tile)

func _get_road_tile_for_cell(cell: Vector2i) -> Vector2i:
	# Check neighbors to determine which tile to use
	var up := road_cells.has(cell + Vector2i(0, -1))
	var down := road_cells.has(cell + Vector2i(0, 1))
	var left := road_cells.has(cell + Vector2i(-1, 0))
	var right := road_cells.has(cell + Vector2i(1, 0))

	# Count neighbors
	var h_neighbors := int(left) + int(right)
	var v_neighbors := int(up) + int(down)

	# Corners (only 2 adjacent neighbors)
	if not up and not left and down and right:
		return road_corner_tl  # top-left corner (grass above and left)
	if not up and not right and down and left:
		return road_corner_tr  # top-right corner
	if not down and not left and up and right:
		return road_corner_bl  # bottom-left corner
	if not down and not right and up and left:
		return road_corner_br  # bottom-right corner

	# Edges (grass on one side)
	if not up and down:
		return road_top  # grass above
	if not down and up:
		return road_bottom  # grass below
	if not left and right:
		return road_left  # grass on left
	if not right and left:
		return road_right  # grass on right

	# Center (surrounded by road)
	return dirt_center

# ---------- tree spawning ----------

func _spawn_decoration_trees() -> void:
	# Spawn trees near roads for decoration
	var attempts := 0
	var trees_placed := 0

	while trees_placed < num_decoration_trees and attempts < 2000:
		attempts += 1

		# Find a random position near a road
		var road_cell: Vector2i = road_cells.keys()[rng.randi() % road_cells.size()]

		# Offset from road by 1-3 tiles
		var offset := Vector2i(
			rng.randi_range(-tree_road_distance, tree_road_distance),
			rng.randi_range(-tree_road_distance, tree_road_distance)
		)
		var tree_pos := road_cell + offset

		# Check if position is valid (on grass, not occupied)
		if _is_valid_tree_position(tree_pos):
			_place_tree(tree_pos, true)  # true = decoration tree
			trees_placed += 1

func _spawn_logging_trees() -> void:
	# Spawn trees at map edges for logging (similar to farm placement)
	var edge_width := width / 5
	var edge_height := height / 5

	var edge_zones := [
		Rect2i(0, 0, width, edge_height),  # top edge
		Rect2i(0, height - edge_height, width, edge_height),  # bottom edge
		Rect2i(0, edge_height, edge_width, height - 2 * edge_height),  # left edge
		Rect2i(width - edge_width, edge_height, edge_width, height - 2 * edge_height)  # right edge
	]

	var attempts := 0
	var trees_placed := 0

	while trees_placed < num_logging_trees and attempts < 3000:
		attempts += 1

		# Pick random edge zone
		var zone: Rect2i = edge_zones[rng.randi_range(0, edge_zones.size() - 1)]

		# Random position in zone
		var tree_pos := Vector2i(
			rng.randi_range(zone.position.x, zone.position.x + zone.size.x - 1),
			rng.randi_range(zone.position.y, zone.position.y + zone.size.y - 1)
		)

		# Check if position is valid
		if _is_valid_tree_position(tree_pos):
			_place_tree(tree_pos, false)  # false = logging tree
			trees_placed += 1

func _is_valid_tree_position(pos: Vector2i) -> bool:
	# Check bounds
	if pos.x < 0 or pos.y < 0 or pos.x >= width or pos.y >= height:
		return false

	# Check if already occupied (by road, building, or another tree)
	if occupied.has(pos):
		return false

	# Check if it's on grass (not on road or building)
	var current_tile := get_cell_atlas_coords(pos)
	if current_tile != grass_plain and current_tile != grass_detail:
		return false

	# Check spacing from other trees (at least 2 tiles apart)
	for tree_cell in tree_cells:
		if pos.distance_to(tree_cell) < 2:
			return false

	return true

func _place_tree(pos: Vector2i, is_decoration: bool = false) -> void:
	# Randomly pick tree variant
	var tree_tile: Vector2i
	if rng.randf() > 0.5:
		tree_tile = tree_tile_1
	else:
		tree_tile = tree_tile_2

	set_cell(pos, source_id, tree_tile)
	occupied[pos] = true
	tree_cells.append(pos)

	# Track tree type separately
	if is_decoration:
		decoration_tree_cells.append(pos)
	else:
		logging_tree_cells.append(pos)

func _add_tree_collisions() -> void:
	# Remove existing tree collisions (in case of regeneration)
	for child in get_children():
		if child.is_in_group("tree_collisions"):
			child.queue_free()

	var tile_size := tile_set.tile_size

	for tree_pos in tree_cells:
		var body := StaticBody2D.new()
		body.add_to_group("tree_collisions")

		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = tile_size.x * 0.4  # Slightly smaller than tile
		shape.shape = circle

		body.add_child(shape)
		body.position = map_to_local(tree_pos)
		add_child(body)

# ---------- house collisions ----------

func _add_house_collisions() -> void:
	# Remove existing collision walls (in case of regeneration)
	for child in get_children():
		if child.is_in_group("house_walls"):
			child.queue_free()

	var tile_size := tile_set.tile_size
	var wall_thickness: float = tile_size.x
	var door_width: float = tile_size.x * 2  # 2 tiles wide door

	for plot in all_plots:
		if plot.type != "house":
			continue

		var body := StaticBody2D.new()
		body.add_to_group("house_walls")

		var rect: Rect2i = plot.rect
		var top_left := map_to_local(rect.position) - Vector2(tile_size) / 2
		var size := Vector2(rect.size) * Vector2(tile_size)

		# Door position in local coords relative to house
		var door_local := map_to_local(plot.door_position) - top_left

		# Determine which side the door is on
		var door_on_top := plot.door_position.y == rect.position.y
		var door_on_bottom := plot.door_position.y == rect.position.y + rect.size.y
		var door_on_left := plot.door_position.x == rect.position.x
		var door_on_right := plot.door_position.x == rect.position.x + rect.size.x

		# Top wall
		if door_on_top:
			_add_wall_with_gap(body, Vector2(0, 0), Vector2(size.x, wall_thickness), door_local.x, door_width, true)
		else:
			_add_wall_segment(body, Vector2(size.x / 2, 0), Vector2(size.x, wall_thickness))

		# Bottom wall
		if door_on_bottom:
			_add_wall_with_gap(body, Vector2(0, size.y), Vector2(size.x, wall_thickness), door_local.x, door_width, true)
		else:
			_add_wall_segment(body, Vector2(size.x / 2, size.y), Vector2(size.x, wall_thickness))

		# Left wall
		if door_on_left:
			_add_wall_with_gap(body, Vector2(0, 0), Vector2(wall_thickness, size.y), door_local.y, door_width, false)
		else:
			_add_wall_segment(body, Vector2(0, size.y / 2), Vector2(wall_thickness, size.y))

		# Right wall
		if door_on_right:
			_add_wall_with_gap(body, Vector2(size.x, 0), Vector2(wall_thickness, size.y), door_local.y, door_width, false)
		else:
			_add_wall_segment(body, Vector2(size.x, size.y / 2), Vector2(wall_thickness, size.y))

		body.position = top_left
		add_child(body)

func _add_wall_segment(body: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = pos
	body.add_child(shape)

func _add_wall_with_gap(body: StaticBody2D, wall_start: Vector2, wall_size: Vector2, gap_pos: float, gap_size: float, horizontal: bool) -> void:
	# Create two wall segments with a gap in between for the door
	if horizontal:
		var left_width := gap_pos - gap_size / 2
		var right_start := gap_pos + gap_size / 2
		var right_width := wall_size.x - right_start

		if left_width > 0:
			_add_wall_segment(body, Vector2(left_width / 2, wall_start.y), Vector2(left_width, wall_size.y))
		if right_width > 0:
			_add_wall_segment(body, Vector2(right_start + right_width / 2, wall_start.y), Vector2(right_width, wall_size.y))
	else:
		var top_height := gap_pos - gap_size / 2
		var bottom_start := gap_pos + gap_size / 2
		var bottom_height := wall_size.y - bottom_start

		if top_height > 0:
			_add_wall_segment(body, Vector2(wall_start.x, top_height / 2), Vector2(wall_size.x, top_height))
		if bottom_height > 0:
			_add_wall_segment(body, Vector2(wall_start.x, bottom_start + bottom_height / 2), Vector2(wall_size.x, bottom_height))

func _add_market_collision() -> void:
	# Remove existing market collision (in case of regeneration)
	for child in get_children():
		if child.is_in_group("market_collision"):
			child.queue_free()

	if market_plot == null:
		return

	var tile_size := tile_set.tile_size
	var body := StaticBody2D.new()
	body.add_to_group("market_collision")

	var rect: Rect2i = market_plot.rect
	var top_left := map_to_local(rect.position) - Vector2(tile_size) / 2
	var size := Vector2(rect.size) * Vector2(tile_size)

	# Market is open (no walls), but add a small collision around the stall
	# Just mark the center area as collision-free for NPCs to enter
	# Actually, let's make market accessible - no collision walls

	body.position = top_left
	add_child(body)

# ---------- house spawning ----------

func _spawn_houses() -> void:
	# Remove existing houses first (in case of regeneration)
	for child in get_children():
		if child.is_in_group("houses"):
			child.queue_free()

	var tile_size := tile_set.tile_size

	for plot in all_plots:
		if plot.type != "house":
			continue

		var house_instance = house_scene.instantiate()
		house_instance.add_to_group("houses")
		# Position house at the center of the plot
		var plot_center := plot.rect.position + plot.rect.size / 2
		house_instance.position = map_to_local(plot_center)
		add_child(house_instance)

func _spawn_market() -> void:
	# Remove existing market (in case of regeneration)
	for child in get_children():
		if child.is_in_group("market"):
			child.queue_free()

	if market_plot == null:
		return

	var market_instance = market_scene.instantiate()
	market_instance.add_to_group("market")
	# Position market at the center of the plot
	var plot_center := market_plot.rect.position + market_plot.rect.size / 2
	market_instance.position = map_to_local(plot_center)
	add_child(market_instance)

# ---------- navigation setup ----------

func _setup_navigation() -> void:
	# Use grid-based A* pathfinding instead of NavigationPolygon
	var tile_size := tile_set.tile_size

	# Create AStarGrid2D
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, width, height)
	astar_grid.cell_size = Vector2(tile_size)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()

	# Mark all cells as walkable initially (they already are by default)

	# Block building cells (houses and market) with padding
	var building_padding := 2  # 2 tile padding around buildings
	for plot in all_plots:
		if plot.type == "house" or plot.type == "market":
			var rect: Rect2i = plot.rect
			# Expand rect by padding
			var start_x := maxi(0, rect.position.x - building_padding)
			var start_y := maxi(0, rect.position.y - building_padding)
			var end_x := mini(width - 1, rect.position.x + rect.size.x + building_padding)
			var end_y := mini(height - 1, rect.position.y + rect.size.y + building_padding)

			for y in range(start_y, end_y + 1):
				for x in range(start_x, end_x + 1):
					astar_grid.set_point_solid(Vector2i(x, y), true)

	# Block tree cells with padding
	var tree_padding := 1  # 1 tile padding around trees
	for tree_pos in tree_cells:
		for dy in range(-tree_padding, tree_padding + 1):
			for dx in range(-tree_padding, tree_padding + 1):
				var cell := tree_pos + Vector2i(dx, dy)
				if cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height:
					astar_grid.set_point_solid(cell, true)

	# Count blocked and walkable cells for debug
	var blocked_count := 0
	var walkable_count := 0
	for y in range(height):
		for x in range(width):
			if astar_grid.is_point_solid(Vector2i(x, y)):
				blocked_count += 1
			else:
				walkable_count += 1

	print("Grid navigation setup complete.")
	print("  - Grid size: %d x %d" % [width, height])
	print("  - Walkable cells: %d" % walkable_count)
	print("  - Blocked cells: %d" % blocked_count)

	# Wait for everything to be ready before spawning NPCs
	await get_tree().process_frame
	await get_tree().physics_frame

	# Now spawn NPCs
	call_deferred("_spawn_npcs")

# Get path from one position to another using grid-based A*
func get_grid_path(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	var tile_size := tile_set.tile_size

	# Convert world positions to grid cells
	var from_cell := local_to_map(to_local(from_pos))
	var to_cell := local_to_map(to_local(to_pos))

	# Clamp to grid bounds
	from_cell.x = clampi(from_cell.x, 0, width - 1)
	from_cell.y = clampi(from_cell.y, 0, height - 1)
	to_cell.x = clampi(to_cell.x, 0, width - 1)
	to_cell.y = clampi(to_cell.y, 0, height - 1)

	# If start or end is blocked, find nearest walkable cell
	if astar_grid.is_point_solid(from_cell):
		from_cell = _find_nearest_walkable(from_cell)
	if astar_grid.is_point_solid(to_cell):
		to_cell = _find_nearest_walkable(to_cell)

	# Get path in grid coordinates
	var grid_path := astar_grid.get_point_path(from_cell, to_cell)

	# Convert to world positions
	var world_path := PackedVector2Array()
	for cell in grid_path:
		var local_pos := map_to_local(Vector2i(cell))
		var global_pos := to_global(local_pos)
		world_path.append(global_pos)

	return world_path

func _find_nearest_walkable(cell: Vector2i) -> Vector2i:
	# Search in expanding squares around the cell
	for radius in range(1, 10):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue  # Only check perimeter
				var check := cell + Vector2i(dx, dy)
				if check.x >= 0 and check.x < width and check.y >= 0 and check.y < height:
					if not astar_grid.is_point_solid(check):
						return check
	return cell  # Fallback to original

# ---------- NPC spawning ----------

func _spawn_npcs() -> void:
	# Remove existing NPCs first (in case of regeneration)
	for child in get_children():
		if child.is_in_group("npcs"):
			child.queue_free()

	npc_farm_map.clear()

	# Wait one more frame to ensure everything is ready
	await get_tree().process_frame

	# Collect house and farm plots separately
	var house_plots: Array[Plot] = []
	var farm_plots: Array[Plot] = []
	for plot in all_plots:
		if plot.type == "house":
			house_plots.append(plot)
		elif plot.type == "farm":
			farm_plots.append(plot)

	print("Spawning NPCs: %d houses, %d farms available" % [house_plots.size(), farm_plots.size()])

	# Track which logging trees have been assigned
	var available_logging_trees := logging_tree_cells.duplicate()
	var woodcutter_index := 0

	# Spawn one NPC per house
	var tile_size := tile_set.tile_size
	for i in range(house_plots.size()):
		var house_plot: Plot = house_plots[i]
		var npc_instance = npc_scene.instantiate()
		npc_instance.add_to_group("npcs")

		# Calculate home position outside the house (offset from door)
		var door_pos: Vector2 = map_to_local(house_plot.door_position)
		var house_center: Vector2 = map_to_local(house_plot.center)
		var door_direction := (door_pos - house_center).normalized()
		# Offset 2 tiles away from the door, outside the house
		var home_pos: Vector2 = door_pos + door_direction * (tile_size.x * 2)

		# Add to scene first
		add_child(npc_instance)

		# Convert all positions to global before passing to NPC
		var global_home_pos: Vector2 = to_global(home_pos)
		var global_market_pos: Vector2 = to_global(market_position) if market_position != Vector2.ZERO else Vector2.ZERO

		# Give all NPCs access to market first
		if market_position != Vector2.ZERO:
			npc_instance.set_market_position(global_market_pos)
			npc_instance.wants_to_sell.connect(_on_npc_wants_to_sell)
			npc_instance.wants_to_buy.connect(_on_npc_wants_to_buy)

		# Assign job: farmer if farm available, otherwise woodcutter
		if i < farm_plots.size():
			# This NPC is a farmer
			var farm_pos: Vector2 = map_to_local(farm_plots[i].center)
			var global_farm_pos: Vector2 = to_global(farm_pos)
			npc_instance.initialize_farmer(global_home_pos, global_farm_pos)
			npc_farm_map[npc_instance] = farm_plots[i]
			npc_instance.arrived_at_farm.connect(_on_npc_arrived_at_farm.bind(npc_instance))
			print("Spawned farmer %d at home: %s, farm: %s" % [i, global_home_pos, global_farm_pos])
		else:
			# This NPC is a woodcutter
			var global_tree_pos := Vector2.ZERO
			if available_logging_trees.size() > 0:
				# Assign a logging tree to this woodcutter
				var tree_cell: Vector2i = available_logging_trees[woodcutter_index % available_logging_trees.size()]
				var tree_pos: Vector2 = map_to_local(tree_cell)
				global_tree_pos = to_global(tree_pos)
				woodcutter_index += 1
			npc_instance.initialize_woodcutter(global_home_pos, global_tree_pos)
			print("Spawned woodcutter %d at home: %s, tree: %s" % [i - farm_plots.size(), global_home_pos, global_tree_pos])

	print("NPC spawning complete: %d NPCs created" % [house_plots.size()])

# ---------- wheat tile painting ----------

func _on_npc_arrived_at_farm(npc: Node) -> void:
	if not npc_farm_map.has(npc):
		return
	var farm_plot: Plot = npc_farm_map[npc]
	_paint_wheat_on_farm(farm_plot.rect)

func _paint_wheat_on_farm(farm_rect: Rect2i) -> void:
	# Paint wheat tiles on the farm - each tile shows the same wheat image
	for y in range(farm_rect.position.y, farm_rect.position.y + farm_rect.size.y):
		for x in range(farm_rect.position.x, farm_rect.position.x + farm_rect.size.x):
			var cell := Vector2i(x, y)
			# Use (0, 0) so each tile shows the same wheat image
			set_cell(cell, wheat_source_id, Vector2i(0, 0))

# ---------- market trading ----------

func _on_npc_wants_to_sell(npc: Node, wheat_amount: int) -> void:
	# Farmer is selling wheat to the market
	market_wheat_stock += wheat_amount
	_update_market_display()
	print("Market: Farmer sold %d wheat. Stock: %d" % [wheat_amount, market_wheat_stock])

func _on_npc_wants_to_buy(npc: Node, wood_amount: int) -> void:
	# Woodcutter wants to buy wheat with wood (1:1 trade)
	var wheat_to_give: int = mini(wood_amount, market_wheat_stock)
	if wheat_to_give > 0:
		market_wheat_stock -= wheat_to_give
		npc.receive_wheat(wheat_to_give)
		npc.spend_wood(wheat_to_give)
		_update_market_display()
		print("Market: Woodcutter bought %d wheat for %d wood. Stock: %d" % [wheat_to_give, wheat_to_give, market_wheat_stock])
	else:
		print("Market: No wheat available for woodcutter!")

func _update_market_display() -> void:
	# Update the market's stock display
	for child in get_children():
		if child.is_in_group("market") and child.has_method("update_stock_display"):
			child.update_stock_display(market_wheat_stock)
			break
