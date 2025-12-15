extends Control
class_name DieDisplay

signal die_clicked(die_display)
signal die_value_changed
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

var dice_pool = null

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
	if die.result_face and not die.result_face.effects.is_empty():
		var effect: DieFaceEffect = die.result_face.effects[0]
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

	for face in die.faces:
		var cell = DieGridCell.instantiate()
		var label = cell.get_node("Label")
		label.text = str(face.value)
		
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
		if not face.effects.is_empty():
			var effect: DieFaceEffect = face.effects[0]
			var effect_style = default_style.duplicate() as StyleBoxFlat
			effect_style.bg_color = effect.highlight_color
			cell.add_theme_stylebox_override("panel", effect_style)

		# Highlight the rolled face
		if face == die.result_face:
			# Create a unique stylebox to highlight the rolled face
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.9, 0.7, 0.2, 0.5) # Translucent gold
			style.border_width_left = 1
			style.border_width_top = 1 
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color.BLACK
			cell.add_theme_stylebox_override("panel", style) # Overwrite the default style

		grid_container.add_child(cell)

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
	if die and die.result_face and not die.result_face.effects.is_empty():
		var effect: DieFaceEffect = die.result_face.effects[0]
		if not effect.description.is_empty():
			var description_text = effect.description
			# Replace placeholders with actual calculated values.
			description_text = description_text.replace("{value}", str(die.result_value))
			description_text = description_text.replace("{value / 2}", str(ceili(die.result_value / 2.0)))
			
			tooltip_label.text = description_text
			
			# Position the tooltip to the right of the die display.
			effect_tooltip.global_position = global_position + Vector2(size.x + 5, 0)
			effect_tooltip.visible = true

func _on_mouse_entered():
	face_grid.visible = true
	if not effect_name_label.text.is_empty():
		effect_name_label.visible = true
	hover_timer.start()

func _on_mouse_exited():
	face_grid.visible = false
	effect_name_label.visible = false
	hover_timer.stop()
	effect_tooltip.visible = false

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			# When clicked, emit a signal with a reference to itself
			emit_signal("die_clicked", self)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			if die and die.result_face and not die.result_face.effects.is_empty():
				for effect in die.result_face.effects:
					if effect.process_effect == EffectLogic.wormhole:
						var context = {"die": die}
						EffectLogic.wormhole(0, null, null, context)
						update_display()
						emit_signal("die_value_changed")
						get_viewport().set_input_as_handled()
						return # Effect triggered, stop processing.

func _notification(what):
	if what == NOTIFICATION_MOUSE_ENTER:
		face_grid.visible = true
		if not effect_name_label.text.is_empty():
			effect_name_label.visible = true
		hover_timer.start()
	elif what == NOTIFICATION_MOUSE_EXIT:
		face_grid.visible = false
		effect_name_label.visible = false
		hover_timer.stop()
		effect_tooltip.visible = false
	elif what == NOTIFICATION_DRAG_END:
		# If the drag ended and this die display was not successfully dropped
		# (i.e., it was not reparented), make it visible again.
		if get_parent() == dice_pool:
			main_display.visible = true

# Called when a drag is initiated on this control.
func _get_drag_data(at_position: Vector2):
	# A die can only be dragged from the dice pool, not from an ability slot.
	if not get_parent() is DicePool:
		return null

	# Let the main game know that a drag has started, so it can be deselected.
	emit_signal("drag_started", self)

	# Create a preview that follows the mouse
	var preview = self.duplicate() # Duplicate the entire control for the preview
	preview.scale = Vector2(0.8, 0.8)
	set_drag_preview(preview)

	# The data payload that will be sent to the drop target
	var payload = {
		"source_display": self,
		"die_data": die
	}
	
	# Hide the original die while it's being dragged
	main_display.visible = false
	
	return payload
