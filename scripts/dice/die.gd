extends Resource
class_name Dice

var rng = RandomNumberGenerator.new()

@export var sides: int = 6
@export var face_values: Array[int]

var result_face: int = -1 # The index of the face that was rolled
var result_value: int = 0  # The value of the face that was rolled

func _init():
	# This function must be parameterless for the resource loader to work.
	# We keep it empty to ensure stable resource loading.
	pass

func roll():
	if not face_values.is_empty():
		# If custom faces are defined, pick one at random.
		result_face = rng.randi_range(0, face_values.size() - 1)
		result_value = face_values[result_face]
		return result_value
	else:
		# Otherwise, perform a standard roll based on the number of sides.
		result_value = rng.randi_range(1, sides)
		# For a standard die, the face index can be considered value - 1
		result_face = result_value - 1
		return result_value

func get_icon_path() -> String:
	match sides:
		4:
			return "res://assets/d4.svg"
		6:
			return "res://assets/d6.svg"
		8:
			return "res://assets/d8.svg"
		10:
			return "res://assets/d10.svg"
		12:
			return "res://assets/d12.svg"
		20:
			return "res://assets/d20.svg"
	return "" # Return an empty string for unknown dice types
