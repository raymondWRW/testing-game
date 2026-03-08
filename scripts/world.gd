class_name World
extends Node2D

## World manager - handles Voronoi-based town system and transitions

## All known towns. Auto-generated if empty.
@export var towns: Array[TownData] = []

## World generation seed.
@export var world_seed: int = 42

## Number of towns to generate.
@export var num_towns: int = 20

## World size for Voronoi diagram (abstract units).
@export var world_size: Vector2 = Vector2(10000, 10000)

## The id of the currently loaded town (empty = none).
var current_town_id: StringName = &""

## Voronoi diagram for the world map.
var voronoi_world: VoronoiWorld = null

## Quick lookup: id -> TownData. Built at _ready().
var _town_map: Dictionary = {}

## Reference to the ground child node.
@onready var ground: TileMapLayer = $ground

## Reference to the player (found dynamically).
var player: CharacterBody2D = null

signal town_loaded(town: TownData)
signal town_unloaded(town_id: StringName)
signal world_initialized()

func _ready() -> void:
	_find_player()
	_initialize_world()

func _find_player() -> void:
	# Find player as sibling
	var parent := get_parent()
	if parent:
		player = parent.get_node_or_null("player") as CharacterBody2D

func _initialize_world() -> void:
	# Generate towns if none exist
	if towns.is_empty():
		_generate_towns()

	_rebuild_town_map()
	_initialize_voronoi()
	_connect_player_signals()

	# Load the first town by default
	if towns.size() > 0:
		load_town(towns[0].id)

	world_initialized.emit()
	print("World initialized with %d towns" % towns.size())

func _generate_towns() -> void:
	var result := TownGenerator.generate_world(num_towns, world_seed, world_size)
	towns = result["towns"]
	voronoi_world = result["voronoi"]
	print("Generated %d towns" % towns.size())

func _initialize_voronoi() -> void:
	if voronoi_world != null:
		return  # Already initialized from generation

	voronoi_world = VoronoiWorld.new()
	voronoi_world.world_size = world_size

	for town in towns:
		voronoi_world.add_site(town.id, town.world_position)

	voronoi_world.compute_voronoi()
	print("Voronoi diagram computed")

func _connect_player_signals() -> void:
	if player and player.has_signal("reached_cell_edge"):
		if not player.reached_cell_edge.is_connected(_on_player_reached_edge):
			player.reached_cell_edge.connect(_on_player_reached_edge)

func _rebuild_town_map() -> void:
	_town_map.clear()
	for town in towns:
		assert(town.id != &"", "TownData is missing an id")
		_town_map[town.id] = town

## Switch to a different town by id.
func load_town(town_id: StringName) -> void:
	assert(_town_map.has(town_id), "Unknown town id: %s" % town_id)

	if current_town_id == town_id:
		return

	# Save current town state before switching
	if current_town_id != &"":
		_save_current_town_state()
		town_unloaded.emit(current_town_id)

	var old_id := current_town_id
	var town_data: TownData = _town_map[town_id]

	# Generate the town
	ground.generate(town_data)
	current_town_id = town_id

	# Restore state if previously visited
	if town_data.has_been_visited:
		# Wait for generation to complete
		await get_tree().process_frame
		await get_tree().process_frame
		_restore_town_state(town_data)
	else:
		town_data.has_been_visited = true

	# Update player's current town reference
	if player and player.has_method("set_current_town"):
		player.current_town_id = town_id
	elif player:
		player.set("current_town_id", town_id)

	# Update player's voronoi reference
	if player:
		player.set("voronoi_world", voronoi_world)
		player.set("world_node", self)

	town_loaded.emit(town_data)
	print("Loaded town: %s (%s)" % [town_data.town_name, town_id])

func _save_current_town_state() -> void:
	var town := get_current_town()
	if not town:
		return

	# Save player position
	if player:
		town.player_last_position = player.global_position

	# Save NPC states
	town.npc_states = ground.get_npc_states()

	# Save economy state
	town.economy_state = ground.get_economy_state()

	# Save market stock
	town.market_wheat_stock = ground.market_wheat_stock

	print("Saved state for town: %s (%d NPCs)" % [town.town_name, town.npc_states.size()])

func _restore_town_state(town: TownData) -> void:
	# Restore NPC states
	if town.npc_states.size() > 0:
		await ground.restore_npc_states(town.npc_states)

	# Restore economy state
	ground.restore_economy_state(town.economy_state)

	# Restore market stock
	ground.market_wheat_stock = town.market_wheat_stock
	ground._update_market_display()

	print("Restored state for town: %s" % town.town_name)

func _on_player_reached_edge(direction: Vector2, neighbor_id: StringName) -> void:
	if neighbor_id == &"" or neighbor_id == current_town_id:
		return

	print("Player reached edge, transitioning to: %s (direction: %s)" % [neighbor_id, direction])

	# Load the neighbor town
	load_town(neighbor_id)

	# Position player at opposite edge
	_position_player_at_entry(-direction)

func _position_player_at_entry(from_direction: Vector2) -> void:
	if not player or not ground:
		return

	# Get map dimensions
	var tile_size := ground.tile_set.tile_size if ground.tile_set else Vector2i(16, 16)
	var map_width: float = ground.width * tile_size.x
	var map_height: float = ground.height * tile_size.y

	# Calculate entry position based on direction player came from
	var entry_pos: Vector2
	var center := Vector2(map_width / 2, map_height / 2)

	if abs(from_direction.x) > abs(from_direction.y):
		# Horizontal transition
		if from_direction.x > 0:
			# Came from left, enter on left side
			entry_pos = Vector2(tile_size.x * 5, center.y)
		else:
			# Came from right, enter on right side
			entry_pos = Vector2(map_width - tile_size.x * 5, center.y)
	else:
		# Vertical transition
		if from_direction.y > 0:
			# Came from top, enter on top
			entry_pos = Vector2(center.x, tile_size.y * 5)
		else:
			# Came from bottom, enter on bottom
			entry_pos = Vector2(center.x, map_height - tile_size.y * 5)

	# Convert to global position
	var global_entry: Vector2 = ground.to_global(entry_pos)

	# Find nearest walkable cell
	var entry_cell: Vector2i = ground.world_to_cell(global_entry)
	if not ground.is_cell_walkable(entry_cell):
		entry_cell = ground.find_walkable_neighbor(entry_cell)
		global_entry = ground.cell_to_world(entry_cell)

	player.global_position = global_entry
	print("Player positioned at entry: %s (cell %s)" % [global_entry, entry_cell])

## Get the TownData for the currently loaded town.
func get_current_town() -> TownData:
	if current_town_id == &"":
		return null
	return _town_map.get(current_town_id)

## Look up any town by id.
func get_town(town_id: StringName) -> TownData:
	return _town_map.get(town_id)

## Add a new town at runtime.
func add_town(town: TownData) -> void:
	assert(town.id != &"", "TownData is missing an id")
	assert(not _town_map.has(town.id), "Duplicate town id: %s" % town.id)
	towns.append(town)
	_town_map[town.id] = town

	# Add to Voronoi
	if voronoi_world:
		voronoi_world.add_site(town.id, town.world_position)
		voronoi_world.compute_voronoi()

## Get the Voronoi world for map UI
func get_voronoi_world() -> VoronoiWorld:
	return voronoi_world

## Get all towns
func get_all_towns() -> Array[TownData]:
	return towns
