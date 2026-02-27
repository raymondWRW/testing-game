extends CanvasLayer

## UI overlay showing economic simulation status

@onready var info_label: Label = $InfoPanel/InfoLabel
@onready var speed_label: Label = $InfoPanel/SpeedLabel

var economy: EconomySimulation = null
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5

func _ready() -> void:
	_create_ui()
	# Find economy simulation after a short delay
	call_deferred("_find_economy")

func _find_economy() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Search for EconomySimulation in the tree
	economy = _find_economy_node(get_tree().root)
	if economy:
		economy.month_changed.connect(_on_month_changed)
		economy.simulation_stats_updated.connect(_on_stats_updated)
		print("SimulationUI connected to economy simulation")
	else:
		print("SimulationUI: No economy simulation found")

func _find_economy_node(node: Node) -> EconomySimulation:
	if node is EconomySimulation:
		return node
	for child in node.get_children():
		var found := _find_economy_node(child)
		if found:
			return found
	return null

func _create_ui() -> void:
	# Create info panel
	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(10, 10)
	panel.custom_minimum_size = Vector2(200, 120)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Info label
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Year 1, Month 1\nSpring\nPopulation: 0"
	vbox.add_child(info_label)

	# Speed control label
	speed_label = Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.text = "Speed: 1x (10s/month)"
	speed_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(speed_label)

	# Help text
	var help_label := Label.new()
	help_label.text = "[+/-] Speed | [P] Pause"
	help_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(help_label)

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_display()

func _input(event: InputEvent) -> void:
	if not economy:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_EQUAL, KEY_KP_ADD:  # + key
				economy.seconds_per_month = maxf(1.0, economy.seconds_per_month / 2.0)
				_update_speed_display()
			KEY_MINUS, KEY_KP_SUBTRACT:  # - key
				economy.seconds_per_month = minf(60.0, economy.seconds_per_month * 2.0)
				_update_speed_display()
			KEY_P:  # Pause
				economy.auto_simulate = not economy.auto_simulate
				_update_speed_display()

func _update_display() -> void:
	if not economy:
		info_label.text = "No simulation"
		return

	var season := economy.get_season_name()
	var alive := economy.get_alive_npcs()
	var pop_by_role := economy.get_population_by_role()

	var text := "Year %d, Month %d\n" % [economy.year, economy.month]
	text += "%s\n" % season
	text += "Population: %d\n" % alive.size()
	text += "  Farmers: %d\n" % pop_by_role[EconomySimulation.Role.FARMER]
	text += "  Lumberjacks: %d\n" % pop_by_role[EconomySimulation.Role.LUMBERJACK]
	text += "  Nobles: %d" % pop_by_role[EconomySimulation.Role.NOBLE]

	info_label.text = text

func _update_speed_display() -> void:
	if not economy:
		return

	var speed_multiplier := 10.0 / economy.seconds_per_month
	var paused := " (PAUSED)" if not economy.auto_simulate else ""
	speed_label.text = "Speed: %.1fx (%.0fs/month)%s" % [speed_multiplier, economy.seconds_per_month, paused]

func _on_month_changed(year: int, month: int, season: String) -> void:
	_update_display()

func _on_stats_updated(stats: Dictionary) -> void:
	_update_display()
