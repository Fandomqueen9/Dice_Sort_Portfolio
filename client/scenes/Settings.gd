# client/scenes/Settings.gd
extends Control

const MIN_SETS := 1
const MAX_SETS := 10

var set_count_label: Label
var slider: HSlider


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.position = Vector2(40, 40)
	add_child(layout)

	var title := Label.new()
	title.text = "Game Settings"
	layout.add_child(title)

	set_count_label = Label.new()
	layout.add_child(set_count_label)

	slider = HSlider.new()
	slider.min_value = MIN_SETS
	slider.max_value = MAX_SETS
	slider.step = 1
	slider.value = GameState.set_count
	slider.custom_minimum_size = Vector2(300, 0)
	slider.value_changed.connect(_on_slider_changed)
	layout.add_child(slider)

	_update_label(slider.value)

	var start_button := Button.new()
	start_button.text = "Start Game"
	start_button.pressed.connect(_on_start_pressed)
	layout.add_child(start_button)


func _on_slider_changed(value: float) -> void:
	GameState.set_count = int(value)
	_update_label(value)


func _update_label(value: float) -> void:
	set_count_label.text = "Number of dice sets: %d" % int(value)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
