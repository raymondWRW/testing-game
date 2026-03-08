extends CharacterBody2D

enum Job { FARMER, WOODCUTTER, NOBLE }
enum State { IDLE_HOME, WALKING_TO_WORK, WORKING, WALKING_HOME, WALKING_TO_MARKET, AT_MARKET }

signal arrived_at_farm
signal collected_resource(item: String, amount: int)
signal wants_to_sell(npc: Node, wheat_amount: int)
signal wants_to_buy(npc: Node, wood_amount: int)

@export var speed := 80.0

@onready var inventory_label: Label = $InventoryLabel

# Grid-based pathfinding and movement
var _ground_node: Node = null
var _current_path: Array[Vector2i] = []  # Path as grid cells
var _path_index: int = 0
var _current_cell: Vector2i = Vector2i.ZERO  # Current grid cell
var _target_cell: Vector2i = Vector2i.ZERO   # Cell we're moving toward
var _moving_to_cell: bool = false            # Are we in transit between cells?

# Job assignment
var job: Job = Job.FARMER
var job_name: String = "Farmer"

# Positions
var home_position: Vector2 = Vector2.ZERO
var work_position: Vector2 = Vector2.ZERO  # Farm for farmer, tree for woodcutter
var market_position: Vector2 = Vector2.ZERO
var has_work: bool = false
var has_market: bool = false

# Economic simulation resources (from npc_simulation.py)
var food: float = 100.0
var wood: float = 50.0
var gold: float = 50.0
var _alive: bool = true

# Inventory system (for visual/local behavior)
var inventory: Dictionary = {}  # { "wheat": 0, "wood": 0 }
const MAX_CARRY := 10  # Max items before returning home
const SELL_THRESHOLD := 5  # Sell wheat above this amount
const BUY_THRESHOLD := 5  # Buy wheat if below this amount

# State machine
var _nav_ready: bool = false
var _state: State = State.IDLE_HOME
var _idle_timer: float = 0.0
var _work_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

# Timing constants
const IDLE_HOME_MIN := 2.0
const IDLE_HOME_MAX := 5.0
const WORK_TIME_MIN := 3.0
const WORK_TIME_MAX := 6.0
const MARKET_TIME := 1.0
const STUCK_THRESHOLD := 2.0
const STUCK_DISTANCE := 5.0

func _ready() -> void:
	# Initialize inventory
	inventory = { "wheat": 0, "wood": 0 }

	# Get reference to ground node for pathfinding
	_ground_node = get_parent()

	# Register with economy simulation if it exists
	var economy := _get_economy_simulation()
	if economy:
		economy.register_npc(self)

	# Wait for grid to be ready
	call_deferred("_init_navigation")

func _get_economy_simulation() -> Node:
	# Check if parent (ground) has economy simulation as sibling
	var parent := get_parent()
	if parent:
		# Direct child of parent
		for child in parent.get_children():
			if child is EconomySimulation:
				return child
		# Also check if parent has it as a named node
		if parent.has_node("EconomySimulation"):
			return parent.get_node("EconomySimulation")

	# Search the entire tree as fallback
	return _find_economy_in_tree(get_tree().root)

func _find_economy_in_tree(node: Node) -> Node:
	if node is EconomySimulation:
		return node
	for child in node.get_children():
		var found := _find_economy_in_tree(child)
		if found:
			return found
	return null

# Economic simulation methods (interface for EconomySimulation)
func is_alive() -> bool:
	return _alive

func set_alive(value: bool) -> void:
	_alive = value
	if not _alive:
		# Visual indication of death
		modulate = Color(0.3, 0.3, 0.3, 0.5)
		set_physics_process(false)

func get_economic_role() -> int:
	# Returns EconomySimulation.Role enum value
	match job:
		Job.FARMER: return 0  # Role.FARMER
		Job.WOODCUTTER: return 1  # Role.LUMBERJACK
		Job.NOBLE: return 2  # Role.NOBLE
	return 0

func get_monthly_food_need() -> int:
	return 5

