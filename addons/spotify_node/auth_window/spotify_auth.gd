class_name SpotifyAuth
extends MarginContainer

enum { INACTIVE, LISTENING }

const redirect_bind_address := "127.0.0.1"
const filled_field_text := "ThisIsAFakeTokenForATextField!!!"

const redirect_uri: String = "http://127.0.0.1"
const redirect_port: int = 7346
const help_texts := {
	SpotifyNode.AuthType.AUTH_CODE: "* Create an application in the [url=https://developer.spotify.com/dashboard]Spotify Developer Dashboard[/url] and copy the Client ID and Client Secret to the fields above. Make sure the OAuth Redirect URL is set to http://localhost:7346",
	SpotifyNode.AuthType.AUTH_CODE_PKCE: "* Create an application in the [url=https://developer.spotify.com/dashboard]Spotify Developer Dashboard[/url] and copy the Client ID to the fields above. Make sure the OAuth Redirect URL is set to http://localhost:7346",
}
@export var spotify_node: SpotifyNode

@export var auth_type_dropdown: OptionButton
@export var application_id_input: LineEdit
@export var application_secret_container: Container
@export var application_secret_input: LineEdit
@export var authorization_code_input: LineEdit
@export var authorization_code_button: Button
@export var status_label: Label
@export var status_icon: TextureRect
@export var help_label: RichTextLabel

var redirect_server := TCPServer.new()
var server_status = INACTIVE
var state_code: String
var auth_type: SpotifyNode.AuthType

func _ready() -> void:
	application_secret_container.hide()
	if spotify_node == null:
		spotify_node = SpotifyNode.new()
		add_child(spotify_node)
	auth_type = spotify_node.get_auth_type()
	auth_type_dropdown.selected = auth_type
	help_label.text = help_texts[auth_type]
	spotify_node.auth_state_changed.connect(_refresh_ui)
	application_id_input.text = spotify_node.get_client_id()
	authorization_code_input.hide()
	_refresh_ui()

func set_spotify_node(_spotify_node: SpotifyNode) -> void:
	if spotify_node != null:
		spotify_node.queue_free()
	spotify_node = _spotify_node

func on_auth_type_selected(index: int):
	match index:
		SpotifyNode.AuthType.AUTH_CODE:
			application_secret_container.show()
		SpotifyNode.AuthType.AUTH_CODE_PKCE:
			application_secret_container.hide()
	auth_type = index
	spotify_node.set_credentials(auth_type, "", "", "", true)

func on_client_id_changed(_client_id: String) -> void:
	spotify_node.set_credentials(auth_type,_client_id, "", "", true)
	if _client_id.length() == 32:
		application_id_input.self_modulate = Color.WHITE
	else:
		application_id_input.self_modulate = Color.DARK_RED
	_refresh_ui()

func on_client_secret_changed(_client_secret: String) -> void:
	if _client_secret.length() > 0:
		spotify_node.set_credentials(auth_type,"", _client_secret, "", true)
		application_secret_input.self_modulate = Color.WHITE
		if server_status != INACTIVE:
			_end_auth_flow()
	else:
		application_secret_input.self_modulate = Color.DARK_RED

func on_authorization_code_changed(_authorization_code: String) -> void:
	if _authorization_code.length() == 30:
		spotify_node.set_credentials(auth_type,"", "", _authorization_code, true)
		authorization_code_input.self_modulate = Color.WHITE
		if server_status != INACTIVE:
			_end_auth_flow()
	else:
		authorization_code_input.self_modulate = Color.DARK_RED

func on_authorization_code_button_pressed() -> void:
	if authorization_code_button.text == "Cancel":
		_end_auth_flow()
	else:
		_open_auth_url()

func open_dev_dashboard(_meta: Variant):
	OS.shell_open("https://developer.spotify.com/dashboard")

func _open_auth_url() -> void:
	redirect_server.listen(redirect_port, redirect_bind_address)
	server_status = LISTENING
	state_code = _generate_state_code()
	var url = spotify_node.get_auth_url("%s:%s" % [redirect_uri, redirect_port], state_code)
	OS.shell_open(url)
	_refresh_ui()

