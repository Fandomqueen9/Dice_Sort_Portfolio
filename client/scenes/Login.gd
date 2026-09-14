# client/scenes/Login.gd
extends Control

var username_field: LineEdit
var password_field: LineEdit
var status_label: Label


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.position = Vector2(40, 40)
	add_child(layout)

	var title := Label.new()
	title.text = "Dice Sorting Game"
	layout.add_child(title)

	username_field = LineEdit.new()
	username_field.placeholder_text = "username"
	layout.add_child(username_field)

	password_field = LineEdit.new()
	password_field.placeholder_text = "password"
	password_field.secret = true
	layout.add_child(password_field)

	var register_button := Button.new()
	register_button.text = "Create Account"
	register_button.pressed.connect(_on_register_pressed)
	layout.add_child(register_button)

	var login_button := Button.new()
	login_button.text = "Log In"
	login_button.pressed.connect(_on_login_pressed)
	layout.add_child(login_button)

	var guest_button := Button.new()
	guest_button.text = "Play as Guest"
	guest_button.pressed.connect(_on_guest_pressed)
	layout.add_child(guest_button)

	status_label = Label.new()
	layout.add_child(status_label)


func _on_register_pressed() -> void:
	status_label.text = "Creating account..."
	var result := await ApiClient.register(username_field.text, password_field.text)
	if not result.ok:
		status_label.text = "Registration failed: %s" % str(result.data.get("error", "unknown error"))
		return
	_enter_game(result.data)


func _on_login_pressed() -> void:
	status_label.text = "Logging in..."
	var result := await ApiClient.login(username_field.text, password_field.text)
	if not result.ok:
		status_label.text = "Login failed: invalid credentials"
		return
	_enter_game(result.data)


func _on_guest_pressed() -> void:
	status_label.text = "Connecting..."
	var result := await ApiClient.guest()
	if not result.ok:
		status_label.text = "Could not reach server"
		return
	_enter_game(result.data)


func _enter_game(data: Dictionary) -> void:
	GameState.set_session(data.get("token", ""), data.get("role", ""))
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
