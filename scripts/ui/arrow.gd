extends Line2D

var source_node = null
var target_node = null

func _ready():
	set_as_top_level(true)
	set_width(5)
	set_default_color(Color("DEB887"))
	add_to_group("arrows")

func _process(delta):
	if source_node and is_instance_valid(source_node):
		if target_node and is_instance_valid(target_node):
			# Locked arrow, update position based on nodes
			global_position = Vector2.ZERO # Reset position since we use global coords
			clear_points()
			add_point(source_node.global_position)
			add_point(target_node.global_position)
		else:
			# Dragging arrow (no target yet)
			global_position = Vector2.ZERO
			clear_points()
			add_point(source_node.global_position)
			add_point(get_global_mouse_position())
	else:
		# No source, clear itself
		clear_points()


func set_source(node):
	source_node = node

func set_target(node):
	target_node = node
