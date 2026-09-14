# client/autoloads/GameState.gd
extends Node

var token: String = ""
var role: String = ""
var has_seen_pickup_tooltip: bool = false

const DIE_TYPES: Array[String] = ["d4", "d6", "d8", "d10", "d12", "d20", "d100"]
const SET_COLORS: Array[Color] = [
	Color(0.8, 0.1, 0.1), Color(0.1, 0.4, 0.8), Color(0.1, 0.7, 0.2),
	Color(0.8, 0.7, 0.1), Color(0.6, 0.1, 0.7), Color(0.9, 0.5, 0.1),
	Color(0.1, 0.7, 0.7), Color(0.9, 0.9, 0.9), Color(0.2, 0.2, 0.2),
	Color(0.9, 0.4, 0.6),
]


func set_session(new_token: String, new_role: String) -> void:
	token = new_token
	role = new_role


func log_out() -> void:
	token = ""
	role = ""
	has_seen_pickup_tooltip = false
