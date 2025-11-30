extends Resource
class_name Dice

var rng = RandomNumberGenerator.new()

@export var sides: int = 6
@export var face_values: Array[int]

func _init():
	# This function must be parameterless for the resource loader to work.
	# We keep it empty to ensure stable resource loading.
	pass

func roll():
	if not face_values.is_empty():
		# If custom faces are defined, pick one at random.
		return face_values.pick_random()
	else:
		# Otherwise, perform a standard roll based on the number of sides.
		return rng.randi_range(1, sides)

func get_icon_path() -> String:
	match sides:
		4:
			return "res://icons/d4.svg"
		6:
			return "res://icons/d6.svg"
		8:
			return "res://icons/d8.svg"
		10:
			return "res://icons/d10.svg"
		12:
			return "res://icons/d12.svg"
		20:
			return "res://icons/d20.svg"
	return "" # Return an empty string for unknown dice types