func _generate_state_code() -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var state_code: String
	for i in 64:
		state_code += chars[randi() % chars.length()]
	return state_code

func _process(_delta: float) -> void:
	if redirect_server.is_connection_available():
		var connection = redirect_server.take_connection()
		var byte_count := connection.get_available_bytes()
		var request = connection.get_utf8_string(byte_count)
		var code := request.split("code=")[1].split("&")[0]
		var returned_state_code := request.split("state=")[1].split(" ")[0]
		var response_code := 200
		if returned_state_code == state_code && code != "":
			spotify_node.set_credentials(auth_type,"", "", code, true)
		else:
			response_code = 400
		connection.put_data(("HTTP/1.1 %d\r\n" % response_code).to_ascii_buffer())
		connection.put_data(_get_redirect_page(response_code).to_ascii_buffer())
		_end_auth_flow()

func _end_auth_flow():
	redirect_server.stop()
	server_status = INACTIVE
	_refresh_ui()

func _refresh_ui(_auth_state: SpotifyNode.AuthState = 0) -> void:
	match auth_type:
		SpotifyNode.AuthType.AUTH_CODE:
			application_secret_container.show()
		SpotifyNode.AuthType.AUTH_CODE_PKCE:
			application_secret_container.hide()
	help_label.text = help_texts[auth_type]
	if application_id_input.text.length() == 32:
		application_id_input.self_modulate = Color.WHITE
		match server_status:
			INACTIVE:
				authorization_code_input.hide()
				authorization_code_button.text = "Create New Code"
			LISTENING:
				authorization_code_input.show()
				authorization_code_button.text = "Cancel"
	else:
		application_id_input.self_modulate = Color.RED
		authorization_code_button.disabled = true

	match spotify_node.get_auth_state():
		SpotifyNode.AuthState.MISSING_ID:
			application_id_input.text = ""
			application_id_input.self_modulate = Color.RED
			application_secret_input.text = ""
			application_secret_input.self_modulate = Color.RED
			authorization_code_input.text = ""
			authorization_code_input.self_modulate = Color.RED
			authorization_code_button.disabled = true
			status_label.text = "Missing client id"
			status_label.self_modulate = Color.RED
		SpotifyNode.AuthState.MISSING_SECRET:
			application_secret_input.text = ""
			application_secret_input.self_modulate = Color.RED
			authorization_code_input.text = ""
			authorization_code_input.self_modulate = Color.RED
			authorization_code_button.disabled = true
			status_label.text = "Missing client secret"
			status_label.self_modulate = Color.RED
		SpotifyNode.AuthState.MISSING_AUTH_CODE:
			application_secret_input.text = filled_field_text
			application_secret_input.self_modulate = Color.WHITE
			authorization_code_button.disabled = false
			authorization_code_input.text = ""
			authorization_code_input.self_modulate = Color.RED
			authorization_code_button.disabled = false
			status_label.text = "Missing authorization code"
			status_label.self_modulate = Color.RED
		SpotifyNode.AuthState.VALID, SpotifyNode.AuthState.REFRESHING:
			application_secret_input.text = filled_field_text
			application_secret_input.self_modulate = Color.WHITE
			authorization_code_input.text = filled_field_text
			authorization_code_input.self_modulate = Color.WHITE
			status_label.text = "Valid credentials"
			status_label.self_modulate = Color.GREEN
		SpotifyNode.AuthState.INVALID:
			status_label.text = "Invalid credentials"
			status_label.self_modulate = Color.RED
		SpotifyNode.AuthState.REFRESHING:
			application_secret_input.text = filled_field_text
			application_secret_input.self_modulate = Color.WHITE
			authorization_code_input.text = filled_field_text
			authorization_code_input.self_modulate = Color.WHITE
			status_label.text = "Refreshing"
			status_label.self_modulate = Color.ORANGE

func _get_redirect_page(response_code: int) -> String:
	var path: String
	if response_code == 200:
		path = "res://addons/spotify_node/auth_window/redirectpage.html"
	else:
		path = "res://addons/spotify_node/auth_window/redirectpage-failed.html"
	var page := FileAccess.get_file_as_string(path)
	if page == "":
		printerr("error retrieving redirect page for %s" % response_code)
	return page
