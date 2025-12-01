extends Character
class_name Player

signal gold_changed(new_amount)

var dice: Array[Dice] = []
var discard_pile: Array[Dice] = []
var gold: int = 0

func _ready():
	super._ready()
	
	# Define the initial deck
	var starting_deck_sides = [4, 6, 6, 6, 8, 8, 10, 12, 20]
	
	for side_count in starting_deck_sides:
		var new_die = Dice.new()
		new_die.sides = side_count
		dice.append(new_die)
	
	dice.shuffle()

func draw_hand():
	var drawn_dice: Array[Dice] = []
	for i in range(3):
		if dice.size() == 0:
			shuffle_discard_pile_into_deck()
		
		if dice.size() > 0:
			var random_index = randi() % dice.size()
			var drawn_die = dice.pop_at(random_index)
			drawn_dice.append(drawn_die)
	return drawn_dice

func discard(dice: Array[Dice]):
	discard_pile.append_array(dice)

func shuffle_discard_pile_into_deck():
	dice.append_array(discard_pile)
	discard_pile.clear()
	dice.shuffle()

func add_die(new_die: Dice):
	dice.append(new_die)

func add_gold(new_gold: int):
	print("gold changed: ", new_gold)
	gold += new_gold
	gold_changed.emit(gold)
