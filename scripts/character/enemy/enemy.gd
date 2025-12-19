extends Character
class_name Enemy

@export var enemy_data: EnemyData

signal exploded(damage, source)

var next_action: EnemyAction
var next_action_value: int = 0
var _is_charging := false
var _turn_count := 0
var _provided_shields: Array[Dictionary] = []

@onready var intent_display: Control = $EnemyIntentDisplay
@onready var sprite: TextureRect = $Sprite2D
@onready var status_display: HBoxContainer = $StatusCanvas/StatusEffectDisplay

func _ready():
	super._ready()
	# Hide the intent display by default to prevent showing stale data on spawn.
	intent_display.visible = false
	statuses_changed.connect(_on_statuses_changed)
	call_deferred("_center_intent_display")
	if not enemy_data:
		# Disable the enemy if it has no data, to prevent crashes.
		# This can be useful for debugging in the editor.
		print_debug("Enemy has no EnemyData assigned. Disabling.")
		set_process(false)
		return

	setup()

func _process(delta):
	# Manually position the status display relative to the enemy's global position,
	# since it's on a separate CanvasLayer.
	if is_instance_valid(status_display):
		status_display.global_position = global_position + Vector2(-19, -5)

func setup():
	"""Initializes the enemy's stats and appearance from its EnemyData resource."""
	name_label.text = enemy_data.enemy_name
	sprite.texture = enemy_data.sprite_texture
	
	var rolled_hp = 0
	for hp_die in enemy_data.hp_dice:
		rolled_hp += hp_die.roll()
	
	# Set the health properties inherited from the Character class
	# Ensure the starting HP is not below the defined minimum.
	var starting_hp = rolled_hp + enemy_data.minimum_hp
	max_hp = starting_hp
	hp = starting_hp
	_is_charging = false
	_turn_count = 0
	update_health_display()