func get_monthly_wood_need(season: int) -> int:
	# Season: 0=Spring, 1=Summer, 2=Fall, 3=Winter
	if season == 3:  # Winter
		return 5
	return 1

func get_months_of_food() -> float:
	var need := get_monthly_food_need()
	if need == 0:
		return INF
	return food / need

func get_months_of_wood(season: int) -> float:
	var need := get_monthly_wood_need(season)
	if need == 0:
		return INF
	return wood / need

func _init_navigation() -> void:
	# Wait for ground's astar_grid to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame

	_nav_ready = true
	_last_position = global_position

	# Initialize current cell from position
	if _ground_node and _ground_node.has_method("world_to_cell"):
		_current_cell = _ground_node.world_to_cell(global_position)
		# Snap to cell center
		global_position = _ground_node.cell_to_world(_current_cell)

	print("NPC [%s] ready at cell: %s, home: %s, work: %s" % [job_name, _current_cell, home_position, work_position])
	_update_inventory_display()

func initialize_farmer(home_pos: Vector2, farm_pos: Vector2) -> void:
	job = Job.FARMER
	job_name = "Farmer"
	home_position = home_pos
	global_position = home_pos
	if farm_pos != Vector2.ZERO:
		work_position = farm_pos
		has_work = true
		print("Farmer initialized - Home: %s, Farm: %s" % [home_pos, farm_pos])
	else:
		print("Warning: Farmer has no farm assigned!")
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func initialize_woodcutter(home_pos: Vector2, tree_pos: Vector2) -> void:
	job = Job.WOODCUTTER
	job_name = "Woodcutter"
	home_position = home_pos
	global_position = home_pos
	if tree_pos != Vector2.ZERO:
		work_position = tree_pos
		has_work = true
		print("Woodcutter initialized - Home: %s, Tree: %s" % [home_pos, tree_pos])
	else:
		print("Warning: Woodcutter has no tree assigned!")
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func initialize_noble(home_pos: Vector2) -> void:
	job = Job.NOBLE
	job_name = "Noble"
	home_position = home_pos
	global_position = home_pos
	has_work = false  # Nobles don't work
	# Nobles start with more gold
	gold = 200.0
	food = 150.0
	wood = 100.0
	print("Noble initialized - Home: %s" % home_pos)
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func initialize_with_resources(role: int, home_pos: Vector2, init_food: float, init_wood: float, init_gold: float) -> void:
	# Used for spawning new NPCs from replication
	food = init_food
	wood = init_wood
	gold = init_gold
	match role:
		0:  # FARMER
			initialize_farmer(home_pos, Vector2.ZERO)  # Will need work assigned later
		1:  # LUMBERJACK
			initialize_woodcutter(home_pos, Vector2.ZERO)  # Will need work assigned later
		2:  # NOBLE
			initialize_noble(home_pos)

func set_market_position(pos: Vector2) -> void:
	market_position = pos
	has_market = pos != Vector2.ZERO

func set_work_position(pos: Vector2) -> void:
	work_position = pos
	has_work = pos != Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not _nav_ready or not _alive:
		return

	# Debug: print state every few seconds
	if Engine.get_physics_frames() % 300 == 0:  # Less frequent but more detailed
		print("NPC [%s] state: %s, pos: %s, has_work: %s, F:%.0f W:%.0f G:%.0f" % [
			job_name,
			State.keys()[_state],
			global_position,
			has_work,
			food, wood, gold
		])

	match _state:
		State.IDLE_HOME:
			_process_idle_home(delta)
		State.WALKING_TO_WORK:
			_process_walking_to_work(delta)
		State.WORKING:
			_process_working(delta)
		State.WALKING_HOME:
			_process_walking_home(delta)
		State.WALKING_TO_MARKET:
			_process_walking_to_market(delta)
		State.AT_MARKET:
			_process_at_market(delta)

