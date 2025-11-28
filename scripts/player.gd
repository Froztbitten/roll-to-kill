extends Character
class_name Player

var deck: Array[Dice] = []
var dice: Array[Dice] = []
var discard_pile: Array[Dice] = []

func _ready():
	super._ready()
	
	# Define the initial deck
	var dice_resource = preload("res://scripts/dice.gd")
	
	deck.append(dice_resource.new(4))
	deck.append(dice_resource.new(6))
	deck.append(dice_resource.new(6))
	deck.append(dice_resource.new(6))
	deck.append(dice_resource.new(8))
	deck.append(dice_resource.new(8))
	deck.append(dice_resource.new(10))
	deck.append(dice_resource.new(12))
	deck.append(dice_resource.new(20))
	
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
