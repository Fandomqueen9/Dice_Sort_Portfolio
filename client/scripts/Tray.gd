# client/scripts/Tray.gd
extends Area3D
class_name Tray

signal die_sorted(die: Die)

var tray_color: Color = Color.WHITE

const WOOD_COLOR := Color(0.36, 0.24, 0.14)
const SIGN_DISTANCE := 0.7
const SIGN_HEIGHT := 1.0
const MINI_DIE_SCALE := 0.6
const MINI_DIE_SPACING := 0.16


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
	# wrong color, or already sorted: no-op — die just rests here physically, no punishment


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
	board_mesh.size = Vector3(1.3, 0.9, 0.06)
	board.mesh = board_mesh
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = WOOD_COLOR
	board.material_override = board_material
	sign_root.add_child(board)

	var die_types := GameState.DIE_TYPES
	var start_x := -MINI_DIE_SPACING * (die_types.size() - 1) / 2.0
	for i in range(die_types.size()):
		var mini_die := Die.new()
		mini_die.setup(die_types[i], color)
		mini_die.freeze = true
		mini_die.collision_layer = 0
		mini_die.collision_mask = 0
		mini_die.scale = Vector3.ONE * MINI_DIE_SCALE
		mini_die.position = Vector3(start_x + i * MINI_DIE_SPACING, 0, -0.08)
		sign_root.add_child(mini_die)
