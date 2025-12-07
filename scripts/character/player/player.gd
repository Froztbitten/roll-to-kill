extends Character
class_name Player

signal dice_bag_changed(new_amount)
signal dice_discard_changed(new_amount)
signal gold_changed(new_amount)
signal abilities_changed(new_ability)

@export var abilities: Array[AbilityData] = []

var _game_dice_bag: Array[Die] = []
var _round_dice_bag: Array[Die] = []
var _dice_discard: Array[Die] = []
var gold: int = 0

var dice_pool_size = 4


func _ready():
	super._ready()
	
	# Define the initial deck
	var starting_deck_sides = [2, 4, 4, 6, 6, 6, 8, 8, 10]
	
	for side_count in starting_deck_sides:
		var new_die = Die.new(side_count)
		new_die.sides = side_count
		add_to_game_bag([new_die])
	print("added default dice bag of size: ", _game_dice_bag.size())

func draw_hand():
	var drawn_dice: Array[Die] = []
	for i in range(dice_pool_size):
		if _round_dice_bag.size() == 0:
			shuffle_dice_discard_into_bag()
		
		if _round_dice_bag.size() > 0:
			var random_index = randi() % _round_dice_bag.size()
			var drawn_die = _round_dice_bag.pop_at(random_index)
			dice_bag_changed.emit(_round_dice_bag.size())
			drawn_dice.append(drawn_die)
	return drawn_dice

func discard(dice_to_discard: Array[Die]):
	_dice_discard.append_array(dice_to_discard)
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
	
func add_to_game_bag(dice_to_add: Array[Die]):
	_game_dice_bag.append_array(dice_to_add)

func add_to_round_bag(dice_to_add: Array[Die]):
	_round_dice_bag.append_array(dice_to_add)
	dice_bag_changed.emit(_round_dice_bag.size())

func add_gold(new_gold: int):
	print("gold changed: ", new_gold)
	gold += new_gold
	gold_changed.emit(gold)

func add_ability(new_ability: AbilityData):
	abilities.append(new_ability)
	abilities_changed.emit(new_ability)
