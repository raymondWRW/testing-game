extends TileMapLayer

@export var width := 160
@export var height := 100

@export var world_seed: int = 12345
@export var use_random_seed := false

## When true, generate() is called automatically in _ready().
## Set to false when the World node manages generation.
@export var auto_generate: bool = true

@export var source_id := 0

# Pick atlas coords that exist in your TileSet
# Grass tiles - plain and detailed variants
@export var grass_plain: Vector2i = Vector2i(0, 0)
@export var grass_detail: Vector2i = Vector2i(1, 0)  # 10% chance
@export var grass_detail_chance: float = 0.1

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

# Plot sizes (W x H in tiles)
const HOUSE_SIZE := Vector2i(8, 12)
const FARM_SIZE  := Vector2i(12, 21)

@export var num_houses := 6
@export var num_farms := 4
@export var plot_margin := 2      # spacing between plots
@export var road_width := 2       # thickness of roads in tiles

var house_scene := preload("res://scenes/house.tscn")
var npc_scene := preload("res://scenes/npc.tscn")

var rng := RandomNumberGenerator.new()
var all_plots: Array[Plot] = []  # Store all plots for intersection checking

# occupied cells (plots + roads)
var occupied := {} # Dictionary used like a set: occupied[cell] = true

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

	# Store plots for later reference
	all_plots.assign(plots)

	# Paint plots as dirt
	for p in plots:
		_fill_rect(p.rect, dirt_center, true)

	# 5) Connect houses to main roads (avoiding other buildings)
	for plot in all_plots:
		if plot.type == "house":
			_connect_to_main_road(plot)

	# 6) Smooth road edges and corners
	_smooth_roads()

	# Move player to map center
	var player := get_node("../../player") as Node2D
	var center_cell := Vector2i(width / 2, height / 2)
	player.global_position = to_global(map_to_local(center_cell))

	# Add collision to house walls
	_add_house_collisions()

	# Spawn house visuals
	_spawn_houses()

	# Spawn NPCs
	_spawn_npcs()

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

# ---------- NPC spawning ----------

func _spawn_npcs() -> void:
	# Remove existing NPCs first (in case of regeneration)
	for child in get_children():
		if child.is_in_group("npcs"):
			child.queue_free()

	# Collect house and farm plots separately
	var house_plots: Array[Plot] = []
	var farm_plots: Array[Plot] = []
	for plot in all_plots:
		if plot.type == "house":
			house_plots.append(plot)
		elif plot.type == "farm":
			farm_plots.append(plot)

	# Spawn one NPC per house, assign farms in order
	for i in range(house_plots.size()):
		var house_plot: Plot = house_plots[i]
		var npc_instance = npc_scene.instantiate()
		npc_instance.add_to_group("npcs")

		var home_pos: Vector2 = map_to_local(house_plot.door_position)
		var farm_pos := Vector2.ZERO
		if i < farm_plots.size():
			farm_pos = map_to_local(farm_plots[i].center)

		add_child(npc_instance)
		npc_instance.initialize(home_pos, farm_pos)
