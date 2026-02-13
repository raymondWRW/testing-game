extends CharacterBody2D

enum State { IDLE_HOME, WALKING_TO_FARM, IDLE_FARM, WALKING_HOME }

signal arrived_at_farm

@export var speed := 80.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

var home_position: Vector2 = Vector2.ZERO
var farm_position: Vector2 = Vector2.ZERO
var has_farm: bool = false
var _nav_ready: bool = false

var _state: State = State.IDLE_HOME
var _idle_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

const IDLE_HOME_MIN := 3.0
const IDLE_HOME_MAX := 8.0
const IDLE_FARM_MIN := 5.0
const IDLE_FARM_MAX := 12.0
const STUCK_THRESHOLD := 2.0  # seconds before considered stuck
const STUCK_DISTANCE := 5.0   # minimum movement to not be stuck

func _ready() -> void:
	# Wait for navigation map to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	_nav_ready = true
	_last_position = global_position

func initialize(home_pos: Vector2, farm_pos: Vector2 = Vector2.ZERO) -> void:
	home_position = home_pos
	global_position = home_pos
	if farm_pos != Vector2.ZERO:
		farm_position = farm_pos
		has_farm = true
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func _physics_process(delta: float) -> void:
	if not _nav_ready:
		return

	match _state:
		State.IDLE_HOME:
			_process_idle_home(delta)
		State.WALKING_TO_FARM:
			_process_walking(delta, farm_position, State.IDLE_FARM, true)
		State.IDLE_FARM:
			_process_idle_farm(delta)
		State.WALKING_HOME:
			_process_walking(delta, home_position, State.IDLE_HOME, false)

func _process_idle_home(delta: float) -> void:
	velocity = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0.0 and has_farm:
		_state = State.WALKING_TO_FARM
		nav_agent.target_position = farm_position
		_stuck_timer = 0.0
		_last_position = global_position

func _process_idle_farm(delta: float) -> void:
	velocity = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_state = State.WALKING_HOME
		nav_agent.target_position = home_position
		_stuck_timer = 0.0
		_last_position = global_position

func _process_walking(delta: float, target: Vector2, next_state: State, emit_signal: bool) -> void:
	# Check if we've arrived
	if nav_agent.is_navigation_finished() or global_position.distance_to(target) < 16.0:
		velocity = Vector2.ZERO
		_state = next_state
		if next_state == State.IDLE_HOME:
			_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)
		else:
			_idle_timer = randf_range(IDLE_FARM_MIN, IDLE_FARM_MAX)
		if emit_signal:
			arrived_at_farm.emit()
		return

	# Check if stuck
	_stuck_timer += delta
	if _stuck_timer >= STUCK_THRESHOLD:
		var distance_moved := global_position.distance_to(_last_position)
		if distance_moved < STUCK_DISTANCE:
			# We're stuck - try to move around obstacle
			_handle_stuck()
		_stuck_timer = 0.0
		_last_position = global_position

	_move_toward_next_path_point()

func _handle_stuck() -> void:
	# Try to nudge in a perpendicular direction
	var to_target := (nav_agent.target_position - global_position).normalized()
	var perpendicular := Vector2(-to_target.y, to_target.x)
	# Randomly pick left or right
	if randf() > 0.5:
		perpendicular = -perpendicular
	velocity = perpendicular * speed
	move_and_slide()

func _move_toward_next_path_point() -> void:
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()

	# Check for valid direction to avoid NaN issues
	if direction.is_finite() and direction.length_squared() > 0.01:
		velocity = direction * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
