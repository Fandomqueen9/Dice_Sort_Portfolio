extends Node3D

const ROOM_SIZE := 10.0
const SET_COUNT_MIN := 5
const SET_COUNT_MAX := 10

var player: CharacterBody3D
var dice: Array[Die] = []
var win_label: Label
var tooltip_label: Label
var trays: Array[Tray] = []


func _ready() -> void:
	_build_environment()
	_build_player()
	_build_ui()
	_build_trays()

	var loaded := await _try_load_saved_state()
	if not loaded:
		_spawn_fresh_pile()

	_start_autosave_timer()


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


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	win_label = Label.new()
	win_label.text = "All sets sorted!"
	win_label.visible = false
	win_label.position = Vector2(400, 50)
	canvas.add_child(win_label)

	tooltip_label = Label.new()
	tooltip_label.text = "Click to pick up. Click again to place it in a matching tray."
	tooltip_label.visible = false
	tooltip_label.position = Vector2(20, 20)
	canvas.add_child(tooltip_label)


func show_pickup_tooltip() -> void:
	tooltip_label.visible = true
	await get_tree().create_timer(4.0).timeout
	tooltip_label.visible = false


func _build_trays() -> void:
	var colors := GameState.SET_COLORS
	for i in range(colors.size()):
		var tray := Tray.new()
		tray.setup(colors[i])
		var angle := (float(i) / colors.size()) * TAU
		var radius := ROOM_SIZE / 2.0 - 1.0
		tray.position = Vector3(cos(angle) * radius, 0.2, sin(angle) * radius)
		tray.die_sorted.connect(_on_die_sorted)
		add_child(tray)
		trays.append(tray)


func _on_die_sorted(_die: Die) -> void:
	if dice.all(func(d): return d.sorted):
		win_label.visible = true


func apply_sort_all() -> void:
	pass  # implemented in Task 12


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


func _try_load_saved_state() -> bool:
	if GameState.role == "guest":
		return false

	var result := await ApiClient.load_game()
	if not result.ok or result.data.get("dice_state") == null:
		return false

	for entry in result.data["dice_state"]:
		var die := Die.new()
		var color := Color(entry["color"][0], entry["color"][1], entry["color"][2])
		die.setup(entry["type"], color)
		die.position = Vector3(entry["position"][0], entry["position"][1], entry["position"][2])
		add_child(die)
		if entry["sorted"]:
			die.mark_sorted()
		dice.append(die)

	return true


func save_current_state() -> void:
	if GameState.role == "guest":
		return

	var state: Array = []
	for die in dice:
		state.append(die.serialize_state())
	await ApiClient.save_game(state)


func _start_autosave_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(func(): save_current_state())
	add_child(timer)
	timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await save_current_state()
		get_tree().quit()
