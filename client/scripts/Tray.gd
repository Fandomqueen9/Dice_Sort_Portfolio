# client/scripts/Tray.gd
extends Area3D
class_name Tray

signal die_sorted(die: Die)

var tray_color: Color = Color.WHITE


func setup(color: Color) -> void:
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
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	add_child(mesh_instance)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Die and not body.sorted and body.set_color.is_equal_approx(tray_color):
		body.global_position = global_position + Vector3(0, 0.3, 0)
		body.mark_sorted()
		die_sorted.emit(body)
	# wrong color, or already sorted: no-op — die just rests here physically, no punishment