func declare_intent(active_enemies: Array):
	_turn_count += 1
	# Guard against calling this on an enemy that has no data assigned.
	if not enemy_data or enemy_data.action_pool.is_empty():
		return

	# --- Special Boss Logic ---
	if enemy_data.enemy_name == "Evil Dice Tower":
		if _turn_count == 1:
			# First turn is always Summon Minions
			for action in enemy_data.action_pool:
				if action.action_type == EnemyAction.ActionType.SPAWN_MINIONS:
					next_action = action
					break
		else:
			# Subsequent turns have conditional logic
			var possible_actions = enemy_data.action_pool.duplicate()
			var other_enemy_count = active_enemies.size() - 1

			if other_enemy_count > 2:
				# Remove Summon Minions if more than 2 allies are present
				possible_actions = possible_actions.filter(func(a): return a.action_type != EnemyAction.ActionType.SPAWN_MINIONS)
			
			if other_enemy_count < 2 or has_status("Advantageous"):
				# Remove Inspiration if less than 2 allies are present OR if advantage is already active on the boss.
				possible_actions = possible_actions.filter(func(a): return a.action_type != EnemyAction.ActionType.BUFF)

			# If filtering leaves no actions, default to the shield move as a safe fallback.
			if possible_actions.is_empty():
				for action in enemy_data.action_pool:
					if action.action_type == EnemyAction.ActionType.SHIELD:
						next_action = action
						break
			else:
				next_action = possible_actions.pick_random()
	# Special logic for Goblin Warchief
	elif enemy_data.enemy_name == "Goblin Warchief":
		var bodyguards_alive = false
		for e in active_enemies:
			if e.enemy_data.enemy_name == "Ogre Bodyguard" and not e._is_dead:
				bodyguards_alive = true
				break
		
		var possible_actions = []
		if bodyguards_alive:
			possible_actions = enemy_data.action_pool.filter(func(a): return a.action_name == "King of Cowards" or a.action_name == "Warstrike")
		else:
			possible_actions = enemy_data.action_pool.filter(func(a): return a.action_name == "Fight" or a.action_name == "Flight" or a.action_name == "Fright")
		
		if not possible_actions.is_empty():
			next_action = possible_actions.pick_random()
		else:
			next_action = enemy_data.action_pool[0]
	# Special logic for D6 Healer
	elif enemy_data.enemy_name == "D6":
		var injured_allies = active_enemies.filter(func(e): return e != self and e.hp < e.max_hp)
		if not injured_allies.is_empty():
			# Find the heal action
			for action in enemy_data.action_pool:
				if action.action_type == EnemyAction.ActionType.HEAL_ALLY:
					next_action = action
					break
		else:
			# Find the do nothing action
			for action in enemy_data.action_pool:
				if action.action_type == EnemyAction.ActionType.DO_NOTHING:
					next_action = action
					break
	# Specific enemies with two actions alternate between them.
	elif enemy_data.action_pool.size() == 2 and (
		enemy_data.enemy_name == "Goblin Archer" or 
		enemy_data.enemy_name == "D10" or 
		enemy_data.enemy_name == "D20"):
		# The _is_charging flag is used to track which action to use.
		# false = action_pool[0], true = action_pool[1]
		if _is_charging:
			next_action = enemy_data.action_pool[1]
			_is_charging = false
		else:
			next_action = enemy_data.action_pool[0]
			_is_charging = true
	else:
		# Default behavior: pick a random action from the pool.
		next_action = enemy_data.action_pool.pick_random()
		_is_charging = false # Reset in case it's a mixed-type enemy

	print("Next action: ", next_action.action_name)
	# Roll the dice for that action and sum the result
	next_action_value = next_action.base_value
	if not next_action.ignore_dice_roll:
		var advantage = has_status("Advantageous")
		for action_die: Die in next_action.dice_to_roll:
			next_action_value += action_die.roll(advantage)
	
	# Safely get the icon for the intent display.
	# This prevents a crash if an action has no dice.
	var die_sides_for_icon = 8 # Default to d8 icon
	if not next_action.dice_to_roll.is_empty():
		die_sides_for_icon = next_action.dice_to_roll[0].sides

	var intent_icon_type = "attack"
	if next_action.dice_to_roll.is_empty():
		# Any action with no dice is considered a "charge" or "setup" move.
		intent_icon_type = "charge"
	elif next_action.action_type == EnemyAction.ActionType.SHIELD or next_action.action_type == EnemyAction.ActionType.SUPPORT_SHIELD:
		intent_icon_type = "shield"
	elif next_action.action_type == EnemyAction.ActionType.HEAL_ALLY:
		intent_icon_type = "heal"

	# Update the UI to show the intent
	intent_display.update_display(next_action.action_name, next_action_value, die_sides_for_icon, intent_icon_type, next_action.dice_to_roll.size())
	intent_display.visible = true


func clear_intent():
	next_action_value = 0
	next_action = null
	intent_display.visible = false

func _on_statuses_changed(current_statuses: Dictionary):
	status_display.update_display(current_statuses)

func _center_intent_display():
	if not is_inside_tree() or not intent_display: return
	# This function vertically centers the intent display relative to the sprite.
	var sprite_center_y = sprite.position.y + (sprite.size.y / 2)
	intent_display.position.x = -150 # Position it to the left of the enemy sprite.
	intent_display.position.y = sprite_center_y - (intent_display.size.y / 2)

func register_provided_shield(target: Character, amount: int):
	_provided_shields.append({"target": target, "amount": amount})

func clear_provided_shields():
	_provided_shields.clear()

func die() -> void:
	# Override the Character's die() function to add special on-death effects.
	if not _is_dead and enemy_data and enemy_data.enemy_name == "Wick-wock":
		var explosion_die = Die.new(8)
		var damage = explosion_die.roll()
		print("Wick-wock explodes, dealing %d damage to the player!" % damage)
		emit_signal("exploded", damage, self)

	# Remove provided shields from allies if this unit dies.
	if not _is_dead:
		for entry in _provided_shields:
			var target = entry.target
			var amount = entry.amount
			if is_instance_valid(target) and not target._is_dead and target != self:
				target.block = max(0, target.block - amount)
				target.update_health_display()
		_provided_shields.clear()

	# Explicitly hide the status display to ensure debuffs are visually removed immediately.
	if status_display:
		status_display.visible = false
		if status_display.get_parent() is CanvasLayer:
			status_display.get_parent().visible = false

	# Call the original die function to handle the rest of the death process.
	super.die()
