extends Control
class_name DieDisplay

signal die_clicked(die_display)
signal die_value_changed(die_display)
signal drag_started(die_display)

const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

var die: Die:
	set = set_die

@onready var main_display: PanelContainer = $MainDisplay
@onready var icon_texture: TextureRect = $MainDisplay/Icon
@onready var roll_label: Label = $MainDisplay/LabelContainer/RollLabel
@onready var face_grid: PanelContainer = $FaceGrid
@onready var effect_name_label: Label = $EffectNameLabel
@onready var grid_container: GridContainer = $FaceGrid/Grid
@onready var effect_tooltip: PanelContainer = $EffectTooltip
@onready var tooltip_label: RichTextLabel = $EffectTooltip/DescriptionLabel
@onready var hover_timer: Timer = $HoverTimer
var tooltip_tween: Tween

var dice_pool = null
var player: Player = null
var current_scale_factor: float = 1.0

func _ready():
	# To prevent all dice from sharing the same glow state, we need to make
	# sure each die instance has its own unique material resource.
	# Duplicating the material ensures that changes to one die's shader
	# parameters don't affect any others.
	if icon_texture.material:
		icon_texture.material = icon_texture.material.duplicate()
	# Make the tooltip render on top of other UI elements and ensure it's hidden at start.
	effect_tooltip.set_as_top_level(true)
	effect_tooltip.visible = false
	hover_timer.timeout.connect(_on_hover_timer_timeout)
	resized.connect(_on_resized)
	face_grid.z_index = 100
	face_grid.set_as_top_level(true)
	face_grid.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_process(false)

func set_die(value: Die):
	die = value
	if is_node_ready():
		update_display()

func update_display():
	if not die:
		return

	# --- 1. Update the default display (Icon and RollLabel) ---
	roll_label.text = str(die.result_value)
	icon_texture.texture = load(die.icon_path)
	effect_name_label.visible = false # Hide by default
	effect_name_label.text = ""

	# --- Shader Glow Effect Logic ---
	# By default, turn off the glow by setting its intensity to 0.
	icon_texture.material.set_shader_parameter("glow_intensity", 0.0)
	# If the rolled face has an effect, turn on the glow and set its color.
	if die.effect:
		var effect: DieFaceEffect = die.effect
		icon_texture.material.set_shader_parameter("glow_color", effect.highlight_color)
		icon_texture.material.set_shader_parameter("glow_intensity", 4.0) # Use the shader's default intensity.
		effect_name_label.text = effect.name

	# --- 2. Populate the hidden hover grid ---
	# Clear previous grid contents
	for child in grid_container.get_children():
		child.queue_free()
	
	# Set separation to -1 so that 1px borders on adjacent cells overlap perfectly
	# This creates a "shared border" look for the grid.
	grid_container.add_theme_constant_override("h_separation", -1)
	grid_container.add_theme_constant_override("v_separation", -1)

	# Set grid columns for a nice layout, similar to the reward screen
	match die.sides:
		4: grid_container.columns = 2
		6: grid_container.columns = 3
		8: grid_container.columns = 4
		10: grid_container.columns = 5
		12: grid_container.columns = 4
		20: grid_container.columns = 5
		_: grid_container.columns = 4

	var cell_base_size = 20.0

	for face in die.faces:
		var cell = DieGridCell.instantiate()
		cell.custom_minimum_size = Vector2(cell_base_size, cell_base_size)
		var label = cell.get_node("Label")
		label.text = str(face.value)
		label.add_theme_font_size_override("font_size", 14)
		
		# Add a black outline to the grid cell labels for readability
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		
		# Default style for non-highlighted cells
		var default_style = StyleBoxFlat.new()
		default_style.bg_color = Color(0.2, 0.2, 0.2, 0.8) # Dark, slightly transparent
		default_style.border_width_left = 1
		default_style.border_width_top = 1
		default_style.border_width_right = 1
		default_style.border_width_bottom = 1
		default_style.border_color = Color.BLACK
		cell.add_theme_stylebox_override("panel", default_style)
		
		# If the face has an effect, give it a special highlight
		if die.effect:
			var effect: DieFaceEffect = die.effect
			var effect_style = default_style.duplicate() as StyleBoxFlat
			effect_style.bg_color = effect.highlight_color
			cell.add_theme_stylebox_override("panel", effect_style)

		# Highlight the rolled face
		if face == die.result_face:
			# Modify the existing stylebox to highlight the border instead of replacing the background.
			var style = cell.get_theme_stylebox("panel")
			style.border_color = Color.GOLD
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3

		grid_container.add_child(cell)
	
	if face_grid.visible:
		_update_face_grid_position()

