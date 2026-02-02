extends Node2D

class_name House

var source_id := 0

# Roof tile coordinates (2 rows)
const ROOF_TOP_LEFT: Vector2i = Vector2i(0, 4)
const ROOF_TOP_MID: Vector2i = Vector2i(1, 4)
const ROOF_TOP_RIGHT: Vector2i = Vector2i(2, 4)
const ROOF_BOT_LEFT: Vector2i = Vector2i(0, 5)
const ROOF_BOT_MID: Vector2i = Vector2i(1, 5)
const ROOF_BOT_RIGHT: Vector2i = Vector2i(2, 5)

# Wall tile coordinates
const WALL_LEFT: Vector2i = Vector2i(0, 6)
const WALL_MID: Vector2i = Vector2i(1, 6)
const WALL_RIGHT: Vector2i = Vector2i(3, 6)

# Door tile
const DOOR: Vector2i = Vector2i(1, 7)

# House dimensions in tiles (matches HOUSE_SIZE in ground.gd)
@export var house_width: int = 8
@export var house_height: int = 12

var tile_map: TileMapLayer

func _init() -> void:
	pass

func _ready() -> void:
	_create_tilemap()
	_build_house()

func _create_tilemap() -> void:
	tile_map = TileMapLayer.new()

	# Create a new tileset using the same texture
	var new_tileset := TileSet.new()
	new_tileset.tile_size = Vector2i(16, 16)

	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = preload("res://assets/Tilemap/tilemap_packed.png")
	atlas_source.texture_region_size = Vector2i(16, 16)

	# Create tiles for all coordinates we need
	var tiles_to_create: Array[Vector2i] = [
		ROOF_TOP_LEFT, ROOF_TOP_MID, ROOF_TOP_RIGHT,
		ROOF_BOT_LEFT, ROOF_BOT_MID, ROOF_BOT_RIGHT,
		WALL_LEFT, WALL_MID, WALL_RIGHT, DOOR
	]

	for tile_coord in tiles_to_create:
		atlas_source.create_tile(tile_coord)

	new_tileset.add_source(atlas_source, source_id)
	tile_map.tile_set = new_tileset

	add_child(tile_map)

func _build_house() -> void:
	# Offset to center the house around position (0,0)
	var offset_x := -house_width / 2
	var offset_y := -house_height / 2

	# Door position (bottom edge, center)
	var door_x := house_width / 2

	for y in range(house_height):
		for x in range(house_width):
			var tile_coord: Vector2i
			var is_edge := (x == 0 or x == house_width - 1 or y == 0 or y == house_height - 1)

			if is_edge:
				# Edge tiles - walls
				if x == door_x and y == house_height - 1:
					# Door on bottom edge
					tile_coord = DOOR
				elif x == 0:
					# Left edge
					tile_coord = WALL_LEFT
				elif x == house_width - 1:
					# Right edge
					tile_coord = WALL_RIGHT
				else:
					# Top/bottom edges
					tile_coord = WALL_MID
			else:
				# Interior - roof tiles
				var roof_row := y % 2
				var roof_col := x % 3

				if roof_row == 0:
					match roof_col:
						0: tile_coord = ROOF_TOP_LEFT
						1: tile_coord = ROOF_TOP_MID
						_: tile_coord = ROOF_TOP_RIGHT
				else:
					match roof_col:
						0: tile_coord = ROOF_BOT_LEFT
						1: tile_coord = ROOF_BOT_MID
						_: tile_coord = ROOF_BOT_RIGHT

			tile_map.set_cell(Vector2i(x + offset_x, y + offset_y), source_id, tile_coord)

# Static factory method to create a house at a position
static func create_at(pos: Vector2) -> House:
	var house := House.new()
	house.position = pos
	return house
