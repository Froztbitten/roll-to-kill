extends Control
class_name TutorialOverlay

signal tutorial_finished
signal next_step

@onready var label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/Label
@onready var next_button: Button = $PanelContainer/MarginContainer/VBoxContainer/NextButton
@onready var panel: PanelContainer = $PanelContainer

# Dimmer Rects
@onready var top_rect: ColorRect = $Dimmer/Top
@onready var bottom_rect: ColorRect = $Dimmer/Bottom
@onready var left_rect: ColorRect = $Dimmer/Left
@onready var right_rect: ColorRect = $Dimmer/Right

var current_tween: Tween
var current_highlight_node: Control = null

func _ready():
	next_button.pressed.connect(func(): next_step.emit())
	# Start fully transparent and invisible to prevent capturing input
	modulate = Color(1, 1, 1, 0)
	visible = false

func _process(_delta):
	if visible and is_instance_valid(current_highlight_node) and current_highlight_node.is_inside_tree():
		_update_layout()

func show_message(text: String, highlight_node: Control = null, show_button: bool = true):
	current_highlight_node = highlight_node
	# Fade in the whole overlay
	if current_tween and current_tween.is_running():
		current_tween.kill()
	current_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	visible = true
	current_tween.tween_property(self, "modulate:a", 1.0, 0.3)

	label.text = text
	next_button.visible = show_button
	
	# If interaction is required (no button), let clicks pass through the panel
	if not show_button:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	_update_layout()

func _update_layout():
	if is_instance_valid(current_highlight_node) and current_highlight_node.is_inside_tree():
		_highlight(current_highlight_node)
		
		var highlight_rect = current_highlight_node.get_global_rect()
		var viewport_rect = get_viewport_rect()
		var panel_size = panel.size
		if panel_size == Vector2.ZERO:
			panel_size = Vector2(400, 150) # Estimate
		
		# Default: Center horizontally
		var target_x = highlight_rect.position.x + (highlight_rect.size.x - panel_size.x) / 2.0
		
		# Try to place below the highlight
		var target_y = highlight_rect.end.y + 20
		
		# If placing below goes off-screen, try other positions
		if target_y + panel_size.y > viewport_rect.size.y - 20:
			# Try Above
			var above_y = highlight_rect.position.y - panel_size.y - 20
			if above_y >= 20:
				target_y = above_y
			else:
				# Vertical doesn't fit. Try Horizontal (Right then Left).
				var center_y = highlight_rect.position.y + (highlight_rect.size.y - panel_size.y) / 2.0
				
				# Try Right
				var right_x = highlight_rect.end.x + 20
				if right_x + panel_size.x <= viewport_rect.size.x - 20:
					target_x = right_x
					target_y = center_y
				else:
					# Try Left
					var left_x = highlight_rect.position.x - panel_size.x - 20
					if left_x >= 20:
						target_x = left_x
						target_y = center_y
					else:
						# Fallback: Center on highlight (overlap)
						target_y = center_y
		
		# Final Clamp to ensure it stays on screen (Priority: Keep UI visible)
		target_x = clamp(target_x, 20, viewport_rect.size.x - panel_size.x - 20)
		target_y = clamp(target_y, 20, viewport_rect.size.y - panel_size.y - 20)
		
		panel.global_position = Vector2(target_x, target_y)
	else:
		_reset_dimmer()
		panel.set_anchors_preset(Control.PRESET_CENTER)

func hide_and_finish():
	if current_tween and current_tween.is_running():
		current_tween.kill()
	current_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	current_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await current_tween.finished
	visible = false
	emit_signal("tutorial_finished")

func _highlight(node: Control):
	var rect = node.get_global_rect()
	var viewport_size = get_viewport_rect().size
	
	# Top
	top_rect.position = Vector2.ZERO
	top_rect.size = Vector2(viewport_size.x, rect.position.y)
	
	# Bottom
	bottom_rect.position = Vector2(0, rect.end.y)
	bottom_rect.size = Vector2(viewport_size.x, viewport_size.y - rect.end.y)
	
	# Left
	left_rect.position = Vector2(0, rect.position.y)
	left_rect.size = Vector2(rect.position.x, rect.size.y)
	
	# Right
	right_rect.position = Vector2(rect.end.x, rect.position.y)
	right_rect.size = Vector2(viewport_size.x - rect.end.x, rect.size.y)
	
	top_rect.visible = true
	bottom_rect.visible = true
	left_rect.visible = true
	right_rect.visible = true

func _reset_dimmer():
	top_rect.visible = false
	bottom_rect.visible = false
	left_rect.visible = false
	right_rect.visible = false
	# Make one full screen dimmer if needed, or just hide all
	# For now, let's just use top rect as full dimmer if no highlight
	top_rect.position = Vector2.ZERO
	top_rect.size = get_viewport_rect().size
	top_rect.visible = true
