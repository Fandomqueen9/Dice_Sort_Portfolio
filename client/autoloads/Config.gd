# client/autoloads/Config.gd
extends Node

var backend_url: String = "http://127.0.0.1:8000"


func _ready() -> void:
	var path := OS.get_executable_path().get_base_dir().path_join("server_url.txt")
	if FileAccess.file_exists(path):
		var url := FileAccess.get_file_as_string(path).strip_edges().trim_suffix("/")
		if url != "":
			backend_url = url
