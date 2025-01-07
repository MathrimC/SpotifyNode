class_name SpotifyNode
extends Node

enum ItemType { ALBUM, ARTIST, PLAYLIST, TRACK, SHOW, EPISODE, AUDIOBOOK }
enum AuthState { EMPTY, MISSING_ID, MISSING_SECRET, MISSING_AUTH_CODE, VALID, INVALID, REFRESHING, UNKNOWN }
enum AuthType { AUTH_CODE, AUTH_CODE_PKCE }

signal playback_item_progress_update(progress_ms: int, duration_ms: int)
signal playback_item_changed(new_item: Dictionary)
signal playback_item_paused(paused: bool)

signal auth_state_changed(auth_state: AuthState)

@export var playing_refresh_time_s: float = 1.0
@export var paused_refresh_time_s: float = 4.0

var is_tracking := false
var playback_state: Dictionary

var user_id: String
var _spotify_api: SpotifyAPI

func _ready() -> void:
	playback_state = {"is_playing": false, "item": {"id": ""}}
	_spotify_api = SpotifyAPI.new()
	_spotify_api.spotify_node = self
	add_child(_spotify_api)

## auth_type: AUTH_CODE uses client secret, AUTH_CODE_PKCE uses a randomly generated code verifier [br]
## client_id: application client id (from Spotify Developer Console) [br]
## client_secret token: application client secret (from Spotify Developer Console) (will be discarded if auth type is AUTH_CODE_PKCE) [br]
## authorizaiton_code: code generated when authorizing the application as a user [br]
## Store: whether or not the credentials should be stored in an encrypted file in the project user directory. If yes, they will be retreived automatically next time the program runs
func set_credentials(auth_type: AuthType, client_id: String, client_secret: String, authorization_code: String, store: bool) -> void:
	_spotify_api.set_credentials(auth_type, client_id, client_secret, authorization_code, store)

func get_client_id() -> String:
	return _spotify_api.get_client_id()

func get_auth_type() -> AuthType:
	return _spotify_api.get_auth_type()

## After calling this, the playback state will be checked regularly (determined by the playing_refresh_time variables), and the playback_item signals will be emitted
func start_tracking_playback_state() -> void:
	if !is_tracking:
		is_tracking = true
		_spotify_api.track_playback_state()

func stop_tracking_playback_state() -> void:
	is_tracking = false

## In case tracking is active, the most recently retrieved playback state is returned. In case tracking is not active, the playback state will be retrieved from Spotify
func get_playback_state() -> Dictionary:
	if is_tracking:
		return playback_state
	else:
		return await _spotify_api.get_playback_state()

func get_available_devices() -> Array:
	return await _spotify_api.get_available_devices()

func get_recently_played_tracks() -> Array:
	return await _spotify_api.get_recently_played_tracks()

func next(device_id: String = "") -> bool:
	return await _spotify_api.next(device_id)

func previous(device_id: String = "") -> bool:
	return await _spotify_api.previous(device_id)

func play(device_id: String = "", context_uri: String = "", track_uris: Array[String] = [], offset_nbr: int = 0, offset_uri: String = "", position_ms: int = 0) -> bool:
	return await _spotify_api.play(device_id, context_uri, track_uris, offset_nbr, offset_uri, position_ms)

func pause(device_id: String = "") -> bool:
	return await _spotify_api.pause()

func set_playback_volume(volume_pct: int) -> bool:
	return await _spotify_api.set_playback_volume(volume_pct)

## Returns an array with spotify item dictionaries
func get_queue() -> Array:
	return await _spotify_api.get_queue()

func add_item_to_queue_by_uri(request_uri: String) -> bool:
	return await _spotify_api.add_item_to_queue(request_uri)

## Adds the first result to the queue. Item types can contain "track", "playlist", "artist", "album", "show". Returns the item that was added to the queue.
func add_item_to_queue_by_search(search_query: String, item_type: ItemType = ItemType.TRACK) -> Dictionary:
	if search_query == "":
		printerr("Can't add item to queue based on empty search query")
		return {}
	var search_results := await _spotify_api.search(search_query, [item_type], 1)
	var type_str: String = ItemType.keys()[item_type]
	type_str = type_str.to_lower() + "s"
	var uri: String = search_results[type_str]["items"][0]["uri"]
	if await _spotify_api.add_item_to_queue(uri):
		return search_results[type_str]["items"][0]
	else:
		printerr("Adding item to queue failed. There is probably no active spotify session.")
		return {}

func get_current_playlist_uri() -> String:
	var state := await get_playback_state()
	if state["context"]["type"] == "playlist":
		return state["context"]["uri"]
	else:
		return ""

func get_current_playlist_info() -> Dictionary:
	return await get_playlist_info(await get_current_playlist_uri())

func get_current_user_playlists() -> Array:
	var playlists := await _spotify_api.get_current_user_playlists()
	if !playlists.is_empty():
		return playlists["items"]
	else:
		return []

func get_user_playlists() -> Array:
	if user_id == "":
		var profile_info := await _spotify_api.get_user_profile()
		if !profile_info.is_empty():
			user_id = profile_info["id"]
		else:
			printerr("Error retrieving spotify profile info")
			return []
	var playlists := await _spotify_api.get_user_playlists(user_id)
	if playlists.is_empty():
		return playlists["items"]
	else:
		return []

func get_playlist_info(playlist_uri: String) -> Dictionary:
	if playlist_uri.begins_with("http"):
		playlist_uri = playlist_uri.split("/")[-1].split("?")[0]
	return await _spotify_api.get_playlist(playlist_uri)

func get_current_user_profile() -> Dictionary:
	return await _spotify_api.get_user_profile()

func search(query: String, types: Array[SpotifyNode.ItemType]) -> Dictionary:
	return await _spotify_api.search(query, types, 50)

func _update_playback_state(new_state: Dictionary) -> void:
	if new_state.is_empty():
		new_state = {"is_playing": false, "item": {"id": ""}}
	if new_state["is_playing"] != playback_state["is_playing"]:
		playback_item_paused.emit(!new_state["is_playing"])
	if new_state["item"]["id"] != playback_state["item"]["id"]:
		var item: Dictionary = new_state["item"]
		playback_item_changed.emit(item)
	if new_state["is_playing"]:
		playback_item_progress_update.emit(new_state["progress_ms"],new_state["item"]["duration_ms"])
	playback_state = new_state

func get_auth_state() -> AuthState:
	return _spotify_api.auth_state

func get_auth_url(_redirect_uri: String, _state: String = "") -> String:
	return _spotify_api.get_auth_url(_redirect_uri, _state)
