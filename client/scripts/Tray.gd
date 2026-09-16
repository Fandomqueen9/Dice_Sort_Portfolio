# client/scripts/Tray.gd
extends Area3D
class_name Tray

signal die_sorted(die: Die)

var tray_color: Color = Color.WHITE
var _mini_dice_by_type: Dictionary = {}

const WOOD_COLOR := Color(0.36, 0.24, 0.14)
const SIGN_DISTANCE := 0.7
const SIGN_HEIGHT := 1.0
const MINI_DIE_SCALE := 0.85
const MATCHED_OUTLINE_COLOR := Color(0.2, 0.9, 0.3)

# Three straight, evenly-spaced rows (2 / 3 / 2), d20 centered in the
# middle row. One offset per entry in GameState.DIE_TYPES, matched by index.
const MINI_DIE_OFFSETS := [
	Vector2(-0.35, 0.28),  # d4    top-left
	Vector2(0.35, 0.28),   # d6    top-right
	Vector2(-0.55, 0.0),   # d8    mid-left
	Vector2(0.55, 0.0),    # d10   mid-right
	Vector2(-0.35, -0.28), # d12   bottom-left
	Vector2(0.0, 0.0),     # d20   center
	Vector2(0.35, -0.28),  # d100  bottom-right
]


func setup(color: Color, outward_direction: Vector3) -> void:
	tray_color = color

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.4, 0.8)
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var material := StandardMaterial3D.new()
	material.albedo_color = WOOD_COLOR
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)

	body_entered.connect(_on_body_entered)

	_build_sign(color, outward_direction)


func _on_body_entered(body: Node) -> void:
	if body is Die and not body.sorted and body.set_color.is_equal_approx(tray_color):
		body.global_position = global_position + Vector3(0, 0.3, 0)
		body.mark_sorted()
		die_sorted.emit(body)
		mark_type_present(body.die_type)
	# wrong color, or already sorted: no-op — die just rests here physically, no punishment


func mark_type_present(die_type: String) -> void:
	if _mini_dice_by_type.has(die_type):
		_mini_dice_by_type[die_type].set_highlighted(true)


func reset_sign_highlights() -> void:
	for mini_die in _mini_dice_by_type.values():
		mini_die.set_highlighted(false)


func _build_sign(color: Color, outward_direction: Vector3) -> void:
	# There's no 2D icon asset for "what belongs in this tray", so the sign
	# shows small frozen, non-interactive copies of the real dice models
	# instead of a picture — reuses the actual set instead of needing art.
	var sign_root := Node3D.new()
	sign_root.position = outward_direction * SIGN_DISTANCE + Vector3(0, SIGN_HEIGHT, 0)
	add_child(sign_root)
	sign_root.look_at(global_position + Vector3(0, SIGN_HEIGHT, 0), Vector3.UP)

	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.5, 1.1, 0.06)
	board.mesh = board_mesh
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = WOOD_COLOR
	board.material_override = board_material
	sign_root.add_child(board)

	var die_types := GameState.DIE_TYPES
	for i in range(die_types.size()):
		var mini_die := Die.new()
		mini_die.setup(die_types[i], color)
		mini_die.freeze = true
		mini_die.collision_layer = 0
		mini_die.collision_mask = 0
		mini_die.set_outline_color(MATCHED_OUTLINE_COLOR)
		mini_die.scale = Vector3.ONE * MINI_DIE_SCALE

		var offset: Vector2 = MINI_DIE_OFFSETS[i]
		mini_die.position = Vector3(offset.x, offset.y, -0.1)
		sign_root.add_child(mini_die)
		_mini_dice_by_type[die_types[i]] = mini_die
