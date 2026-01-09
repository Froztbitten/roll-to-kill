extends Button
class_name TriangleButton

var triangle_size: float = 100.0
var points_up: bool = true

func _ready():
	flat = true
	focus_mode = Control.FOCUS_NONE
	# Make the button's own background/border invisible, but keep children (Polygon2D) visible.
	self_modulate = Color(1, 1, 1, 0)

func _has_point(point: Vector2) -> bool:
	var half_width = triangle_size / 2.0
	var height = triangle_size * sqrt(3) / 2.0
	var center = size / 2.0
	
	var v1: Vector2
	var v2: Vector2
	var v3: Vector2
	
	if points_up:
		v1 = center + Vector2(0, -2.0 / 3.0 * height)
		v2 = center + Vector2(half_width, 1.0 / 3.0 * height)
		v3 = center + Vector2(-half_width, 1.0 / 3.0 * height)
	else:
		v1 = center + Vector2(0, 2.0 / 3.0 * height)
		v2 = center + Vector2(-half_width, -1.0 / 3.0 * height)
		v3 = center + Vector2(half_width, -1.0 / 3.0 * height)
		
	return Geometry2D.is_point_in_polygon(point, [v1, v2, v3])