extends Character
class_name Player

var deck: Array[Dice] = []
var dice: Array[Dice] = []
var discard_pile: Array[Dice] = []

func _ready():
	super._ready()
	
	# Define the initial deck
	var starting_deck_sides = [4, 6, 6, 6, 8, 8, 10, 12, 20]
	
	for side_count in starting_deck_sides:
		var new_die = Dice.new()
		new_die.sides = side_count
		deck.append(new_die)
	
	initialize()

func initialize():
	dice = deck.duplicate(true)
	discard_pile.clear()
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

func shuffle_discard_pile_into_deck():
	dice.append_array(discard_pile)
	discard_pile.clear()
	dice.shuffle()