func _process_idle_home(delta: float) -> void:
	velocity = Vector2.ZERO
	_moving_to_cell = false
	_idle_timer -= delta

	if _idle_timer <= 0.0:
		# Update inventory display periodically
		_update_inventory_display()

		# Nobles mostly stay home (occasionally go to market)
		if job == Job.NOBLE:
			if _should_go_to_market():
				_go_to_market()
			else:
				# Stay home longer
				_idle_timer = randf_range(IDLE_HOME_MIN * 2, IDLE_HOME_MAX * 2)
			return

		# Decide what to do next
		if _should_go_to_market():
			_go_to_market()
		elif has_work:
			_state = State.WALKING_TO_WORK
			_moving_to_cell = false
			_request_path(work_position)
			_stuck_timer = 0.0
			_last_position = global_position

func _should_go_to_market() -> bool:
	if not has_market:
		return false

	match job:
		Job.FARMER:
			# Farmers sell wheat if they have more than threshold
			return inventory.get("wheat", 0) > SELL_THRESHOLD
		Job.WOODCUTTER:
			# Woodcutters buy wheat if they have wood and wheat below threshold
			return inventory.get("wood", 0) > 0 and inventory.get("wheat", 0) < BUY_THRESHOLD

	return false

func _go_to_market() -> void:
	_state = State.WALKING_TO_MARKET
	_moving_to_cell = false
	_request_path(market_position)
	_stuck_timer = 0.0
	_last_position = global_position

func _process_walking_to_work(delta: float) -> void:
	# Check arrival using both path completion and cell proximity
	var work_cell := Vector2i.ZERO
	if _ground_node and _ground_node.has_method("world_to_cell"):
		work_cell = _ground_node.world_to_cell(work_position)

	var at_work := _is_path_finished() or _current_cell == work_cell or global_position.distance_to(work_position) < 16.0

	if at_work:
		velocity = Vector2.ZERO
		_moving_to_cell = false
		_state = State.WORKING
		_work_timer = randf_range(WORK_TIME_MIN, WORK_TIME_MAX)
		print("NPC [%s] arrived at work (cell %s), starting work timer: %.1f" % [job_name, _current_cell, _work_timer])

		# Emit signal for farmers (to paint wheat)
		if job == Job.FARMER:
			arrived_at_farm.emit()
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_working(delta: float) -> void:
	velocity = Vector2.ZERO
	_moving_to_cell = false
	_work_timer -= delta

	if _work_timer <= 0.0:
		# Collect resource based on job
		_collect_resource()

		# Check if inventory is full or should continue working
		if _get_total_items() >= MAX_CARRY:
			# Inventory full, go home
			_go_home()
		else:
			# Continue working (collect more)
			_work_timer = randf_range(WORK_TIME_MIN, WORK_TIME_MAX)

func _process_walking_home(delta: float) -> void:
	# Check arrival using both path completion and cell proximity
	var home_cell := Vector2i.ZERO
	if _ground_node and _ground_node.has_method("world_to_cell"):
		home_cell = _ground_node.world_to_cell(home_position)

	var at_home := _is_path_finished() or _current_cell == home_cell or global_position.distance_to(home_position) < 16.0

	if at_home:
		velocity = Vector2.ZERO
		_moving_to_cell = false
		_state = State.IDLE_HOME
		_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)
		print("NPC [%s] arrived home (cell %s), idle timer: %.1f" % [job_name, _current_cell, _idle_timer])
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_walking_to_market(delta: float) -> void:
	# Check arrival using both path completion and cell proximity
	var market_cell := Vector2i.ZERO
	if _ground_node and _ground_node.has_method("world_to_cell"):
		market_cell = _ground_node.world_to_cell(market_position)

	var at_market := _is_path_finished() or _current_cell == market_cell or global_position.distance_to(market_position) < 16.0

	if at_market:
		velocity = Vector2.ZERO
		_moving_to_cell = false
		_state = State.AT_MARKET
		_work_timer = MARKET_TIME
		print("NPC [%s] arrived at market (cell %s)" % [job_name, _current_cell])
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_at_market(delta: float) -> void:
	velocity = Vector2.ZERO
	_moving_to_cell = false
	_work_timer -= delta

	if _work_timer <= 0.0:
		# Perform trade
		_do_market_trade()
		# Go home after trading
		_go_home()

