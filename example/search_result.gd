class_name SearchResult
extends HBoxContainer

@export var label: Label

var item: Dictionary
var music_player_controller: MusicPlayerController

func _ready() -> void:
	label.text = "%s - %s" % [item["name"], item["artists"][0]["name"]]

func _on_button_pressed() -> void:
	music_player_controller.add_search_result_to_queue(item)
