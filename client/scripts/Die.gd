# client/scripts/Die.gd
extends RigidBody3D
class_name Die

var die_type: String = ""
var set_color: Color = Color.WHITE
var sorted: bool = false

var _material: StandardMaterial3D

const SIZE_BY_TYPE := {
	"d4": 0.18, "d6": 0.2, "d8": 0.22, "d10": 0.24,
	"d12": 0.26, "d20": 0.28, "d100": 0.3,
}


func setup(type: String, color: Color) -> void:
	die_type = type
	set_color = color

	var scale_amount: float = SIZE_BY_TYPE.get(type, 0.2)
	var size: Vector3 = Vector3.ONE * scale_amount

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material
	add_child(mesh_instance)

	var label := Label3D.new()
	label.text = type
	label.position = Vector3(0, size.y / 2.0 + 0.05, 0)
	label.font_size = 32
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func set_highlighted(on: bool) -> void:
	_material.emission_enabled = on
	_material.emission = Color(1, 1, 1)
	_material.emission_energy_multiplier = 0.6 if on else 0.0


func pick_up() -> void:
	freeze = true
	collision_layer = 0


func release() -> void:
	freeze = false
	collision_layer = 1


func mark_sorted() -> void:
	sorted = true
	freeze = true
	collision_layer = 0


func serialize_state() -> Dictionary:
	return {
		"type": die_type,
		"color": [set_color.r, set_color.g, set_color.b],
		"position": [global_position.x, global_position.y, global_position.z],
		"sorted": sorted,
	}
