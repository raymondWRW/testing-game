class_name TownData
extends Resource

## Unique identifier for this town (used as dictionary key in world).
@export var id: StringName = &""

## Human-readable display name.
@export var town_name: String = "Unnamed Town"

## Deterministic seed that fully reproduces the layout.
@export var town_seed: int = 12345

## Map dimensions in tiles.
@export var width: int = 160
@export var height: int = 100

## Building counts.
@export var num_houses: int = 6
@export var num_farms: int = 4

## Layout tuning.
@export var plot_margin: int = 2
@export var road_width: int = 2

## Position in the Voronoi world map.
@export var world_position: Vector2 = Vector2.ZERO

## Open-ended bag for future data (e.g., quest flags, shop inventory).
@export var metadata: Dictionary = {}

# -------------------- Persistence (runtime, not saved to .tres) --------------------

## Saved NPC states when player leaves the town.
var npc_states: Array[Dictionary] = []

## Saved economy simulation state.
var economy_state: Dictionary = {}

## Market wheat stock.
var market_wheat_stock: int = 0

## Whether this town has been visited (initialized).
var has_been_visited: bool = false

## Player's last position in this town.
var player_last_position: Vector2 = Vector2.ZERO

## Clear all runtime state (for fresh start)
func clear_runtime_state() -> void:
	npc_states.clear()
	economy_state.clear()
	market_wheat_stock = 0
	has_been_visited = false
	player_last_position = Vector2.ZERO
