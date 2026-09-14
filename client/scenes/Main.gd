extends Node3D

const ROOM_SIZE := 10.0
const SET_COUNT_MIN := 5
const SET_COUNT_MAX := 10

var player: CharacterBody3D
var dice: Array[Die] = []


func _ready() -> void:
	_build_environment()
	_build_player()
	_spawn_fresh_pile()


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	add_child(light)

	var floor_body := StaticBody3D.new()

	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ROOM_SIZE, 0.2, ROOM_SIZE)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)

	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)

	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)


func _build_player() -> void:
	player = preload("res://scripts/Player.gd").new()
	player.position = Vector3(0, 1, 3)
	add_child(player)


func show_pickup_tooltip() -> void:
	pass  # implemented in Task 9


func _spawn_fresh_pile() -> void:
	var set_count := randi_range(SET_COUNT_MIN, SET_COUNT_MAX)
	var colors := GameState.SET_COLORS.duplicate()
	colors.shuffle()

	for s in range(set_count):
		var color: Color = colors[s % colors.size()]
		for die_type in GameState.DIE_TYPES:
			var die := Die.new()
			die.setup(die_type, color)
			die.position = Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 3.0), randf_range(-1.5, 1.5))
			add_child(die)
			dice.append(die)
