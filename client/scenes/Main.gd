extends Node3D

const ROOM_SIZE := 10.0

var player: CharacterBody3D
var dice: Array[Die] = []
var win_label: Label
var tooltip_label: Label
var trays: Array[Tray] = []
var admin_console: Control
var admin_input: LineEdit
var pause_menu: Control


func _ready() -> void:
	_build_environment()
	_build_walls()
	_build_player()
	_build_ui()
	_build_trays()

	var loaded := await _try_load_saved_state()
	if not loaded:
		_spawn_fresh_pile()

	_start_autosave_timer()

	_build_admin_console()
	_build_pause_menu()


func _build_environment() -> void:
	# A single directional light leaves faces angled away from it fully
	# unlit (black) — walls/trays showed this as "two black sides". Ambient
	# fill light via WorldEnvironment gives every face some base illumination.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1, 1, 1)
	environment.ambient_light_energy = 0.6

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

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


func _build_walls() -> void:
	var wall_height := 3.0
	var wall_thickness := 0.3
	var half := ROOM_SIZE / 2.0

	var configs := [
		{"position": Vector3(0, wall_height / 2.0, -half), "size": Vector3(ROOM_SIZE, wall_height, wall_thickness)},
		{"position": Vector3(0, wall_height / 2.0, half), "size": Vector3(ROOM_SIZE, wall_height, wall_thickness)},
		{"position": Vector3(-half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, ROOM_SIZE)},
		{"position": Vector3(half, wall_height / 2.0, 0), "size": Vector3(wall_thickness, wall_height, ROOM_SIZE)},
	]

	for config in configs:
		var wall_body := StaticBody3D.new()

		var wall_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = config["size"]
		wall_shape.shape = box
		wall_body.add_child(wall_shape)

		var wall_mesh := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = config["size"]
		wall_mesh.mesh = mesh
		wall_body.add_child(wall_mesh)

		wall_body.position = config["position"]
		add_child(wall_body)


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


func _build_admin_console() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	admin_console = Control.new()
	admin_console.visible = false
	canvas.add_child(admin_console)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 400)
	admin_console.add_child(box)

	admin_input = LineEdit.new()
	admin_input.placeholder_text = "command (try 'help')"
	box.add_child(admin_input)

	var output := Label.new()
	box.add_child(output)

	admin_input.text_submitted.connect(func(command_text: String):
		var result := await ApiClient.admin_command(command_text)
		if result.ok and command_text == "sort_all":
			apply_sort_all()
		if result.data.has("commands"):
			output.text = "Available commands: " + ", ".join(result.data["commands"])
		elif result.data.has("error"):
			output.text = result.data["error"]
		else:
			output.text = str(result.data)
		admin_input.text = ""
	)


func toggle_admin_console() -> void:
	if not admin_console:
		return

	admin_console.visible = not admin_console.visible
	if admin_console.visible:
		admin_input.grab_focus()
	else:
		admin_input.release_focus()


func _build_pause_menu() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	pause_menu = Control.new()
	pause_menu.visible = false
	canvas.add_child(pause_menu)

	var box := VBoxContainer.new()
	box.position = Vector2(400, 250)
	pause_menu.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	box.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.pressed.connect(toggle_pause_menu)
	box.add_child(resume_button)

	var save_button := Button.new()
	save_button.text = "Save"
	box.add_child(save_button)

	var save_status_label := Label.new()
	save_status_label.visible = false
	box.add_child(save_status_label)

	save_button.pressed.connect(func():
		if GameState.role == "guest":
			save_status_label.text = "Guests can't save"
		else:
			var success := await save_current_state()
			save_status_label.text = "Saved!" if success else "Save failed"
		save_status_label.visible = true
		await get_tree().create_timer(2.0).timeout
		save_status_label.visible = false
	)

	var quit_menu_button := Button.new()
	quit_menu_button.text = "Quit to Menu"
	quit_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	box.add_child(quit_menu_button)

	var quit_desktop_button := Button.new()
	quit_desktop_button.text = "Quit to Desktop"
	quit_desktop_button.pressed.connect(_on_quit_to_desktop_pressed)
	box.add_child(quit_desktop_button)


func toggle_pause_menu() -> void:
	if not pause_menu:
		return

	pause_menu.visible = not pause_menu.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_menu.visible else Input.MOUSE_MODE_CAPTURED


func _on_quit_to_menu_pressed() -> void:
	await save_current_state()
	GameState.log_out()
	get_tree().change_scene_to_file("res://scenes/Login.tscn")


func _on_quit_to_desktop_pressed() -> void:
	await save_current_state()
	get_tree().quit()


func apply_sort_all() -> void:
	for die in dice:
		if not die.sorted:
			for tray in trays:
				if tray.tray_color.is_equal_approx(die.set_color):
					die.global_position = tray.global_position + Vector3(0, 0.3, 0)
					die.mark_sorted()
					break
	_on_die_sorted(null)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		toggle_admin_console()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle_pause_menu()


func _spawn_fresh_pile() -> void:
	var colors := GameState.SET_COLORS.duplicate()
	colors.shuffle()

	for s in range(GameState.set_count):
		var color: Color = colors[s % colors.size()]
		for die_type in GameState.DIE_TYPES:
			var die := Die.new()
			die.setup(die_type, color)
			die.position = Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 3.0), randf_range(-2.5, 2.5))
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


func save_current_state() -> bool:
	if GameState.role == "guest":
		return false

	var state: Array = []
	for die in dice:
		state.append(die.serialize_state())
	var result := await ApiClient.save_game(state)
	return result.ok


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
