extends CharacterBody2D

enum Job { FARMER, WOODCUTTER }
enum State { IDLE_HOME, WALKING_TO_WORK, WORKING, WALKING_HOME, WALKING_TO_MARKET, AT_MARKET }

signal arrived_at_farm
signal collected_resource(item: String, amount: int)
signal wants_to_sell(npc: Node, wheat_amount: int)
signal wants_to_buy(npc: Node, wood_amount: int)

@export var speed := 80.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var inventory_label: Label = $InventoryLabel

# Job assignment
var job: Job = Job.FARMER
var job_name: String = "Farmer"

# Positions
var home_position: Vector2 = Vector2.ZERO
var work_position: Vector2 = Vector2.ZERO  # Farm for farmer, tree for woodcutter
var market_position: Vector2 = Vector2.ZERO
var has_work: bool = false
var has_market: bool = false

# Inventory system
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

	# Wait for navigation map to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	_nav_ready = true
	_last_position = position

	_update_inventory_display()

func initialize_farmer(home_pos: Vector2, farm_pos: Vector2) -> void:
	job = Job.FARMER
	job_name = "Farmer"
	home_position = home_pos
	position = home_pos
	if farm_pos != Vector2.ZERO:
		work_position = farm_pos
		has_work = true
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func initialize_woodcutter(home_pos: Vector2, tree_pos: Vector2) -> void:
	job = Job.WOODCUTTER
	job_name = "Woodcutter"
	home_position = home_pos
	position = home_pos
	if tree_pos != Vector2.ZERO:
		work_position = tree_pos
		has_work = true
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func set_market_position(pos: Vector2) -> void:
	market_position = pos
	has_market = pos != Vector2.ZERO

func set_work_position(pos: Vector2) -> void:
	work_position = pos
	has_work = pos != Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not _nav_ready:
		return

	# Debug: print state every few seconds
	if Engine.get_physics_frames() % 180 == 0:
		print("NPC [%s] state: %s, has_work: %s, timer: %.1f" % [job_name, State.keys()[_state], has_work, _idle_timer])

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
	_idle_timer -= delta

	if _idle_timer <= 0.0:
		# Decide what to do next
		if _should_go_to_market():
			_go_to_market()
		elif has_work:
			_state = State.WALKING_TO_WORK
			nav_agent.target_position = work_position
			_stuck_timer = 0.0
			_last_position = position

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
	nav_agent.target_position = market_position
	_stuck_timer = 0.0
	_last_position = position

func _process_walking_to_work(delta: float) -> void:
	if nav_agent.is_navigation_finished() or position.distance_to(work_position) < 16.0:
		velocity = Vector2.ZERO
		_state = State.WORKING
		_work_timer = randf_range(WORK_TIME_MIN, WORK_TIME_MAX)

		# Emit signal for farmers (to paint wheat)
		if job == Job.FARMER:
			arrived_at_farm.emit()
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_working(delta: float) -> void:
	velocity = Vector2.ZERO
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
	if nav_agent.is_navigation_finished() or position.distance_to(home_position) < 16.0:
		velocity = Vector2.ZERO
		_state = State.IDLE_HOME
		_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_walking_to_market(delta: float) -> void:
	if nav_agent.is_navigation_finished() or position.distance_to(market_position) < 16.0:
		velocity = Vector2.ZERO
		_state = State.AT_MARKET
		_work_timer = MARKET_TIME
		return

	_check_stuck(delta)
	_move_toward_next_path_point()

func _process_at_market(delta: float) -> void:
	velocity = Vector2.ZERO
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
	nav_agent.target_position = home_position
	_stuck_timer = 0.0
	_last_position = position

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
	for item in inventory.keys():
		if inventory[item] > 0:
			display_text += "%s: %d\n" % [item, inventory[item]]

	if _get_total_items() == 0:
		display_text += "(empty)"

	inventory_label.text = display_text

func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer >= STUCK_THRESHOLD:
		var distance_moved := position.distance_to(_last_position)
		if distance_moved < STUCK_DISTANCE:
			_handle_stuck()
		_stuck_timer = 0.0
		_last_position = position

func _handle_stuck() -> void:
	var to_target := (nav_agent.target_position - position).normalized()
	var perpendicular := Vector2(-to_target.y, to_target.x)
	if randf() > 0.5:
		perpendicular = -perpendicular
	velocity = perpendicular * speed
	move_and_slide()

func _move_toward_next_path_point() -> void:
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - position).normalized()

	# Debug navigation issues
	if Engine.get_physics_frames() % 60 == 0:
		print("Nav debug - pos: %s, next: %s, target: %s, finished: %s" % [position, next_pos, nav_agent.target_position, nav_agent.is_navigation_finished()])

	if direction.is_finite() and direction.length_squared() > 0.01:
		velocity = direction * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
