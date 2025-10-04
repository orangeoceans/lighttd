extends Node2D


const GAME_SCENE_PATH = "res://scenes/game.tscn"


func _ready():
	# Automatically focus on the Start Game button when the scene loads
	$"CanvasLayer/Control/Start Game".grab_focus()

func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_exit_game_pressed() -> void:
	get_tree().quit()
