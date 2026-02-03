class_name World
extends Node2D

## All known towns. Populate in editor or via code.
@export var towns: Array[TownData] = []

## The id of the currently loaded town (empty = none).
var current_town_id: StringName = &""

## Quick lookup: id -> TownData. Built at _ready().
var _town_map: Dictionary = {}

## Reference to the ground child node.
@onready var ground: TileMapLayer = $ground

signal town_loaded(town: TownData)
signal town_unloaded(town_id: StringName)

func _ready() -> void:
	_rebuild_town_map()
	# Load the first town by default.
	if towns.size() > 0:
		load_town(towns[0].id)

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

	var old_id := current_town_id
	var town_data: TownData = _town_map[town_id]
	ground.generate(town_data)
	current_town_id = town_id

	if old_id != &"":
		town_unloaded.emit(old_id)
	town_loaded.emit(town_data)

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
