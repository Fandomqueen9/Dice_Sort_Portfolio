extends CharacterBody3D

const SPEED := 4.5
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_DISTANCE := 2.5

var camera: Camera3D
var interact_ray: RayCast3D
var held_die: Node3D = null
var hovered_die: Node3D = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	collision.shape = capsule
	add_child(collision)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0.7, 0)
	add_child(camera)

	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0, 0, -INTERACT_DISTANCE)
	interact_ray.collide_with_areas = false
	interact_ray.collide_with_bodies = true
	camera.add_child(interact_ray)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -1.3, 1.3)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_interact_pressed()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()
	_update_hover()

	if held_die:
		held_die.global_position = camera.global_position + camera.global_transform.basis.z * -1.2


func _update_hover() -> void:
	if held_die:
		return

	interact_ray.force_raycast_update()
	var collider := interact_ray.get_collider()

	if collider == hovered_die:
		return

	if hovered_die and hovered_die.has_method("set_highlighted"):
		hovered_die.set_highlighted(false)

	hovered_die = null
	if collider and collider.has_method("set_highlighted"):
		hovered_die = collider
		hovered_die.set_highlighted(true)


func _on_interact_pressed() -> void:
	if held_die:
		_release_die()
	elif hovered_die:
		_pick_up_die(hovered_die)


func _pick_up_die(die: Node3D) -> void:
	die.set_highlighted(false)
	die.pick_up()
	held_die = die
	hovered_die = null

	if not GameState.has_seen_pickup_tooltip:
		GameState.has_seen_pickup_tooltip = true
		get_tree().current_scene.show_pickup_tooltip()


func _release_die() -> void:
	held_die.release()
	held_die = null
