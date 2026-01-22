extends Label

func _ready():
	# Find the player node in the scene tree
	var player = get_tree().current_scene.find_child("Player")
	if player:
		_connect_player(player)

func _connect_player(player):
	if not player.is_connected("hp_changed", _update_text):
		player.hp_changed.connect(_update_text)
	# Initial update
	_update_text(player.hp, player.max_hp)

func _update_text(hp, max_hp):
	text = "%d / %d" % [hp, max_hp]