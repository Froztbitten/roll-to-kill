extends Control

@onready var gold_label: Label = $Panel/VBoxContainer/Header/GoldLabel
@onready var remove_die_button: Button = $Panel/VBoxContainer/Options/RemoveDieButton
@onready var upgrade_die_button: Button = $Panel/VBoxContainer/Options/UpgradeDieButton
@onready var effects_container: HBoxContainer = $Panel/VBoxContainer/Options/EffectsContainer
@onready var abilities_container: HBoxContainer = $Panel/VBoxContainer/Options/AbilitiesContainer
@onready var selection_overlay: Control = $SelectionOverlay
@onready var selection_grid: GridContainer = $SelectionOverlay/ScrollContainer/GridContainer
@onready var selection_title: Label = $SelectionOverlay/TitleLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var player: Player
var current_mode = "" # "remove" or "upgrade"

func _ready():
	visible = false
	selection_overlay.visible = false
	
	# Auto-connect to MapScreen if present in the scene tree
	var map_screen = get_node_or_null("../MapScreen")
	if map_screen:
		map_screen.node_selected.connect(_on_map_node_selected)

func _on_map_node_selected(node_data):
	if node_data.type == "shop":
		open()

func open():
	player = get_node_or_null("../../Player")
	if not player: return
	
	visible = true
	_update_ui()
	_generate_shop_inventory()

func _update_ui():
	gold_label.text = "Gold: %d" % player.gold
	remove_die_button.text = "Remove Die (%dg)" % player.die_removal_cost
	
	if player.gold < player.die_removal_cost:
		remove_die_button.disabled = true
	else:
		remove_die_button.disabled = false

func _generate_shop_inventory():
	# Clear previous
	for child in effects_container.get_children():
		child.queue_free()
	for child in abilities_container.get_children():
		child.queue_free()
		
	# Generate 3 Random Effects
	for i in range(3):
		var btn = Button.new()
		# Try to get a random effect from the library, or fallback to a dummy one
		var effect = null
		if ClassDB.class_exists("EffectLibrary") or (EffectLibrary if "EffectLibrary" in get_tree().root else null):
			# Assuming EffectLibrary is an autoload or class we can access
			# Since I can't see EffectLibrary, I'll create a simple placeholder effect
			effect = DieFaceEffect.new("Fire", "Deal 2 damage", 1, Color.ORANGE_RED)
		else:
			# Fallback effects
			var types = [
				{"name": "Fire", "color": Color.ORANGE_RED, "desc": "Burn 2"},
				{"name": "Ice", "color": Color.CYAN, "desc": "Freeze"},
				{"name": "Void", "color": Color.PURPLE, "desc": "Void"}
			]
			var data = types.pick_random()
			effect = DieFaceEffect.new(data.name, data.desc, 1, data.color)
			
		btn.text = "%s (50g)" % effect.name
		btn.custom_minimum_size = Vector2(100, 60)
		btn.pressed.connect(_on_buy_effect_pressed.bind(effect, 50, btn))
		effects_container.add_child(btn)

	# Generate 3 Random Abilities
	var ability_files = DirAccess.get_files_at("res://resources/abilities/")
	if ability_files:
		var shuffled_files = Array(ability_files)
		shuffled_files.shuffle()
		for i in range(min(3, shuffled_files.size())):
			var file_name = shuffled_files[i]
			if file_name.ends_with(".tres") or file_name.ends_with(".remap"):
				file_name = file_name.replace(".remap", "")
				var ability = load("res://resources/abilities/" + file_name) as AbilityData
				if ability:
					var btn = Button.new()
					btn.text = "%s (150g)" % ability.title
					btn.custom_minimum_size = Vector2(100, 60)
					btn.pressed.connect(_on_buy_ability_pressed.bind(ability, 150, btn))
					abilities_container.add_child(btn)

func _on_remove_die_pressed():
	if player.gold < player.die_removal_cost: return
	current_mode = "remove"
	_show_dice_selection("Select Die to Remove")

func _on_upgrade_die_pressed():
	current_mode = "upgrade"
	_show_dice_selection("Select Die to Upgrade")

func _show_dice_selection(title: String):
	selection_title.text = title
	selection_overlay.visible = true
	
	for child in selection_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var btn = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		selection_grid.add_child(btn)
		btn.set_die(die)
		btn.pressed.connect(_on_die_selected.bind(die))

func _on_die_selected(die: Die):
	if current_mode == "remove":
		if player.gold >= player.die_removal_cost:
			player.add_gold(-player.die_removal_cost)
			player.remove_die_from_bag(die)
			player.die_removal_cost += 25
			_update_ui()
			selection_overlay.visible = false
			
	elif current_mode == "upgrade":
		var upgrades = die.get_meta("upgrade_count", 0)
		if upgrades >= 3:
			print("Die is fully upgraded!")
			return
			
		var cost = 50 * (upgrades + 1)
		if player.gold >= cost:
			player.add_gold(-cost)
			player.upgrade_die(die)
			_update_ui()
			selection_overlay.visible = false
		else:
			print("Not enough gold!")

func _on_buy_effect_pressed(effect, cost, button):
	if player.gold >= cost:
		player.add_gold(-cost)
		player.apply_effect_to_random_dice(effect)
		button.disabled = true
		button.text = "Sold"
		_update_ui()

func _on_buy_ability_pressed(ability, cost, button):
	if player.gold >= cost:
		player.add_gold(-cost)
		player.add_ability(ability)
		button.disabled = true
		button.text = "Sold"
		_update_ui()

func _on_close_button_pressed():
	visible = false
	# Signal Main to continue or go back to map?
	# Assuming Main handles state, but for now we just hide.
	# If MapScreen is visible behind, we might need to re-enable it.
	var map_screen = get_node_or_null("../MapScreen")
	if map_screen:
		map_screen.visible = true

func _on_cancel_selection_pressed():
	selection_overlay.visible = false
