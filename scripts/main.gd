extends Node2D

var end_turn_button: Button
@onready var dice_ui: DiceUI = $"UI/DiceUI"
@onready var dice_bag_ui: Control = $"UI/DiceBagUI"

var intents: Dictionary = {}

func _ready():
	end_turn_button = $"UI/EndTurnButton"
	GameManager.player = $Player
	GameManager.enemy = $Enemies.get_child(0)
	end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	dice_ui.intent_created.connect(_on_intent_created)
	
	player_turn()

func player_turn():
	dice_ui.clear_arrows()
	# Reset block at the start of the turn
	GameManager.player.block = 0
	intents = {}
	
	var rolled_dice = []
	var hand = GameManager.player.draw_hand()
	for die in hand:
		var roll = die.roll()
		rolled_dice.append({"value": roll, "sides": die.sides})
	
	dice_ui.set_hand(rolled_dice)
	dice_bag_ui.update_label(GameManager.player.dice.size())
	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if GameManager.current_turn == GameManager.Turn.PLAYER:
		resolve_dice_intents()
		GameManager.next_turn()
		enemy_turn()

func resolve_dice_intents():
	for intent in intents.values():
		if intent.target is Player:
			GameManager.player.block += intent.roll
		else:
			Utils.take_turn(GameManager.player, intent.target)
		
	print("Player block: " + str(GameManager.player.block))

func enemy_turn():
	end_turn_button.disabled = true
	await get_tree().create_timer(1.0).timeout
	if GameManager.current_turn == GameManager.Turn.ENEMY:
		Utils.take_turn(GameManager.enemy, GameManager.player)
		GameManager.next_turn()
		player_turn()

func _on_intent_created(die, roll, target):
	if target:
		intents[die] = {"roll": roll, "target": target}
	elif intents.has(die):
		intents.erase(die)
	print("Intents: " + str(intents))
