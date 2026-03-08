extends CanvasLayer

## World map overlay showing Voronoi cells as town regions
## Press M to toggle visibility

signal town_selected(town_id: StringName)

## Scale factor for world to screen conversion
@export var map_scale: float = 0.08

## Colors
@export var cell_color: Color = Color(0.2, 0.4, 0.2, 0.7)
@export var current_cell_color: Color = Color(0.4, 0.6, 0.3, 0.9)
@export var neighbor_cell_color: Color = Color(0.3, 0.5, 0.3, 0.8)
@export var outline_color: Color = Color(0.1, 0.2, 0.1, 1.0)
@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var player_color: Color = Color(1.0, 0.3, 0.3, 1.0)

var voronoi_world: VoronoiWorld = null
var world_node: Node = null
var current_town_id: StringName = &""
var is_map_visible: bool = false

# UI elements
var map_panel: Control = null
var map_canvas: Control = null
var title_label: Label = null
var info_label: Label = null
var close_button: Button = null

# Map positioning
var map_offset: Vector2 = Vector2.ZERO
var map_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Ensure we can receive input even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_create_ui()
	visible = false

	# Find world node
	call_deferred("_find_world")

func _find_world() -> void:
	var parent := get_parent()
	if parent:
		world_node = parent.get_node_or_null("world")
		if world_node:
			voronoi_world = world_node.get_voronoi_world()
			if world_node.has_signal("town_loaded"):
				world_node.town_loaded.connect(_on_town_loaded)
			current_town_id = world_node.current_town_id

func _create_ui() -> void:
	# Main panel covering the screen
	map_panel = Panel.new()
	map_panel.name = "MapPanel"
	map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(map_panel)

	# Dark background style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.05, 0.95)
	map_panel.add_theme_stylebox_override("panel", style)

	# Title
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "World Map"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.position = Vector2(0, 20)
	title_label.add_theme_font_size_override("font_size", 24)
	map_panel.add_child(title_label)

	# Info label (bottom)
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Press M or ESC to close"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info_label.position = Vector2(0, -40)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	map_panel.add_child(info_label)

	# Map canvas for drawing
	map_canvas = Control.new()
	map_canvas.name = "MapCanvas"
	map_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_canvas.set_anchor(SIDE_TOP, 0.1)
	map_canvas.set_anchor(SIDE_BOTTOM, 0.9)
	map_canvas.set_anchor(SIDE_LEFT, 0.1)
	map_canvas.set_anchor(SIDE_RIGHT, 0.9)
	map_canvas.draw.connect(_on_canvas_draw)
	map_panel.add_child(map_canvas)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_M:
				toggle_map()
			KEY_ESCAPE:
				if is_map_visible:
					toggle_map()

func toggle_map() -> void:
	is_map_visible = not is_map_visible
	visible = is_map_visible

	if is_map_visible:
		# Update references
		if world_node:
			voronoi_world = world_node.get_voronoi_world()
			current_town_id = world_node.current_town_id

		# Pause the game
		get_tree().paused = true

		# Calculate map positioning
		_calculate_map_layout()

		# Redraw
		map_canvas.queue_redraw()
	else:
		# Unpause the game
		get_tree().paused = false

func _calculate_map_layout() -> void:
	if not voronoi_world:
		return

	var canvas_size := map_canvas.size
	var world_size := voronoi_world.world_size

	# Calculate scale to fit world in canvas
	var scale_x := canvas_size.x / world_size.x
	var scale_y := canvas_size.y / world_size.y
	map_scale = min(scale_x, scale_y) * 0.9  # 90% of available space

	# Center the map
	map_size = world_size * map_scale
	map_offset = (canvas_size - map_size) / 2

func _on_canvas_draw() -> void:
	if not voronoi_world:
		return

	var all_town_ids := voronoi_world.get_all_town_ids()
	var neighbor_ids: Array = voronoi_world.get_neighbors(current_town_id) if current_town_id != &"" else []

	# Draw all cells
	for town_id in all_town_ids:
		var polygon := voronoi_world.get_cell_polygon(town_id)
		if polygon.is_empty():
			continue

		# Transform to screen coordinates
		var screen_polygon := _transform_polygon(polygon)

		# Determine cell color
		var color: Color
		if town_id == current_town_id:
			color = current_cell_color
		elif town_id in neighbor_ids:
			color = neighbor_cell_color
		else:
			color = cell_color

		# Draw filled polygon
		if screen_polygon.size() >= 3:
			map_canvas.draw_colored_polygon(screen_polygon, color)

		# Draw outline
		if screen_polygon.size() >= 2:
			var outline := screen_polygon.duplicate()
			outline.append(screen_polygon[0])  # Close the polygon
			map_canvas.draw_polyline(outline, outline_color, 2.0)

	# Draw town names
	for town_id in all_town_ids:
		var center := voronoi_world.get_cell_center(town_id)
		var screen_center := _transform_point(center)

		# Get town name
		var town_name := str(town_id)
		if world_node:
			var town_data: TownData = world_node.get_town(town_id)
			if town_data:
				town_name = town_data.town_name

		# Draw name
		var font := ThemeDB.fallback_font
		var font_size := 12
		var text_size := font.get_string_size(town_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := screen_center - text_size / 2

		# Background for readability
		var bg_rect := Rect2(text_pos - Vector2(2, 2), text_size + Vector2(4, 4))
		map_canvas.draw_rect(bg_rect, Color(0, 0, 0, 0.5))

		# Text
		map_canvas.draw_string(font, text_pos + Vector2(0, font_size), town_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# Draw player marker
	if current_town_id != &"":
		var player_world_pos := voronoi_world.get_site_position(current_town_id)
		var player_screen_pos := _transform_point(player_world_pos)
		map_canvas.draw_circle(player_screen_pos, 8, player_color)
		map_canvas.draw_circle(player_screen_pos, 6, Color(1, 1, 1, 1))
		map_canvas.draw_circle(player_screen_pos, 4, player_color)

func _transform_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		result.append(_transform_point(point))
	return result

func _transform_point(world_point: Vector2) -> Vector2:
	return world_point * map_scale + map_offset

func _on_town_loaded(town: TownData) -> void:
	current_town_id = town.id
	if is_map_visible:
		map_canvas.queue_redraw()
