extends Control

signal open_quest_board
signal open_shop
signal open_map

func _ready():
	visible = false

func open():
	visible = true

func _on_quest_board_button_pressed():
	emit_signal("open_quest_board")

func _on_shop_button_pressed():
	emit_signal("open_shop")

func _on_map_button_pressed():
	emit_signal("open_map")
