extends CharacterBody2D

enum State { IDLE_HOME, WALKING_TO_FARM, IDLE_FARM, WALKING_HOME }

@export var speed := 80.0

var home_position: Vector2 = Vector2.ZERO
var farm_position: Vector2 = Vector2.ZERO
var has_farm: bool = false

var _state: State = State.IDLE_HOME
var _idle_timer: float = 0.0

const ARRIVAL_THRESHOLD := 4.0
const IDLE_HOME_MIN := 3.0
const IDLE_HOME_MAX := 8.0
const IDLE_FARM_MIN := 5.0
const IDLE_FARM_MAX := 12.0

func initialize(home_pos: Vector2, farm_pos: Vector2 = Vector2.ZERO) -> void:
	home_position = home_pos
	position = home_pos
	if farm_pos != Vector2.ZERO:
		farm_position = farm_pos
		has_farm = true
	_state = State.IDLE_HOME
	_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)

func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE_HOME:
			_process_idle_home(delta)
		State.WALKING_TO_FARM:
			_process_walking(delta, farm_position, State.IDLE_FARM)
		State.IDLE_FARM:
			_process_idle_farm(delta)
		State.WALKING_HOME:
			_process_walking(delta, home_position, State.IDLE_HOME)

func _process_idle_home(delta: float) -> void:
	velocity = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0.0 and has_farm:
		_state = State.WALKING_TO_FARM

func _process_idle_farm(delta: float) -> void:
	velocity = Vector2.ZERO
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_state = State.WALKING_HOME

func _process_walking(_delta: float, target: Vector2, next_state: State) -> void:
	var to_target := target - position
	if to_target.length() < ARRIVAL_THRESHOLD:
		position = target
		velocity = Vector2.ZERO
		_state = next_state
		if next_state == State.IDLE_HOME:
			_idle_timer = randf_range(IDLE_HOME_MIN, IDLE_HOME_MAX)
		elif next_state == State.IDLE_FARM:
			_idle_timer = randf_range(IDLE_FARM_MIN, IDLE_FARM_MAX)
		return
	velocity = to_target.normalized() * speed
	move_and_slide()
