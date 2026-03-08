extends CharacterBody2D

## Player controller with edge detection for town transitions

signal reached_cell_edge(direction: Vector2, neighbor_town_id: StringName)

@export var speed := 260.0

## Reference to the world node (set by World)
var world_node: Node = null

## Voronoi world for neighbor lookup (set by World)
var voronoi_world: VoronoiWorld = null

## Current town ID (set by World)
var current_town_id: StringName = &""

## Edge detection settings
const EDGE_CHECK_INTERVAL: float = 0.1
const EDGE_MARGIN: int = 3  # Tiles from edge to trigger transition

var _edge_check_timer: float = 0.0
var _ground_node: Node = null

func _ready():
	print("Player script is running")
	print("ready, paused?", get_tree().paused)
	print("physics processing?", is_physics_processing())

	# Find ground node for boundary checking
	call_deferred("_find_ground")

func _find_ground() -> void:
	# Find ground node as sibling of world
	var parent := get_parent()
	if parent:
		var world := parent.get_node_or_null("world")
		if world:
			_ground_node = world.get_node_or_null("ground")

func _physics_process(delta: float) -> void:
	# Movement
	var x := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	var direction := Vector2(x, y).normalized()
	velocity = direction * speed
	move_and_slide()

	# Edge detection for town transitions
	_edge_check_timer += delta
	if _edge_check_timer >= EDGE_CHECK_INTERVAL:
		_edge_check_timer = 0.0
		_check_cell_boundary()

func _check_cell_boundary() -> void:
	if not _ground_node or not voronoi_world or current_town_id == &"":
		return

	if not _ground_node.has_method("world_to_cell"):
		return

	# Get current cell position
	var cell: Vector2i = _ground_node.world_to_cell(global_position)
	var map_bounds: Rect2i = _ground_node.get_map_bounds()

	var near_edge := false
	var edge_direction := Vector2.ZERO

	# Check if near any map edge
	if cell.x <= EDGE_MARGIN:
		near_edge = true
		edge_direction = Vector2.LEFT
	elif cell.x >= map_bounds.size.x - EDGE_MARGIN - 1:
		near_edge = true
		edge_direction = Vector2.RIGHT

	if cell.y <= EDGE_MARGIN:
		near_edge = true
		edge_direction = Vector2.UP
	elif cell.y >= map_bounds.size.y - EDGE_MARGIN - 1:
		near_edge = true
		edge_direction = Vector2.DOWN

	if near_edge:
		# Get neighbor town in this direction
		var neighbor_id := voronoi_world.get_neighbor_in_direction(current_town_id, edge_direction)
		if neighbor_id != &"" and neighbor_id != current_town_id:
			print("Player near edge (cell %s), direction: %s, neighbor: %s" % [cell, edge_direction, neighbor_id])
			reached_cell_edge.emit(edge_direction, neighbor_id)
