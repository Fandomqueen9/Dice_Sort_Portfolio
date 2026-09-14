# client/autoloads/ApiClient.gd
extends Node


func _request(method: HTTPClient.Method, path: String, body: Dictionary = {}, auth: bool = true) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := ["Content-Type: application/json"]
	if auth and GameState.token != "":
		headers.append("Authorization: Bearer %s" % GameState.token)

	var body_string := ""
	if not body.is_empty():
		body_string = JSON.stringify(body)

	var err := http.request(Config.backend_url + path, headers, method, body_string)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": {}}

	var result: Array = await http.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	http.queue_free()

	var parsed: Variant = {}
	if response_body.size() > 0:
		var text := response_body.get_string_from_utf8()
		var maybe = JSON.parse_string(text)
		if maybe != null:
			parsed = maybe

	return {"ok": response_code >= 200 and response_code < 300, "status": response_code, "data": parsed}


func register(username: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/register", {"username": username, "password": password}, false)


func login(username: String, password: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/login", {"username": username, "password": password}, false)


func guest() -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/auth/guest", {}, false)


func save_game(dice_state: Array) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/game/save", {"dice_state": dice_state})


func load_game() -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/game/load")


func admin_command(command_name: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/admin/command", {"command": command_name})