func select(animated: bool = true):
	# Visually indicate that the die is selected (e.g., make it brighter)
	main_display.pivot_offset = main_display.size / 2
	main_display.modulate = Color(1.8, 1.8, 1.8)
	if animated:
		var tween = create_tween().set_trans(Tween.TRANS_SINE)
		tween.tween_property(main_display, "scale", Vector2(1.15, 1.15), 0.1)
	else:
		main_display.scale = Vector2(1.15, 1.15)

func deselect(animated: bool = true):
	# Return to normal appearance
	main_display.pivot_offset = main_display.size / 2
	main_display.modulate = Color(1, 1, 1)
	if animated:
		var tween = create_tween().set_trans(Tween.TRANS_SINE)
		tween.tween_property(main_display, "scale", Vector2(1.0, 1.0), 0.1)
	else:
		main_display.scale = Vector2(1.0, 1.0)

func _on_hover_timer_timeout():
	# This function is called after the hover delay.
	# Check if the rolled face has an effect and a description.
	if not is_inside_tree(): return
	if die and die.effect:
		var effect: DieFaceEffect = die.effect
		if not effect.description.is_empty():
			var description_text = effect.description
			# Replace placeholders with actual calculated values.
			description_text = description_text.replace("{value}", str(die.result_value))
			description_text = description_text.replace("{value / 2}", str(ceili(die.result_value / 2.0)))
			
			tooltip_label.text = description_text

			# Wait a frame for the label to resize with the new text.
			await get_tree().process_frame

			# Position the tooltip to the right of the die display.
			var tooltip_pos = global_position + Vector2(size.x + 5, 0)
			var viewport_rect = get_viewport().get_visible_rect()
			if tooltip_pos.x + effect_tooltip.size.x > viewport_rect.end.x:
				tooltip_pos.x = global_position.x - effect_tooltip.size.x - 5
			
			effect_tooltip.global_position = tooltip_pos
			
			if tooltip_tween and tooltip_tween.is_running():
				tooltip_tween.kill()
			tooltip_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			effect_tooltip.modulate.a = 0.0
			effect_tooltip.visible = true
			tooltip_tween.tween_property(effect_tooltip, "modulate:a", 1.0, 0.2)

func _on_mouse_entered(): pass # Deprecated, handled by _notification
func _on_mouse_exited(): pass # Deprecated, handled by _notification

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			# When clicked, emit a signal with a reference to itself
			emit_signal("die_clicked", self)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			if die and die.effect:
				var effect = die.effect
				if effect.process_effect == EffectLogic.wormhole:
					var context = {"die": die}
					EffectLogic.wormhole(0, player, null, context)
					update_display()
					emit_signal("die_value_changed", self)
					get_viewport().set_input_as_handled()
					return # Effect triggered, stop processing.

func _notification(what):
	if what == NOTIFICATION_MOUSE_ENTER:
		_update_face_grid_position()
		face_grid.visible = true
		if not effect_name_label.text.is_empty():
			effect_name_label.visible = true
		hover_timer.start()
		set_process(true)
	elif what == NOTIFICATION_MOUSE_EXIT:
		face_grid.visible = false
		effect_name_label.visible = false
		hover_timer.stop()
		if tooltip_tween and tooltip_tween.is_running():
			tooltip_tween.kill()
		if effect_tooltip.visible:
			tooltip_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
			tooltip_tween.tween_property(effect_tooltip, "modulate:a", 0.0, 0.1)
			tooltip_tween.tween_callback(func(): if is_instance_valid(effect_tooltip): effect_tooltip.visible = false)
		set_process(false)
	elif what == NOTIFICATION_DRAG_END:
		# If the drag ended and this die display was not successfully dropped
		# (i.e., it was not reparented), make it visible again.
		if get_parent() == dice_pool:
			main_display.visible = true

