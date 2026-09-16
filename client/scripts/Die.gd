# client/scripts/Die.gd
extends RigidBody3D
class_name Die

var die_type: String = ""
var set_color: Color = Color.WHITE
var sorted: bool = false

var _outline_root: Node3D

const OUTLINE_SCALE := 1.06
const DIE_SHADER := preload("res://shaders/die.gdshader")

const SCALE_BY_TYPE := {
	"d4": 0.22, "d6": 0.2, "d8": 0.22, "d10": 0.24,
	"d12": 0.24, "d20": 0.26, "d100": 0.24,
}

const MODEL_BY_TYPE := {
	"d4": preload("res://assets/PolyhedralDice/D4.gltf"),
	"d6": preload("res://assets/PolyhedralDice/D6.gltf"),
	"d8": preload("res://assets/PolyhedralDice/D8.gltf"),
	"d10": preload("res://assets/PolyhedralDice/D10_Ones.gltf"),
	"d12": preload("res://assets/PolyhedralDice/D12.gltf"),
	"d20": preload("res://assets/PolyhedralDice/D20.gltf"),
	"d100": preload("res://assets/PolyhedralDice/D10_Percentile.gltf"),
}


func setup(type: String, color: Color) -> void:
	die_type = type
	set_color = color

	var model_scale: float = SCALE_BY_TYPE.get(type, 0.22)

	var model_instance := MODEL_BY_TYPE[type].instantiate() as Node3D
	model_instance.scale = Vector3.ONE * model_scale
	add_child(model_instance)

	var mesh_instances := _find_mesh_instances(model_instance)
	_apply_die_shader(mesh_instances, color)

	_build_outline(model_instance, model_scale)
	_build_collision(mesh_instances, model_scale)


func _apply_die_shader(mesh_instances: Array[MeshInstance3D], color: Color) -> void:
	# The model files each split their geometry into two surfaces: the body,
	# and the recessed number/pip engravings (their original material name
	# contains "Recess"). Overriding both surfaces with one flat color (the
	# old approach) erased the numbers entirely. Instead, color each surface
	# separately so the engravings stay legible against the body color.
	var body_material := ShaderMaterial.new()
	body_material.shader = DIE_SHADER
	body_material.set_shader_parameter("albedo_color", color)

	var body_luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	var number_color := Color(0.05, 0.05, 0.05) if body_luminance > 0.5 else Color(0.95, 0.95, 0.95)
	var number_material := ShaderMaterial.new()
	number_material.shader = DIE_SHADER
	number_material.set_shader_parameter("albedo_color", number_color)

	for mesh_instance in mesh_instances:
		for i in range(mesh_instance.mesh.get_surface_count()):
			var original := mesh_instance.mesh.surface_get_material(i)
			var is_number_surface := original != null and "recess" in original.resource_name.to_lower()
			mesh_instance.set_surface_override_material(i, number_material if is_number_surface else body_material)


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found


func _build_outline(model_instance: Node3D, model_scale: float) -> void:
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1, 1, 1)
	outline_material.cull_mode = BaseMaterial3D.CULL_FRONT

	_outline_root = model_instance.duplicate() as Node3D
	_outline_root.scale = Vector3.ONE * (model_scale * OUTLINE_SCALE)
	_outline_root.visible = false
	add_child(_outline_root)

	for mesh_instance in _find_mesh_instances(_outline_root):
		mesh_instance.material_override = outline_material


func _build_collision(mesh_instances: Array[MeshInstance3D], model_scale: float) -> void:
	# A bounding-box collider instead of a convex hull of the full detailed
	# mesh — with ~70 dice colliding at once, a hull with hundreds of faces
	# per die (from the recessed pip/number geometry) made physics unplayably
	# slow. The box is invisible and close enough for sorting/carrying feel.
	var mesh_aabb := mesh_instances[0].mesh.get_aabb()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh_aabb.size
	shape.shape = box
	shape.position = mesh_aabb.get_center()
	shape.scale = Vector3.ONE * model_scale
	add_child(shape)


func set_highlighted(on: bool) -> void:
	_outline_root.visible = on


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


func reset() -> void:
	sorted = false
	freeze = false
	collision_layer = 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func serialize_state() -> Dictionary:
	return {
		"type": die_type,
		"color": [set_color.r, set_color.g, set_color.b],
		"position": [global_position.x, global_position.y, global_position.z],
		"sorted": sorted,
	}
