extends Node2D

class_name Market

var source_id := 0

# Roof tile coordinates (2 rows) - same as house
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

# Market dimensions in tiles (smaller than house - matches MARKET_SIZE in ground.gd)
@export var market_width: int = 6
@export var market_height: int = 8

var tile_map: TileMapLayer

# Market inventory display
var wheat_label: Label

func _ready() -> void:
	_create_tilemap()
	_build_market()
	_create_label()

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
		WALL_LEFT, WALL_MID, WALL_RIGHT
	]

	for tile_coord in tiles_to_create:
		atlas_source.create_tile(tile_coord)

	new_tileset.add_source(atlas_source, source_id)
	tile_map.tile_set = new_tileset

	add_child(tile_map)

func _build_market() -> void:
	# Offset to center the market around position (0,0)
	var offset_x := -market_width / 2
	var offset_y := -market_height / 2

	for y in range(market_height):
		for x in range(market_width):
			var tile_coord: Vector2i
			var is_edge := (x == 0 or x == market_width - 1 or y == 0 or y == market_height - 1)

			if is_edge:
				# Edge tiles - walls (no door for market, it's open)
				if x == 0:
					tile_coord = WALL_LEFT
				elif x == market_width - 1:
					tile_coord = WALL_RIGHT
				else:
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

func _create_label() -> void:
	wheat_label = Label.new()
	wheat_label.text = "MARKET\nWheat: 0"
	wheat_label.position = Vector2(-30, -market_height * 8 - 20)
	wheat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var label_settings := LabelSettings.new()
	label_settings.font_size = 10
	label_settings.font_color = Color(1, 1, 0)  # Yellow
	label_settings.outline_size = 2
	label_settings.outline_color = Color(0, 0, 0)
	wheat_label.label_settings = label_settings

	add_child(wheat_label)

func update_stock_display(wheat_count: int) -> void:
	if wheat_label:
		wheat_label.text = "MARKET\nWheat: %d" % wheat_count
