class_name SpotifyAPI
extends Node

const base_url := "https://api.spotify.com/v1"
const auth_uri := "https://accounts.spotify.com/authorize" 
const token_url := "https://accounts.spotify.com/api/token"
const scopes := ["user-read-playback-state", "user-modify-playback-state", "playlist-read-private", "playlist-read-collaborative", "user-read-recently-played"]

var spotify_node: SpotifyNode
var http_client := HTTPClient.new()
var rate_limit_hit: bool = false
var encrypted_credentials: Dictionary
var encrypted_access_token: PackedByteArray
var key: CryptoKey
var auth_state: SpotifyNode.AuthState
var token_refresh_running: bool = false

@onready var crypto: Crypto = Crypto.new()

func _ready() -> void:
	if _init_credentials():
		_refresh_token()

func track_playback_state() -> void:
	while spotify_node.is_tracking:
		var timestamp: int = Time.get_ticks_msec()
		if auth_state == SpotifyNode.AuthState.VALID:
			var state := await get_playback_state()
			spotify_node._update_playback_state(state)
			var wait_time_ms: int = (spotify_node.playing_refresh_time_s if spotify_node.playback_state["is_playing"] else spotify_node.paused_refresh_time_s) * 1000 - (Time.get_ticks_msec() - timestamp)
			if wait_time_ms > 0:
				await get_tree().create_timer(wait_time_ms / 1000.).timeout
		else:
			await get_tree().create_timer(0.1).timeout

func get_playback_state() -> Dictionary:
	var result := await _execute_request("%s/me/player" % base_url, HTTPClient.METHOD_GET)
	return _get_response_body(result)

func get_available_devices() -> Array:
	var result := await _execute_request("%s/me/player/devices" % base_url, HTTPClient.METHOD_GET)
	var body := _get_response_body(result)
	if !body.is_empty():
		return body["devices"]
	else:
		return []

