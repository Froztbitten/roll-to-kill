extends Node
class_name SteamManager

signal lobby_created(lobby_id)
signal lobby_joined(lobby_id, steam_id)
signal player_joined(steam_id)
signal player_left(steam_id)
signal p2p_packet_received(data, from_id)

var lobby_id = 0
var opponent_ids: Array = []
var is_host = false

func _ready():
	# Check if the Steam singleton exists (GodotSteam module)
	if not ClassDB.class_exists("Steam"):
		return
		
	var steam_initialized = Steam.steamInit()
	if not steam_initialized:
		print("Failed to initialize Steam. Is the Steam client running?")
		return
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	
	# Check command line arguments for lobby invite
	_check_command_line()

func _process(_delta):
	Steam.run_callbacks()
	_read_and_emit_p2p_packets()

func _check_command_line():
	# This allows joining a lobby from a Steam invite when the game isn't running
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg == "+connect_lobby" and args.size() > args.find(arg) + 1:
			var lobby_invite_id = int(args[args.find(arg) + 1])
			join_lobby(lobby_invite_id)

func create_lobby(max_players: int = 2):
	if lobby_id == 0:
		print("Creating lobby for %d players" % max_players)
		Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, max_players)

func join_lobby(steam_lobby_id: int):
	Steam.joinLobby(steam_lobby_id)

func invite_friend():
	if lobby_id > 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)

func _on_lobby_created(connect: int, created_lobby_id: int):
	if connect == 1:
		lobby_id = created_lobby_id
		is_host = true
		print("Created Steam Lobby: %s" % lobby_id)
		emit_signal("lobby_created", lobby_id)
		
		# Set lobby data
		Steam.setLobbyData(lobby_id, "name", "RollToKill Lobby")
		Steam.setLobbyData(lobby_id, "game", "RollToKill")

func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == 1:
		lobby_id = joined_lobby_id
		is_host = false
		print("Joined Steam Lobby: %s" % lobby_id)
		var host_id = Steam.getLobbyOwner(lobby_id)
		emit_signal("lobby_joined", lobby_id, host_id)
		
		# Get all current members
		var num_members = Steam.getNumLobbyMembers(lobby_id)
		for i in range(num_members):
			var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
			if member_id != Steam.getSteamID():
				if not opponent_ids.has(member_id):
					opponent_ids.append(member_id)
				_make_p2p_handshake(member_id)

func _on_lobby_chat_update(steam_lobby_id: int, change_id: int, making_change_id: int, chat_state: int):
	if steam_lobby_id != lobby_id: return
	
	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		print("Player joined lobby: %s" % making_change_id)
		if not opponent_ids.has(making_change_id):
			opponent_ids.append(making_change_id)
		emit_signal("player_joined", making_change_id)
		_make_p2p_handshake(making_change_id)
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
		print("Player left lobby: %s" % making_change_id)
		if opponent_ids.has(making_change_id):
			opponent_ids.erase(making_change_id)
		emit_signal("player_left", making_change_id)

func _make_p2p_handshake(target_id: int):
	# Simple handshake to open P2P channel
	send_p2p_packet_to_user(target_id, {"type": "handshake"})

func _on_p2p_session_request(remote_id: int):
	# Accept all P2P requests from players in the lobby
	Steam.acceptP2PSessionWithUser(remote_id)

func send_p2p_packet_to_user(user_id: int, data: Dictionary):
	if user_id != 0:
		var packet_data = var_to_bytes(data)
		Steam.sendP2PPacket(user_id, packet_data, Steam.P2P_SEND_RELIABLE)

func send_p2p_packet_to_all(data: Dictionary):
	for id in opponent_ids:
		send_p2p_packet_to_user(id, data)

func read_p2p_packets() -> Array:
	# This function is now deprecated in favor of the signal-based approach.
	# It's kept here to prevent breaking old code that calls it, but it does nothing.
	return []

func _read_and_emit_p2p_packets():
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	while packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		if not packet.is_empty():
			var data = bytes_to_var(packet["data"])
			var from_id = packet["steam_id_remote"]
			emit_signal("p2p_packet_received", data, from_id)
		packet_size = Steam.getAvailableP2PPacketSize(0)
