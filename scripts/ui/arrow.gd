extends Line2D

var source_node = null
var target_node = null

@onready var arrow_head: Polygon2D = $ArrowHead

func _ready():
	set_as_top_level(true)
	set_width(5)
	set_default_color(Color("DEB887"))
	if arrow_head:
		arrow_head.color = default_color
	add_to_group("arrows")

func _process(_delta):
	if source_node and is_instance_valid(source_node):
		var start_pos = source_node.global_position
		var end_pos = Vector2.ZERO
		
		if target_node and is_instance_valid(target_node):
			# Locked arrow, update position based on nodes
			end_pos = target_node.global_position
		else:
			# Dragging arrow (no target yet)
			end_pos = get_global_mouse_position()
			
		global_position = Vector2.ZERO # Reset position since we use global coords
		clear_points()
		add_point(start_pos)
		add_point(end_pos)
		
		if arrow_head:
			arrow_head.position = end_pos
			arrow_head.rotation = (end_pos - start_pos).angle()
			arrow_head.visible = true
	else:
		# No source, clear itself
		clear_points()
		if arrow_head:
			arrow_head.visible = false


func set_source(node):
	source_node = node

func set_target(node):
	target_node = node