func get_recently_played_tracks() -> Array:
	var query_parameters := { "limit": 50 }
	var result := await _execute_request("%s/me/player/recently_played?%s" % [base_url, http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_GET)
	var body := _get_response_body(result)
	if !body.is_empty():
		return body["items"]
	else:
		return []

func next(device_id: String = "") -> bool:
	var url := "%s/me/player/next" % base_url
	if device_id != "":
		var query_parameters := { "device_id" = device_id }
		url += "?%s" % http_client.query_string_from_dict(query_parameters)
	var result := await _execute_request(url, HTTPClient.METHOD_POST, "{}")
	return _is_successfull(result)

func previous(device_id: String = "") -> bool:
	var url := "%s/me/player/previous" % base_url
	if device_id != "":
		var query_parameters := { "device_id" = device_id }
		url += "?%s" % http_client.query_string_from_dict(query_parameters)
	var result := await _execute_request(url, HTTPClient.METHOD_POST, "{}")
	return _is_successfull(result)

func play(device_id: String = "", context_uri: String = "", track_uris: Array[String] = [], offset_nbr: int = 0, offset_uri: String = "", position_ms: int = 0) -> bool:
	var url := "%s/me/player/play" % base_url
	if device_id != "":
		var query_parameters := { "device_id" = device_id }
		url += "?%s" % http_client.query_string_from_dict(query_parameters)
	var body := {}
	if context_uri != "":
		body["context_uri"] = "spotify:playlist:%s" % context_uri
	if track_uris != []:
		body["uris"] = track_uris
	if offset_nbr != 0:
		body["offset"] = {"position": offset_nbr}
	elif offset_uri != "":
		body["offset"] = {"uri": offset_uri}
	if position_ms != 0:
		body["position_ms"] = position_ms
	var result := await _execute_request(url, HTTPClient.METHOD_PUT, JSON.stringify(body))
	if !result.is_empty() && result[1] == 404:
		var devices := await get_available_devices()
		var query_parameters := { "device_id" = devices[0]["id"] }
		url += "?%s" % http_client.query_string_from_dict(query_parameters)
		await _execute_request(url, HTTPClient.METHOD_PUT, JSON.stringify(body))
	return _is_successfull(result)

func pause(device_id: String = ""):
	var url := "%s/me/player/pause" % base_url
	if device_id != "":
		var query_parameters := { "device_id" = device_id }
		url += "?%s" % http_client.query_string_from_dict(query_parameters)
	var result := await _execute_request(url, HTTPClient.METHOD_PUT, "{}")
	return _is_successfull(result)

func set_playback_volume(volume_percent: int) -> bool:
	var query_parameters := { "volume_percent" : volume_percent }
	var result := await _execute_request("%s/me/player/volume?%s" % [base_url,http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_PUT, "{}")
	return _is_successfull(result)

func get_queue() -> Array:
	var result := await _execute_request("%s/me/player/queue" % base_url, HTTPClient.METHOD_GET)
	var body := _get_response_body(result)
	if !body.is_empty():
		return body["queue"]
	else:
		return []

func add_item_to_queue(request_uri: String, device_id: String = "") -> bool:
	var query_parameters := {
		"uri" : request_uri,
	}
	if device_id != "":
		query_parameters["device_id"] = device_id
	var result := await _execute_request("%s/me/player/queue?%s" % [base_url, http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_POST, "{}")
	return _is_successfull(result)

func get_current_user_playlists() -> Dictionary:
	var query_parameters := {
		"limit" : 50,
	}
	var result := await _execute_request("%s/me/playlists?%s" % [base_url, http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_GET)
	return _get_response_body(result)

func get_user_playlists(user_id: String) -> Dictionary:
	var query_parameters := {
		"limit" : 50,
	}
	var result := await _execute_request("%s/users/%s/playlists?%s" % [base_url, user_id, http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_GET)
	return _get_response_body(result)

func get_playlist(playlist_id: String) -> Dictionary:
	var result := await _execute_request("%s/playlists/%s" % [base_url, playlist_id], HTTPClient.METHOD_GET)
	if _is_successfull(result):
		return _get_response_body(result)
	else:
		return {}

func search(query: String, types: Array[SpotifyNode.ItemType], limit: int = 50) -> Dictionary:
	if query == "":
		printerr("Can't perform Spotify search with empty query")
		return {}
	var types_str: Array[String]
	for type in types:
		var type_str: String = SpotifyNode.ItemType.keys()[type]
		types_str.append(type_str.to_lower())
	var query_parameters := { "q" : query, "type" : types_str, "limit" : limit }
	var result := await _execute_request("%s/search?%s" % [base_url,http_client.query_string_from_dict(query_parameters)], HTTPClient.METHOD_GET)
	return _get_response_body(result)

func get_user_profile() -> Dictionary:
	var result := await _execute_request("%s/me" % base_url, HTTPClient.METHOD_GET)
	return _get_response_body(result)

func _execute_request(url: String, method: int = 0, body: String = "") -> Array:
	if auth_state == SpotifyNode.AuthState.REFRESHING && url != token_url:
		await spotify_node.auth_state_changed
	if auth_state != SpotifyNode.AuthState.VALID && url != token_url:
		printerr("Spotify request failed due to missing or invalid credentials")
		return []
	if rate_limit_hit:
		printerr("Spotify rate limit hit")
		return []
	var request := HTTPRequest.new()
	request.use_threads = true
	add_child(request)
	request.request(url,_get_headers(url),method,body)
	var result: Array = await request.request_completed
	request.queue_free()
	if result[1] == 429:
		rate_limit_hit = true
		_reset_rate_limit(result[2]["Retry-After"])
	return result

func _reset_rate_limit(retry_after: int) -> void:
	await get_tree().create_timer(retry_after).timeout
	rate_limit_hit = false

func _get_headers(url: String) -> PackedStringArray:
	if url == token_url:
		var headers := ["Content-Type: application/x-www-form-urlencoded"]
		match encrypted_credentials["auth_type"]:
			SpotifyNode.AuthType.AUTH_CODE:
				var client_info := Marshalls.utf8_to_base64("%s:%s" % [crypto.decrypt(key,encrypted_credentials["client_id"]).get_string_from_utf8(),crypto.decrypt(key,encrypted_credentials["client_secret"]).get_string_from_utf8()])
				headers.append("Authorization: Basic %s" % client_info)
		return headers
	else:
		return ["Authorization: Bearer %s" % crypto.decrypt(key,encrypted_access_token).get_string_from_utf8(), "Content-Type: application/json"]

func _is_successfull(request_result: Array) -> bool:
	if request_result.is_empty():
		return false
	else:
		return request_result[0] == 0 && request_result[1] > 199 && request_result[1] < 300

func _get_response_body(request_result: Array) -> Dictionary:
	if request_result.is_empty():
		return {}
	if request_result[1] == 200:
		var body: PackedByteArray = request_result[3]
		var parsed_body: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed_body is Dictionary:
			return JSON.parse_string(body.get_string_from_utf8())
		else:
			printerr("Spotify response not a dictionary: %s" % parsed_body)
			return {}
	elif request_result[1] < 200 || request_result[1] > 299:
		var body_str := ""
		if request_result[3] != null:
			var body: PackedByteArray = request_result[3]
			body_str = body.get_string_from_utf8()
		printerr("Recieved spotify api response %s, body: %s" % [request_result[1], body_str])
	elif request_result[1] != 204:
		var body_str := ""
		if request_result[3] != null:
			var body: PackedByteArray = request_result[3]
			body_str = body.get_string_from_utf8()
		printerr("Please check this printout: response code: %s, body: %s" % [request_result[1], body_str])
	return {}

func _request_token(authorization_code: String) -> int:
	auth_state = SpotifyNode.AuthState.REFRESHING
	spotify_node.auth_state_changed.emit(auth_state)
	var body := {
		"grant_type": "authorization_code",
		"code": authorization_code,
		"redirect_uri": "%s:%s" % [SpotifyAuth.redirect_uri, SpotifyAuth.redirect_port],
	}
	if encrypted_credentials["auth_type"] == SpotifyNode.AuthType.AUTH_CODE_PKCE:
		body["client_id"] = crypto.decrypt(key,encrypted_credentials["client_id"]).get_string_from_utf8()
		body["code_verifier"] = crypto.decrypt(key,encrypted_credentials["code_verifier"]).get_string_from_utf8()
	var result := await _execute_request(token_url, HTTPClient.METHOD_POST, http_client.query_string_from_dict(body))
	var response_body := _get_response_body(result)
	if !response_body.is_empty():
		encrypted_access_token = crypto.encrypt(key,response_body["access_token"].to_utf8_buffer())
		encrypted_credentials["refresh_token"] = crypto.encrypt(key,response_body["refresh_token"].to_utf8_buffer())
		var lifetime: int = response_body["expires_in"]
		auth_state = SpotifyNode.AuthState.VALID
		spotify_node.auth_state_changed.emit(auth_state)
		return lifetime
	else:
		printerr("Error refreshing token")
		auth_state = SpotifyNode.AuthState.INVALID
		spotify_node.auth_state_changed.emit(auth_state)
		return 0

func _refresh_token(lifetime: int = 0) -> void:
	token_refresh_running = true
	if lifetime > 60:
		await get_tree().create_timer(lifetime - 60).timeout
	while true:
		auth_state = SpotifyNode.AuthState.REFRESHING
		spotify_node.auth_state_changed.emit(auth_state)
		var body := {
			"grant_type": "refresh_token",
			"refresh_token": crypto.decrypt(key,encrypted_credentials["refresh_token"]).get_string_from_utf8(),
		}
		if encrypted_credentials["auth_type"] == SpotifyNode.AuthType.AUTH_CODE_PKCE:
			body["client_id"] = crypto.decrypt(key,encrypted_credentials["client_id"]).get_string_from_utf8()
		var result := await _execute_request(token_url, HTTPClient.METHOD_POST, http_client.query_string_from_dict(body))
		var response_body := _get_response_body(result)
		if !response_body.is_empty():
			encrypted_access_token = crypto.encrypt(key,response_body["access_token"].to_utf8_buffer())
			lifetime = response_body["expires_in"]
			var refresh_token: String = response_body.get("refresh_token", "")
			if refresh_token != "":
				encrypted_credentials["refresh_token"] = crypto.encrypt(key,refresh_token.to_utf8_buffer())
				_store_credentials()
			auth_state = SpotifyNode.AuthState.VALID
			spotify_node.auth_state_changed.emit(auth_state)
			await get_tree().create_timer(lifetime - 60).timeout
		else:
			token_refresh_running = false
			printerr("Error refreshing token")
			auth_state = SpotifyNode.AuthState.INVALID
			spotify_node.auth_state_changed.emit(auth_state)
			break

func get_client_id() -> String:
	if !encrypted_credentials["client_id"].is_empty():
		return crypto.decrypt(key, encrypted_credentials["client_id"]).get_string_from_utf8()
	else:
		return ""

func get_auth_type() -> SpotifyNode.AuthType:
	return encrypted_credentials["auth_type"]

func get_auth_url(_redirect_uri: String, _state: String = "") -> String:
	var query_parameters := {
		"client_id" : get_client_id(),
		"response_type" : "code",
		"redirect_uri" : _redirect_uri,
		"scope" : get_channel_scope(),
		"show_dialog" : true
	}
	if _state != "":
		query_parameters["state"] = _state
	match encrypted_credentials["auth_type"]:
		SpotifyNode.AuthType.AUTH_CODE:
			pass
		SpotifyNode.AuthType.AUTH_CODE_PKCE:
			encrypted_credentials["code_verifier"] = crypto.encrypt(key, _generate_code_verifier().to_utf8_buffer())
			query_parameters["code_challenge_method"] = "S256"
			var code_challenge := Marshalls.raw_to_base64(crypto.decrypt(key, encrypted_credentials["code_verifier"]).get_string_from_utf8().sha256_buffer()).replacen("+","-").replacen("/","_").replacen("=","")
			query_parameters["code_challenge"] = code_challenge
	return auth_uri + "?" + HTTPClient.new().query_string_from_dict(query_parameters)

func get_channel_scope() -> String:
	var scope_str: String
	for scope in scopes:
		scope_str += scope + " "
	return scope_str.trim_suffix(" ")

func set_credentials(auth_type: SpotifyNode.AuthType, client_id: String, client_secret: String, authorization_code: String, store: bool) -> void:
	auth_state = SpotifyNode.AuthState.UNKNOWN
	if auth_type != encrypted_credentials["auth_type"]:
		encrypted_credentials["auth_type"] = auth_type
		encrypted_credentials["client_secret"] = []
		encrypted_credentials["refresh_token"] = []
	if client_id != "":
		encrypted_credentials["client_id"] = crypto.encrypt(key, client_id.to_utf8_buffer())
	if auth_type == SpotifyNode.AuthType.AUTH_CODE:
		if client_secret != "":
			encrypted_credentials["client_secret"] = crypto.encrypt(key, client_secret.to_utf8_buffer())
	else:
		encrypted_credentials["client_secret"] = []
	if authorization_code != "":
		var lifetime := await _request_token(authorization_code)
		if !token_refresh_running:
			_refresh_token(lifetime)
	if store:
		_store_credentials()
	_check_credentials()

func _generate_code_verifier() -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var verifier: String
	for i in 128:
		verifier += chars[randi() % chars.length()]
	return verifier

func _init_credentials() -> bool:
	_init_key()
	encrypted_credentials["version"] = "0.1"
	encrypted_credentials["auth_type"] = SpotifyNode.AuthType.AUTH_CODE_PKCE
	encrypted_credentials["client_id"] = []
	encrypted_credentials["client_secret"] = []
	encrypted_credentials["refresh_token"] = []
	_load_credentials()
	return _check_credentials()

func _check_credentials() -> bool:
	var previous_auth_state := auth_state
	var credentials_complete = false
	if encrypted_credentials["client_id"].is_empty():
		auth_state = SpotifyNode.AuthState.MISSING_ID
	elif encrypted_credentials["auth_type"] == SpotifyNode.AuthType.AUTH_CODE && encrypted_credentials["client_secret"].is_empty():
		auth_state = SpotifyNode.AuthState.MISSING_SECRET
	elif encrypted_credentials["refresh_token"].is_empty():
		auth_state = SpotifyNode.AuthState.MISSING_AUTH_CODE
	else:
		credentials_complete = true
	if auth_state != previous_auth_state:
		spotify_node.auth_state_changed.emit(auth_state)
	return credentials_complete

func _store_credentials() -> void:
	if !DirAccess.dir_exists_absolute("user://SpotifyNode"):
		DirAccess.make_dir_absolute("user://SpotifyNode")
	var file = FileAccess.open("user://SpotifyNode/spotify_credentials", FileAccess.WRITE)
	file.store_buffer(var_to_bytes(encrypted_credentials))

func _load_credentials() -> bool:
	if FileAccess.file_exists("user://SpotifyNode/spotify_credentials"):
		var file := FileAccess.open("user://SpotifyNode/spotify_credentials", FileAccess.READ)
		encrypted_credentials = bytes_to_var(file.get_buffer(file.get_length()))
		return true
	else:
		return false

func _init_key() -> void:
	if key != null:
		return 
	key = CryptoKey.new()
	if !DirAccess.dir_exists_absolute("user://SpotifyNode"):
		DirAccess.make_dir_absolute("user://SpotifyNode")
	var err := key.load("user://SpotifyNode/encryption.key")
	if err != 0:
		key = crypto.generate_rsa(4096)
		key.save("user://SpotifyNode/encryption.key")
