extends CharacterBody2D

@export var speed := 260.0
func _ready():
	print("Player script is running")
	print("ready, paused?", get_tree().paused)
	print("physics processing?", is_physics_processing())
func _physics_process(_dt):
	var x := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y := Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	var direction := Vector2(x, y).normalized()
	velocity = direction * speed
	move_and_slide()
