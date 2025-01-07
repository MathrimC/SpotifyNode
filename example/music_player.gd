class_name MusicPlayerController
extends Node

const auth_scene := preload("res://addons/spotify_node/auth_window/spotify_auth_window.tscn")
const search_result_scene := preload("res://example/search_result.tscn")

@export var spotify_node: SpotifyNode

@export var info_label: Label
@export var progress_bar: ProgressBar
@export var play_button: Button
@export var skip_button: Button
@export var search_input: LineEdit
@export var queue_container: Container
@export var search_results_container: Container
@export var status_label: Label

var paused: bool = true
var search_results_lines: Array[SearchResult]
var queue_labels: Array[Label]

func _ready() -> void:
	spotify_node.playback_item_progress_update.connect(_on_progress)
	spotify_node.playback_item_changed.connect(_on_item_changed)
	spotify_node.playback_item_paused.connect(_on_item_paused)
	spotify_node.auth_state_changed.connect(_on_auth_state_changed)
	spotify_node.start_tracking_playback_state()
	_on_auth_state_changed(spotify_node.get_auth_state())

func _process(delta: float) -> void:
	if !paused:
		progress_bar.value += (delta * 1000) as int

func _on_item_changed(new_item: Dictionary) -> void:
	if !new_item.is_empty():
		info_label.text = "%s - %s" % [new_item["name"], new_item["artists"][0]["name"]]
	else:
		info_label.text = ""
	_refresh_queue()

func _on_progress(_progress: int, _duration: int) -> void:
	progress_bar.value = _progress
	progress_bar.max_value = _duration

func _on_item_paused(_paused: bool):
	paused = _paused
	play_button.text = ">" if paused else "||"

func _on_play_pressed() -> void:
	if paused:
		spotify_node.play()
	else:
		spotify_node.pause()
	paused = !paused
	play_button.text = ">" if paused else "||"

func _on_skip_pressed() -> void:
	spotify_node.next()

func _on_previous_pressed() -> void:
	spotify_node.previous()

func _on_search_button_pressed() -> void:
	for line in search_results_lines:
		line.queue_free()
	search_results_lines.clear()
	var search_results := await spotify_node.search(search_input.text, [SpotifyNode.ItemType.TRACK])
	if search_results.is_empty():
		return
	for item in search_results["tracks"]["items"]:
		var search_result: SearchResult = search_result_scene.instantiate()
		search_result.item = item
		search_result.music_player_controller = self
		search_results_container.add_child(search_result)
		search_results_lines.append(search_result)
	search_results_container.show()

func _on_search_and_add_pressed() -> void:
	for line in search_results_lines:
		line.queue_free()
	search_results_lines.clear()
	await spotify_node.add_item_to_queue_by_search(search_input.text, SpotifyNode.ItemType.TRACK)
	_refresh_queue()

func add_search_result_to_queue(item: Dictionary) -> void:
	await spotify_node.add_item_to_queue_by_uri(item["uri"])
	_refresh_queue()

func _refresh_queue() -> void:
	var queue_position: int = 0
	for item in await spotify_node.get_queue():
		if queue_position < queue_labels.size():
			queue_labels[queue_position].text = "%s. %s - %s" % [queue_position + 1, item["name"], item["artists"][0]["name"]]
		else:
			var label := Label.new()
			label.text = "%s. %s - %s" % [queue_position + 1, item["name"], item["artists"][0]["name"]]
			queue_container.add_child(label)
			queue_labels.append(label)
		queue_position += 1
	while queue_position < queue_labels.size():
		queue_labels[queue_position].pop_back().queue_free()

func _on_spotify_button_pressed() -> void:
	OS.shell_open("https://open.spotify.com/")

func _on_auth_settings_pressed() -> void:
	var auth_window: SpotifyAuthWindow = auth_scene.instantiate()
	auth_window.set_spotify_node(spotify_node)
	add_child(auth_window)

func _on_auth_state_changed(_auth_state: SpotifyNode.AuthState) -> void:
	match _auth_state:
		SpotifyNode.AuthState.VALID:
			var profile_info := await spotify_node.get_current_user_profile()
			status_label.text = profile_info["display_name"]
			status_label.self_modulate = Color.WHITE
		SpotifyNode.AuthState.REFRESHING:
			status_label.text = "Reconnecting"
			status_label.self_modulate = Color.ORANGE
		_:
			status_label.text = "Disconnected"
			status_label.self_modulate = Color.RED
