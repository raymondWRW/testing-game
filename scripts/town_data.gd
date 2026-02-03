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

## Open-ended bag for future data (e.g., quest flags, shop inventory).
@export var metadata: Dictionary = {}
