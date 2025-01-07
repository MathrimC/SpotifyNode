class_name SpotifyAuthWindow
extends Window

@export var spotify_auth: SpotifyAuth

func _on_close_requested() -> void:
	self.queue_free()

func set_spotify_node(spotify_node: SpotifyNode) -> void:
	spotify_auth.set_spotify_node(spotify_node)
