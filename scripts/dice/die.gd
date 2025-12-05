extends Resource
class_name Die

@export var sides: int = 6:
	set(new_sides):
		sides = new_sides
		
		icon_path = "res://assets/ai/dice/d%d.svg" % sides
		
		face_values.clear()
		for i in range(sides):
			face_values.append(i + 1)

@export var face_values: Array[int] = []

var icon_path: String
var result_face: int = -1
var result_value: int = 0

func _init(pSides: int = 6):
	sides = pSides

func roll():
	result_face = randi_range(0, face_values.size() - 1)
	result_value = face_values[result_face]
	return result_value