# Called when a drag is initiated on this control.
func _get_drag_data(_at_position: Vector2):
	# A die can only be dragged from the dice pool, not from an ability slot.
	if not get_parent() is DicePool:
		return null

	# Let the main game know that a drag has started, so it can be deselected.
	emit_signal("drag_started", self)

	# Create a container for the preview that will be managed by Godot's drag system
	var preview_container = Control.new()
	# Attach a script to sync the visual's position (since it's in a CanvasLayer)
	var script = GDScript.new()
	script.source_code = "extends Control\nvar visual_node: Control\nfunc _ready():\n\tif get_child_count() > 0:\n\t\tvar cl = get_child(0)\n\t\tif cl is CanvasLayer and cl.get_child_count() > 0:\n\t\t\tvisual_node = cl.get_child(0)\nfunc _process(_delta):\n\tif visual_node:\n\t\tvisual_node.global_position = global_position - (visual_node.size * visual_node.scale) / 2.0\n"
	script.reload()
	preview_container.set_script(script)
	
	# Create a CanvasLayer to render the preview above the UI (Layer 20)
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	preview_container.add_child(canvas_layer)

	# Create the actual visual preview
	var preview = self.duplicate()
	preview.scale = Vector2(0.8, 0.8)
	preview.get_node("FaceGrid").visible = false
	canvas_layer.add_child(preview)
	
	set_drag_preview(preview_container)

	# The data payload that will be sent to the drop target
	var payload = {
		"source_display": self,
		"die_data": die
	}
	
	# Hide the original die while it's being dragged
	main_display.visible = false
	face_grid.visible = false
	
	return payload

func _clean_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(text, "", true)

func _update_face_grid_position():
	face_grid.scale = Vector2.ONE
	face_grid.pivot_offset = Vector2.ZERO
	
	# Separation should be fixed at -1 because borders are fixed at 1px (StyleBoxFlat borders don't scale)
	grid_container.add_theme_constant_override("h_separation", -1)
	grid_container.add_theme_constant_override("v_separation", -1)
	
	var cell_base_size = 20.0
	var scaled_cell_size = cell_base_size * current_scale_factor
	
	for cell in grid_container.get_children():
		cell.custom_minimum_size = Vector2(scaled_cell_size, scaled_cell_size)
		var label = cell.get_node("Label")
		if label:
			label.add_theme_font_size_override("font_size", int(14 * current_scale_factor))

	# Reset container min sizes to allow shrinking
	grid_container.custom_minimum_size = Vector2.ZERO
	grid_container.size = Vector2.ZERO
	face_grid.custom_minimum_size = Vector2.ZERO
	
	# Ensure the grid has the correct size based on its content
	face_grid.size = Vector2.ZERO
	var target_size = face_grid.get_minimum_size()
	face_grid.size = target_size
	
	# Calculate position relative to the die
	# Use the icon texture's global rect to ensure we are positioning relative to the visual die,
	# not the container which might be larger (e.g. due to layout stretching).
	var visual_rect = icon_texture.get_global_rect()
	var die_top_center = Vector2(visual_rect.position.x + visual_rect.size.x / 2.0, visual_rect.position.y)
	
	var gap = 10.0 * current_scale_factor
	
	# For dice in the pool, we want the grid to sit tight against the die visual.
	if dice_pool != null:
		gap = 0.0
	
	var grid_pos_x = die_top_center.x - (target_size.x / 2.0)
	var grid_pos_y = die_top_center.y - gap - target_size.y
	
	face_grid.global_position = Vector2(grid_pos_x, grid_pos_y)

func update_scale(factor: float):
	current_scale_factor = factor
	var base_size = 50.0
	custom_minimum_size = Vector2(base_size, base_size) * factor
	if face_grid.visible:
		_update_face_grid_position()

func _on_resized():
	if face_grid.visible:
		_update_face_grid_position()

func _process(_delta):
	if face_grid.visible:
		_update_face_grid_position()
