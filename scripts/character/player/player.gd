extends Character
class_name Player

signal dice_bag_changed(new_amount)
signal dice_discard_changed(new_amount)
signal gold_changed(new_amount)
signal abilities_changed(new_ability)
signal dice_drawn(drawn_dice)

@export var abilities: Array[AbilityData] = []

var _game_dice_bag: Array[Die] = []
var _round_dice_bag: Array[Die] = []
var _dice_discard: Array[Die] = []
var _held_dice: Array[Die] = []
var gold: int = 0
var _shield_sound: AudioStream
@onready var status_display: HBoxContainer = $StatusCanvas/StatusEffectDisplay

var dice_pool_size = 4


func _ready():
	super._ready()
	_shield_sound = load("res://assets/ai/sounds/shield.wav")
	statuses_changed.connect(_on_statuses_changed)
	
	# Define the initial deck
	var starting_deck_sides = [2, 4, 4, 6, 6, 6, 8, 8, 10]
	
	for side_count in starting_deck_sides:
		var new_die = Die.new(side_count)

		if MainGame.debug_mode:
			# Testing: Apply a random effect to every face
			for face in new_die.faces:
				var effect = EffectLibrary.get_random_effect_for_die(side_count, 3)
				if effect:
					print("Adding effect %s to D%d face value %d" % [effect.name, side_count, face.value])
					face.effects.append(effect)

		add_to_game_bag([new_die])
	print("added default dice bag of size: ", _game_dice_bag.size())

func _process(delta):
	# Manually position the status display relative to the player's global position,
	# since it's on a separate CanvasLayer.
	if is_instance_valid(status_display):
		status_display.global_position = global_position + Vector2(-50, -50)

func _draw_from_bag(count: int) -> Array[Die]:
	var drawn_dice: Array[Die] = []
	var is_shrunk = has_status(STATUS_SHRUNK)
	
	for i in range(count):
		if _round_dice_bag.size() == 0:
			shuffle_dice_discard_into_bag()
		
		if _round_dice_bag.size() > 0:
			var random_index = randi() % _round_dice_bag.size()
			var drawn_die = _round_dice_bag.pop_at(random_index)
			dice_bag_changed.emit(_round_dice_bag.size())
			
			drawn_dice.append(shrink_die(drawn_die) if is_shrunk else drawn_die)
	return drawn_dice

func draw_hand():
	return _draw_from_bag(dice_pool_size)

func draw_dice(count: int):
	var drawn_dice = _draw_from_bag(count)
	if not drawn_dice.is_empty():
		dice_drawn.emit(drawn_dice)

func discard(dice_to_discard: Array[Die]):
	var dice_to_actually_discard: Array[Die] = []
	for d in dice_to_discard:
		# If the die is a temporary shrunken version, discard its original instead.
		# The shrunken die object will be automatically freed as it's no longer referenced.
		var die_to_add = d
		while die_to_add.has_meta("original_die"):
			die_to_add = die_to_add.get_meta("original_die")
		dice_to_actually_discard.append(die_to_add)
	_dice_discard.append_array(dice_to_actually_discard)
	dice_discard_changed.emit(_dice_discard.size())

func shuffle_dice_discard_into_bag():
	add_to_round_bag(_dice_discard)
	
	_dice_discard.clear()
	dice_discard_changed.emit(_dice_discard.size())
	_round_dice_bag.shuffle()
	
func reset_for_new_round():
	_round_dice_bag = _game_dice_bag.duplicate()
	dice_bag_changed.emit(_round_dice_bag.size())
	
	_dice_discard.clear()
	dice_discard_changed.emit(_dice_discard.size())
	
	statuses.clear()
	_new_statuses_this_turn.clear()
	statuses_changed.emit(statuses)
	
func add_to_game_bag(dice_to_add: Array[Die]):
	_game_dice_bag.append_array(dice_to_add)

func add_to_round_bag(dice_to_add: Array[Die]):
	_round_dice_bag.append_array(dice_to_add)
	dice_bag_changed.emit(_round_dice_bag.size())

func add_block(amount: int):
	if amount > 0:
		# Play the shield sound if one is loaded.
		if audio_player and _shield_sound:
			audio_player.stream = _shield_sound
			audio_player.play()
	
	super.add_block(amount)

func add_gold(new_gold: int):
	print("gold changed: ", new_gold)
	gold += new_gold
	gold_changed.emit(gold)

func add_ability(new_ability: AbilityData):
	abilities.append(new_ability)
	abilities_changed.emit(new_ability)

func remove_ability(ability: AbilityData):
	if abilities.has(ability):
		abilities.erase(ability)

func hold_die(die_to_hold: Die):
	_held_dice.append(die_to_hold)

func get_and_clear_held_dice() -> Array[Die]:
	var dice_to_return: Array[Die] = []
	var is_shrunk = has_status(STATUS_SHRUNK)
	
	for held_die in _held_dice:
		if is_shrunk:
			# If we are shrunken, ensure the die is shrunken.
			var final_die = shrink_die(held_die)
			if final_die != held_die:
				var face_index = held_die.faces.find(held_die.result_face)
				if face_index != -1 and face_index < final_die.faces.size():
					final_die.result_face = final_die.faces[face_index]
					final_die.result_value = final_die.result_face.value
				else:
					final_die.roll()
			dice_to_return.append(final_die)
		else:
			# If we are NOT shrunken, ensure the die is normal.
			if held_die.has_meta("is_shrunken") and held_die.has_meta("original_die"):
				var original = held_die.get_meta("original_die")
				var face_index = held_die.faces.find(held_die.result_face)
				if face_index != -1 and face_index < original.faces.size():
					original.result_face = original.faces[face_index]
					original.result_value = original.result_face.value
				else:
					original.roll()
				dice_to_return.append(original)
			else:
				dice_to_return.append(held_die)
	
	_held_dice.clear()
	return dice_to_return

func shrink_die(original_die: Die) -> Die:
	if original_die.has_meta("is_shrunken"):
		return original_die

	if original_die.sides <= 2:
		return original_die

	var original_sides = original_die.sides
	var new_sides = max(2, original_sides - 2)
	if new_sides == original_sides:
		return original_die

	var shrunken_die = Die.new(new_sides)
	# Tag the new die with metadata so we can identify it later and revert it.
	shrunken_die.set_meta("is_shrunken", true)
	shrunken_die.set_meta("original_die", original_die)
	
	# Copy over the faces that still exist on the smaller die.
	for i in range(new_sides):
		# The original die's faces are indexed 0 to N-1, corresponding to values 1 to N.
		# We manually copy properties to ensure effects are preserved correctly.
		if i < original_die.faces.size():
			var original_face = original_die.faces[i]
			var new_face = shrunken_die.faces[i]
			
			new_face.value = original_face.value
			# Shallow copy the effects array to share the effect resources.
			new_face.effects = original_face.effects.duplicate()

	print("Shrunk a D%d to a D%d" % [original_sides, new_sides])
	return shrunken_die

func heal(amount: int):
	# Player's heal ability is less effective, healing for half the value.
	var old_hp = hp
	var old_block = block
	var heal_amount = ceili(amount / 2.0)
	hp = min(hp + heal_amount, max_hp)
	if health_bar.has_method("update_with_animation"):
		health_bar.update_with_animation(old_hp, hp, old_block, block, max_hp)
	else:
		update_health_display()
	print("%s healed for %d (raw) -> %d (actual), has %d HP left." % [name, amount, heal_amount, hp])

func _on_statuses_changed(current_statuses: Dictionary):
	if status_display:
		status_display.update_display(current_statuses)
