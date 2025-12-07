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

func roll(with_advantage: bool = false):
	var roll1_face = randi_range(0, face_values.size() - 1)
	var roll1_value = face_values[roll1_face]
	
	if with_advantage:
		var roll2_face = randi_range(0, face_values.size() - 1)
		var roll2_value = face_values[roll2_face]
		result_value = max(roll1_value, roll2_value)
		result_face = roll1_face if roll1_value >= roll2_value else roll2_face
	else:
		result_face = roll1_face
		result_value = roll1_value
	return result_value
