extends Control

@onready var player_labels: Array[Label] = [
	$VBoxContainer/PlayerListContainer/Player1Label,
	$VBoxContainer/PlayerListContainer/Player2Label,
	$VBoxContainer/PlayerListContainer/Player3Label,
	$VBoxContainer/PlayerListContainer/Player4Label,
]
@onready var invite_button = $VBoxContainer/Buttons/InviteButton
@onready var start_game_button = $VBoxContainer/Buttons/StartGameButton

var steam_manager

func _ready():
	if not get_tree().root.has_node("SteamManager"):
		print("SteamManager not found!")
		get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")
		return
	steam_manager = get_tree().root.get_node("SteamManager")

	steam_manager.lobby_created.connect(_on_lobby_created)
	steam_manager.lobby_joined.connect(_on_lobby_joined)
	steam_manager.player_joined.connect(_on_player_joined)
	steam_manager.player_left.connect(_on_player_left)
	steam_manager.p2p_packet_received.connect(_on_p2p_packet_received)

	# Create a lobby for 4 players when entering this screen
	steam_manager.create_lobby(4)
	invite_button.disabled = true
	start_game_button.disabled = true

func _on_lobby_created(_lobby_id):
	# This player is the host
	start_game_button.visible = true
	start_game_button.disabled = false
	invite_button.disabled = false
	_update_player_list()

func _on_lobby_joined(_lobby_id, _host_id):
	# This player is a client
	start_game_button.visible = false
	invite_button.disabled = true # Only host can invite
	_update_player_list()

func _on_player_joined(_steam_id):
	_update_player_list()

func _on_player_left(_steam_id):
	_update_player_list()

func _update_player_list():
	if not steam_manager or steam_manager.lobby_id == 0:
		return

	var num_members = Steam.getNumLobbyMembers(steam_manager.lobby_id)
	for i in range(player_labels.size()):
		if i < num_members:
			var member_id = Steam.getLobbyMemberByIndex(steam_manager.lobby_id, i)
			var member_name = Steam.getFriendPersonaName(member_id)
			player_labels[i].text = "%d. %s" % [i + 1, member_name]
		else:
			player_labels[i].text = "%d. Waiting for player..." % [i + 1]

func _on_invite_button_pressed():
	steam_manager.invite_friend()

func _on_start_game_pressed():
	if not steam_manager.is_host: return

	steam_manager.send_p2p_packet_to_all({"type": "start_game"})
	_start_game()

func _on_p2p_packet_received(data, _from_id):
	if data.type == "start_game":
		_start_game()

func _start_game():
	GameState.is_multiplayer = true
	var members = []
	var num_members = Steam.getNumLobbyMembers(steam_manager.lobby_id)
	for i in range(num_members):
		members.append(Steam.getLobbyMemberByIndex(steam_manager.lobby_id, i))
	GameState.player_steam_ids = members
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_back_button_pressed():
	if steam_manager and steam_manager.lobby_id != 0:
		Steam.leaveLobby(steam_manager.lobby_id)
		steam_manager.lobby_id = 0
		steam_manager.opponent_ids.clear()
		steam_manager.is_host = false
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")