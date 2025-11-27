extends Resource
class_name Dice

@export var sides: int = 6
var icon_path: String

func _init(s = 6):
	sides = s
	match s:
		6:
			icon_path = "res://icons/d6.svg"
		8:
			icon_path = "res://icons/d8.svg"
		10:
			icon_path = "res://icons/d10.svg"

func roll():
	return randi_range(1, sides)
