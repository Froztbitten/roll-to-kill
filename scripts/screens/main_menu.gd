extends Control

func _on_start_button_pressed():
	# Transition to the main game scene
	MainGame.debug_mode = false
	get_tree().root.set_meta("force_shop_encounter", false)
	get_tree().root.set_meta("tutorial_mode", false)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_tutorial_button_pressed():
	MainGame.debug_mode = false
	get_tree().root.set_meta("tutorial_mode", true)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_debug_button_pressed():
	# Enable debug mode and start game
	MainGame.debug_mode = true
	get_tree().root.set_meta("force_shop_encounter", true)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
