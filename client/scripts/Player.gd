extends CharacterBody3D

const SPEED := 4.5
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_DISTANCE := 2.5

var camera: Camera3D
var interact_ray: RayCast3D
var held_dice: Array[Node3D] = []
var hovered_die: Node3D = null
var crosshair: Control
var max_held_dice: int = 1

# Local offsets (right, up, forward) for each carry slot so held dice don't
# stack inside each other once multi-carry is unlocked.
const HOLD_OFFSETS := [
	Vector3(0.0, 0.0, -1.2),
	Vector3(-0.35, -0.05, -1.1),
	Vector3(0.35, -0.05, -1.1),
]


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

	_build_crosshair()


func _build_crosshair() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(crosshair)

	var horizontal := ColorRect.new()
	horizontal.color = Color(1, 1, 1, 0.85)
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal.size = Vector2(8, 2)
	horizontal.anchor_left = 0.5
	horizontal.anchor_right = 0.5
	horizontal.anchor_top = 0.5
	horizontal.anchor_bottom = 0.5
	horizontal.position = Vector2(-4, -1)
	crosshair.add_child(horizontal)

	var vertical := ColorRect.new()
	vertical.color = Color(1, 1, 1, 0.85)
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.size = Vector2(2, 8)
	vertical.anchor_left = 0.5
	vertical.anchor_right = 0.5
	vertical.anchor_top = 0.5
	vertical.anchor_bottom = 0.5
	vertical.position = Vector2(-1, -4)
	crosshair.add_child(vertical)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -1.3, 1.3)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_on_interact_pressed()


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
	crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	for i in range(held_dice.size()):
		var offset: Vector3 = HOLD_OFFSETS[i]
		held_dice[i].global_position = camera.global_position \
			+ camera.global_transform.basis.x * offset.x \
			+ camera.global_transform.basis.y * offset.y \
			+ camera.global_transform.basis.z * offset.z


func _update_hover() -> void:
	if held_dice.size() >= max_held_dice:
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
	if hovered_die and held_dice.size() < max_held_dice:
		_pick_up_die(hovered_die)
	elif held_dice.size() > 0:
		_release_all_dice()


func _pick_up_die(die: Node3D) -> void:
	die.set_highlighted(false)
	die.pick_up()
	held_dice.append(die)
	hovered_die = null

	if not GameState.has_seen_pickup_tooltip:
		GameState.has_seen_pickup_tooltip = true
		get_tree().current_scene.show_pickup_tooltip()


func _release_all_dice() -> void:
	for die in held_dice:
		die.release()
	held_dice.clear()


func release_held_dice() -> void:
	if held_dice.size() > 0:
		_release_all_dice()


func unlock_multi_carry() -> void:
	max_held_dice = 3