func _do_market_trade() -> void:
	match job:
		Job.FARMER:
			# Sell excess wheat (keep SELL_THRESHOLD)
			var current_wheat: int = inventory.get("wheat", 0)
			var wheat_to_sell: int = current_wheat - SELL_THRESHOLD
			if wheat_to_sell > 0:
				inventory["wheat"] = SELL_THRESHOLD
				wants_to_sell.emit(self, wheat_to_sell)
		Job.WOODCUTTER:
			# Buy wheat with wood (1:1 trade)
			var wood_available: int = inventory.get("wood", 0)
			var current_wheat: int = inventory.get("wheat", 0)
			var wheat_needed: int = BUY_THRESHOLD - current_wheat
			if wood_available > 0 and wheat_needed > 0:
				wants_to_buy.emit(self, mini(wood_available, wheat_needed))

	_update_inventory_display()

func receive_wheat(amount: int) -> void:
	# Called when market gives wheat to woodcutter
	inventory["wheat"] = inventory.get("wheat", 0) + amount
	_update_inventory_display()

func spend_wood(amount: int) -> void:
	# Called when woodcutter spends wood at market
	inventory["wood"] = max(0, inventory.get("wood", 0) - amount)
	_update_inventory_display()

func _go_home() -> void:
	_state = State.WALKING_HOME
	_moving_to_cell = false
	_request_path(home_position)
	_stuck_timer = 0.0
	_last_position = global_position
	print("NPC [%s] going home from cell %s to %s" % [job_name, _current_cell, home_position])

func _collect_resource() -> void:
	var item: String
	var amount := 1

	match job:
		Job.FARMER:
			item = "wheat"
		Job.WOODCUTTER:
			item = "wood"

	inventory[item] = inventory.get(item, 0) + amount
	collected_resource.emit(item, amount)
	_update_inventory_display()

func _get_total_items() -> int:
	var total := 0
	for value in inventory.values():
		total += value
	return total

func _update_inventory_display() -> void:
	if not inventory_label:
		return

	var display_text := "[%s]\n" % job_name
	# Show economic resources
	display_text += "F:%d W:%d G:%d\n" % [int(food), int(wood), int(gold)]
	# Show carried items
	for item in inventory.keys():
		if inventory[item] > 0:
			display_text += "%s: %d\n" % [item, inventory[item]]

	inventory_label.text = display_text

func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer >= STUCK_THRESHOLD:
		var distance_moved := global_position.distance_to(_last_position)
		if distance_moved < STUCK_DISTANCE:
			print("NPC [%s] appears stuck at cell %s, finding escape" % [job_name, _current_cell])
			_handle_stuck()
		_stuck_timer = 0.0
		_last_position = global_position

func _handle_stuck() -> void:
	# Find a valid walkable neighbor cell instead of random direction
	if not _ground_node or not _ground_node.has_method("find_walkable_neighbor"):
		return

	# First, teleport to a walkable cell if we're in a blocked one
	if _ground_node.has_method("is_cell_walkable") and not _ground_node.is_cell_walkable(_current_cell):
		var escape_cell: Vector2i = _ground_node.find_walkable_neighbor(_current_cell)
		if escape_cell != _current_cell:
			print("NPC [%s] stuck in blocked cell %s, teleporting to %s" % [job_name, _current_cell, escape_cell])
			_current_cell = escape_cell
			global_position = _ground_node.cell_to_world(escape_cell)

	# Skip to next path point if we have one
	if _path_index < _current_path.size() - 1:
		_path_index += 1
		if _path_index < _current_path.size():
			_target_cell = _current_path[_path_index]
			_moving_to_cell = true
			print("NPC [%s] skipping to path index %d, target cell %s" % [job_name, _path_index, _target_cell])

