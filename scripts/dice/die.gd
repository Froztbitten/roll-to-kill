extends Resource
class_name Die

class DieFace extends Resource:
	@export var value: int = 1
	@export var effects: Array[DieFaceEffect]

@export var faces: Array[DieFace]

var sides: int:
	get:
		return faces.size()

var icon_path: String:
	get:
		if sides == 0: return ""
		return "res://assets/ai/dice/d%d.svg" % sides

var result_face: Die.DieFace = null
var result_value: int = 0

func _init(p_sides: int = 6):
	if faces.is_empty():
		for i in range(p_sides):
			var new_face = Die.DieFace.new()
			new_face.value = i + 1
			faces.append(new_face)

func roll(with_advantage: bool = false):
	if faces.is_empty():
		push_warning("Attempted to roll a die with no faces.")
		result_face = null
		result_value = 0
		return 0

	var roll1_face: Die.DieFace = faces.pick_random()
	
	if with_advantage:
		var roll2_face: Die.DieFace = faces.pick_random()
		result_face = roll1_face if roll1_face.value >= roll2_face.value else roll2_face
	else:
		result_face = roll1_face
	
	result_value = result_face.value
	return result_value

func get_face_values() -> Array[int]:
	var values: Array[int] = []
	for face in faces:
		values.append(face.value)
	return values
