extends Resource
class_name Die

class DieFace extends Resource:
	@export var value: int = 1
	@export var effects: Array[DieFaceEffect]

@export var sides: int = 6:
	set(value):
		sides = value
		_update_faces()

@export var faces: Array[DieFace]:
	set(value):
		faces = value
		if faces:
			sides = faces.size()

var icon_path: String:
	get:
		if sides == 0: return ""
		return "res://assets/ai/dice/d%d.svg" % sides

var result_face: DieFace = null
var result_value: int = 0

func _init(p_sides: int = 6):
	sides = p_sides
	_update_faces()

func _update_faces():
	if faces == null:
		faces = []
	
	var current_size = faces.size()
	if current_size == sides:
		return
		
	if sides < current_size:
		faces.resize(sides)
	else:
		for i in range(current_size, sides):
			var new_face = DieFace.new()
			new_face.value = i + 1
			faces.append(new_face)

func roll(with_advantage: bool = false):
	if faces.is_empty():
		push_warning("Attempted to roll a die with no faces.")
		result_face = null
		result_value = 0
		return 0

	var roll1_face: DieFace = faces.pick_random()
	
	if with_advantage:
		var roll2_face: DieFace = faces.pick_random()
		result_face = roll1_face if roll1_face.value >= roll2_face.value else roll2_face
	else:
		result_face = roll1_face
	
	result_value = result_face.value
	return result_value

func flip_die():
	if faces.size() < 2:
		push_warning("Attempted to flip a die with less than 2 faces.")
		return
	
	var current_index = faces.find(result_face)
	var new_index = (faces.size() - 1) - current_index
	result_face = faces[new_index]
	result_value = result_face.value

func get_face_values() -> Array[int]:
	var values: Array[int] = []
	for face in faces:
		values.append(face.value)
	return values