# Request a new path from current position to target (stores as grid cells)
func _request_path(target: Vector2) -> void:
	_current_path.clear()
	_path_index = 0
	_moving_to_cell = false

	if not _ground_node:
		print("NPC [%s] no ground node for pathfinding!" % [job_name])
		return

	if not _ground_node.has_method("world_to_cell"):
		print("NPC [%s] ground node missing grid methods!" % [job_name])
		return

	# Check if NPC is in a blocked cell (e.g., inside a house)
	# If so, teleport to nearest walkable cell first
	_current_cell = _ground_node.world_to_cell(global_position)
	var is_walkable_method: bool = _ground_node.has_method("is_cell_walkable")
	var is_blocked: bool = is_walkable_method and not _ground_node.is_cell_walkable(_current_cell)
	print("NPC [%s] requesting path - current cell %s, blocked: %s" % [job_name, _current_cell, is_blocked])

	if is_blocked:
		var walkable_cell: Vector2i = _ground_node.find_walkable_neighbor(_current_cell)
		if walkable_cell != _current_cell:
			print("NPC [%s] teleporting from blocked cell %s to walkable cell %s" % [job_name, _current_cell, walkable_cell])
			_current_cell = walkable_cell
			global_position = _ground_node.cell_to_world(walkable_cell)

	# Get path as grid cells
	var target_cell: Vector2i = _ground_node.world_to_cell(target)
	var world_path: PackedVector2Array = _ground_node.get_grid_path(global_position, target)

	# Convert world path to cell path
	for world_pos in world_path:
		var cell: Vector2i = _ground_node.world_to_cell(world_pos)
		# Avoid duplicates
		if _current_path.size() == 0 or _current_path[-1] != cell:
			_current_path.append(cell)

	if _current_path.size() > 0:
		print("NPC [%s] got grid path with %d cells" % [job_name, _current_path.size()])
		# Start moving to first cell if different from current
		if _current_path[0] != _current_cell:
			_target_cell = _current_path[0]
			_moving_to_cell = true
		elif _current_path.size() > 1:
			_path_index = 1
			_target_cell = _current_path[1]
			_moving_to_cell = true
	else:
		print("NPC [%s] failed to get path to cell %s" % [job_name, target_cell])

func _is_path_finished() -> bool:
	return _path_index >= _current_path.size() and not _moving_to_cell

func _move_toward_next_path_point() -> void:
	if not _ground_node:
		velocity = Vector2.ZERO
		return

	# If we're not currently moving to a cell, get the next one
	if not _moving_to_cell:
		if _path_index >= _current_path.size():
			velocity = Vector2.ZERO
			return

		_target_cell = _current_path[_path_index]

		# Validate target cell is walkable
		if _ground_node.has_method("is_cell_walkable") and not _ground_node.is_cell_walkable(_target_cell):
			print("NPC [%s] target cell %s is blocked, skipping" % [job_name, _target_cell])
			# Skip this cell and try next
			_path_index += 1
			if _path_index >= _current_path.size():
				velocity = Vector2.ZERO
				return
			_target_cell = _current_path[_path_index]

		_moving_to_cell = true

	# Get world position of target cell
	var target_world: Vector2 = _ground_node.cell_to_world(_target_cell)
	var distance := global_position.distance_to(target_world)

	# Check if we've reached the target cell
	if distance < 4.0:  # Tight threshold for cell-to-cell movement
		# Snap to cell center
		global_position = target_world
		_current_cell = _target_cell
		_moving_to_cell = false
		_path_index += 1
		velocity = Vector2.ZERO
		return

	# Move toward target cell center
	var direction := (target_world - global_position).normalized()

	if direction.is_finite() and direction.length_squared() > 0.01:
		velocity = direction * speed
		# Debug movement (less frequent)
		if Engine.get_physics_frames() % 120 == 0:
			print("NPC [%s] moving: pos=%s, target=%s, vel=%s, dist=%.1f" % [
				job_name, global_position, target_world, velocity, distance
			])
	else:
		velocity = Vector2.ZERO
		print("NPC [%s] invalid direction: pos=%s, target=%s" % [job_name, global_position, target_world])

	move_and_slide()

	# Clamp position to map bounds as safety
	if _ground_node.has_method("clamp_to_map"):
		var clamped: Vector2 = _ground_node.clamp_to_map(global_position)
		if clamped.distance_to(global_position) > 1.0:
			global_position = clamped
			_current_cell = _ground_node.world_to_cell(global_position)
