extends Character
class_name Player

signal dice_bag_changed(new_amount)
signal dice_discard_changed(new_amount)
signal gold_changed(new_amount)
signal total_dice_count_changed(new_amount)
signal abilities_changed(new_ability)
signal dice_drawn(drawn_dice)

@export var abilities: Array[AbilityData] = []

var _game_dice_bag: Array[Die] = []
var _round_dice_bag: Array[Die] = []
var _dice_discard: Array[Die] = []
var _held_dice: Array[Die] = []
var gold: int = 50
var die_removal_cost: int = 50
var _shield_sound: AudioStream
var current_attack_dice_count: int = 1
@onready var status_display: HBoxContainer = $Visuals/InfoContainer/StatusEffectDisplay
@onready var info_container: VBoxContainer = $Visuals/InfoContainer

var dice_pool_size = 4


func _ready():
	super._ready()
	add_to_group("player")
	_shield_sound = load("res://assets/ai/sounds/shield.wav")
	statuses_changed.connect(_on_statuses_changed)
	info_container.resized.connect(_on_info_container_resized)
	_on_info_container_resized()
	
	# Define the initial deck
	var starting_deck_sides = [4, 4, 6, 6, 6, 8, 8, 10, 12]
	
	# Avoid cyclic dependency by loading MainGame script dynamically
	var main_game_script = load("res://scripts/main.gd")
	var is_debug = main_game_script and main_game_script.debug_mode
	
	for side_count in starting_deck_sides:
		var new_die = Die.new(side_count)

		if is_debug:
			# Testing: Apply a random effect to every face
			var effect = EffectLibrary.get_random_effect_for_die(side_count, 3)
			if effect:
				print("Adding effect %s to D%d" % [effect.name, side_count])
				new_die.effect = effect

		add_to_game_bag([new_die])
	print("added default dice bag of size: ", _game_dice_bag.size())
	total_dice_count_changed.emit(_game_dice_bag.size())

func _process(_delta):
	pass

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
	current_attack_dice_count = 1
	
	var preserved_statuses = {}
	for status in statuses:
		if status.status_name == STATUS_DECAYED:
			preserved_statuses[status] = statuses[status]
	
	statuses = preserved_statuses
	_new_statuses_this_turn.clear()
	statuses_changed.emit(statuses)
	
func add_to_game_bag(dice_to_add: Array[Die]):
	_game_dice_bag.append_array(dice_to_add)
	total_dice_count_changed.emit(_game_dice_bag.size())

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
	shrunken_die.effect = original_die.effect
	
	# Copy over the faces that still exist on the smaller die.
	for i in range(new_sides):
		# The original die's faces are indexed 0 to N-1, corresponding to values 1 to N.
		# We manually copy properties to ensure effects are preserved correctly.
		if i < original_die.faces.size():
			var original_face = original_die.faces[i]
			var new_face = shrunken_die.faces[i]
			
			new_face.value = original_face.value

	print("Shrunk a D%d to a D%d" % [original_sides, new_sides])
	return shrunken_die

func heal(amount: int):
	# Player's heal ability is less effective, healing for half the value.
	var heal_amount = ceili(amount / 2.0)
	print("%s healing effectiveness reduced: %d -> %d" % [name, amount, heal_amount])
	super.heal(heal_amount)

func _on_statuses_changed(current_statuses: Dictionary):
	if status_display:
		status_display.update_display(current_statuses)

func _on_info_container_resized():
	# Player sprite is centered at (0, -20), height 128 (half 64). Bottom is at 44.
	# Place info container below the sprite
	info_container.position.x = -(info_container.size.x / 2.0)
	info_container.position.y = 44.0 + 10.0 # Bottom + Padding

func die() -> void:
	if _is_dead: return
	await super.die()
	
	var main_game_script = load("res://scripts/main.gd")
	var is_debug = main_game_script and main_game_script.debug_mode
	
	if _is_dead and not is_debug:
		var defeat_screen = get_node_or_null("../UI/DefeatScreen")
		if defeat_screen:
			defeat_screen.visible = true

func remove_die_from_bag(die_to_remove: Die):
	if _game_dice_bag.has(die_to_remove):
		_game_dice_bag.erase(die_to_remove)
		# Also remove from round bag if present
		if _round_dice_bag.has(die_to_remove):
			_round_dice_bag.erase(die_to_remove)
		dice_bag_changed.emit(_round_dice_bag.size())
		total_dice_count_changed.emit(_game_dice_bag.size())

func upgrade_die(die_to_upgrade: Die):
	# Update metadata to track upgrade count
	var current_upgrades = die_to_upgrade.get_meta("upgrade_count", 0)
	die_to_upgrade.set_meta("upgrade_count", current_upgrades + 1)

func apply_effect_to_random_dice(effect: DieFaceEffect, count: int = 3):
	# Pick random dice from game bag
	var candidates = _game_dice_bag.duplicate()
	candidates.shuffle()
	
	for i in range(min(count, candidates.size())):
		var die_candidate = candidates[i]
		die_candidate.effect = effect
