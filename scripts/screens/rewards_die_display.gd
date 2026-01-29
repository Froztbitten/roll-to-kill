extends Button
class_name RewardsDieDisplay

signal die_hovered(die_display)

@onready var die_label: Label = $DieLabel
@onready var die_icon: TextureRect = $DieIcon
@onready var status_label: Label = $StatusLabel
@onready var face_grid: GridContainer = $FaceGrid
@onready var average_label: Label = $AverageLabel
@onready var promotion_label: Label = $PromotionLabel
const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

var die: Die
var original_grid_text: String # Used for the Alt-hover average display
var is_selected = false
var average_roll = 0
var upgrades_list: VBoxContainer
var current_scale_factor: float = 1.0
var current_base_size: Vector2 = Vector2(120, 120)

var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_timer: Timer
var _tooltip_tween: Tween
var _hovered_control: Control

func _ready():
	# 1. Create a new stylebox
	var new_style = StyleBoxFlat.new()
	new_style.bg_color = Color(0.9, 0.7, 0.2)
		
	# Optional: Apply it to hover/pressed so it doesn't flicker gray
	add_theme_stylebox_override("hover", new_style)
	add_theme_stylebox_override("pressed", new_style)

	face_grid.set_anchors_preset(Control.PRESET_TOP_LEFT)
	die_label.label_settings = null # Allow theme overrides
	die_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Create a container to display the list of upgrades on the die.
	upgrades_list = VBoxContainer.new()
	upgrades_list.name = "UpgradesList"
	upgrades_list.mouse_filter = MOUSE_FILTER_IGNORE # Let clicks pass through to the button.
	add_child(upgrades_list)
	face_grid.resized.connect(_update_layout)
	upgrades_list.resized.connect(_update_layout)
	resized.connect(_update_layout)

	# --- Custom Tooltip Setup ---
	_tooltip_panel = PanelContainer.new()
	var tooltip_style = StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0, 0, 0, 0.8)
	tooltip_style.content_margin_left = 8
	tooltip_style.content_margin_top = 4
	tooltip_style.content_margin_right = 8
	tooltip_style.content_margin_bottom = 4
	_tooltip_panel.add_theme_stylebox_override("panel", tooltip_style)
	_tooltip_label = Label.new()
	_tooltip_panel.add_child(_tooltip_label)
	_tooltip_panel.visible = false
	_tooltip_panel.set_as_top_level(true)
	_tooltip_panel.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_tooltip_panel)

	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.1
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_show_tooltip)
	add_child(_tooltip_timer)

func _process(_delta):
	# On every frame, check if the mouse is over this control and if ALT is pressed.
	# This provides immediate feedback to the user.
	var show_avg = MainGame.debug_mode
	if not show_avg and get_global_rect().has_point(get_global_mouse_position()) and Input.is_key_pressed(KEY_ALT):
		show_avg = true

	if show_avg and average_roll > 0:
		if MainGame.debug_mode:
			var effect_val = 0.0
			if die.effect:
				effect_val = die.effect.tier * 1.5 # Estimated weight
			var total = average_roll + effect_val
			average_label.text = "Avg: %.1f\nEff: %.1f\nTot: %.1f" % [average_roll, effect_val, total]
		else:
			average_label.text = "Avg:\n%.1f" % average_roll
		average_label.visible = true
	else:
		average_label.visible = false


func set_die(die_data: Die, force_grid: bool = false, is_upgrade_reward: bool = false, _upgraded_faces_info: Array = [], show_status_text: bool = false):
	deselect()
	
	self.die = die_data
	status_label.text = ""
	die_label.visible = false
	promotion_label.visible = false
	var die_object: Die = die_data

	# Clear previous contents of the grid
	for child in face_grid.get_children():
		child.queue_free()

	if die.result_value > 0 and not force_grid:
		# Standard display for rolled dice in hand
		current_base_size = Vector2(80, 80)
		face_grid.columns = 1
		
		var cell = DieGridCell.instantiate()
		var label = cell.get_node("Label")
		label.text = str(die.result_value)
		label.set("theme_override_font_sizes/font_size", 48) # Make the single number large
		cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new()) # Remove panel style for single value
		face_grid.add_child(cell)
		original_grid_text = str(die.result_value)
	else:
		# Larger display for unrolled dice on the reward screen
		current_base_size = Vector2(100, 100)
		
		# Set columns to achieve the desired number of rows
		match die.sides:
			4, 6:
				face_grid.columns = die.sides
			8:
				face_grid.columns = 4 # 2 rows
			10:
				face_grid.columns = 5 # 2 rows
			12:
				face_grid.columns = 6 # 2 rows
			20:
				face_grid.columns = 5 # 4 rows
			_:
				face_grid.columns = 4 # Default fallback
		face_grid.add_theme_constant_override("h_separation", -1)
		face_grid.add_theme_constant_override("v_separation", -1)
		
		# The die resource now has an array of DieFace objects
		for face_data in die_object.faces:
			var cell = DieGridCell.instantiate()
			cell.get_node("Label").text = str(face_data.value)
			face_grid.add_child(cell)
			
			# If the face has an effect, highlight it
			if die.effect:
				var effect: DieFaceEffect = die.effect
				var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.bg_color = effect.highlight_color
				cell.add_theme_stylebox_override("panel", style)
		# Clear previous list
		for child in upgrades_list.get_children():
			child.queue_free()
			
		if is_upgrade_reward:
			var d_name = _get_die_name(die)
			die_label.text = d_name
			die_label.visible = true
			if d_name.length() > 5:
				die_label.add_theme_font_size_override("font_size", 18)
			else:
				die_label.remove_theme_font_size_override("font_size")
				
			status_label.text = "(Upgrade)" if show_status_text else ""
			
			if die.effect:
				_add_effect_panel_to_list(upgrades_list, die.effect, "Face Value")
				upgrades_list.visible = true
			
		else: # New Die
			var d_name = _get_die_name(die)
			die_label.text = d_name
			die_label.visible = true
			if d_name.length() > 5:
				die_label.add_theme_font_size_override("font_size", 18)
			else:
				die_label.remove_theme_font_size_override("font_size")
				
			status_label.text = ""
			if die.effect:
				_add_effect_panel_to_list(upgrades_list, die.effect, "Face Value")
				upgrades_list.visible = true

		# Show promotion count
		var upgrades = die.get_meta("upgrade_count", 0)
		if upgrades > 0:
			promotion_label.text = "+%d" % upgrades
			promotion_label.visible = true

		original_grid_text = "" # Not needed for multi-cell grid
		
	# Set the icon behind the side label
	if die_icon:
		if die_object:
			var icon_path = die_object.icon_path
			if not icon_path.is_empty():
				die_icon.texture = load(icon_path)
			else:
				die_icon.texture = null # Clear texture if no icon is found
		else:
			die_icon.texture = null
	
	# Calculate actual average from faces
	var sum = 0.0
	if die.faces.size() > 0:
		for f in die.faces:
			sum += f.value
		average_roll = sum / float(die.faces.size())
	else:
		average_roll = 0.0
		
	var bonus = die.get_meta("upgrade_count", 0)
	average_roll += bonus

	_apply_scale()
	visible = true
	call_deferred("_update_layout")

func select():
	is_selected = true
	#self.color = Color(0.9, 0.7, 0.2) # Gold color for selection
	
func deselect():
	is_selected = false
	#self.colo color = Color(0.2, 0.2, 0.2) # Default dark gray

func _on_mouse_entered():
	emit_signal("die_hovered", self)

func _on_mouse_exited():
	# Revert text when mouse exits, in case Alt was held.
	if face_grid.get_child_count() > 0 and original_grid_text != "":
		var first_cell_label = face_grid.get_child(0).get_node("Label") as Label
		first_cell_label.text = original_grid_text

func _clean_bbcode(bbcode_text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(bbcode_text, "", true)

func _add_effect_panel_to_list(parent_container: VBoxContainer, effect: DieFaceEffect, face_value_placeholder: String):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_bottom = 2
	style.border_color = effect.highlight_color
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", style)
	
	panel.mouse_filter = MOUSE_FILTER_PASS
	panel.mouse_default_cursor_shape = Control.CURSOR_HELP
	
	var tooltip_desc = effect.description
	tooltip_desc = tooltip_desc.replace("{value}", face_value_placeholder)
	tooltip_desc = tooltip_desc.replace("{value / 2}", face_value_placeholder + " / 2")
	var cleaned_tooltip_text = _clean_bbcode(tooltip_desc)
	panel.mouse_entered.connect(_on_control_hover_entered.bind(panel, cleaned_tooltip_text))
	
	var label = Label.new()
	label.text = effect.name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_color_override("font_color", effect.highlight_color)
	panel.add_child(label)
	
	parent_container.add_child(panel)

func _get_die_name(d: Die) -> String:
	var parts = []
	
	# 1. Check Custom/Promoted
	var values = []
	for f in d.faces:
		values.append(f.value)
	values.sort()
	
	var is_standard = true
	var is_promoted = false
	var is_custom = false
	
	# Check against standard 1..N
	for i in range(values.size()):
		if values[i] != i + 1:
			is_standard = false
			break
	
	if not is_standard:
		# Check if Promoted (Standard + K)
		var k = values[0] - 1
		var matches_promoted = true
		if k <= 0: 
			matches_promoted = false
		else:
			for i in range(values.size()):
				if values[i] != (i + 1) + k:
					matches_promoted = false
					break
		
		if matches_promoted:
			is_promoted = true
		else:
			is_custom = true
			
	if is_custom: parts.append("Customized")
	elif is_promoted: parts.append("Promoted")
	if d.effect: parts.append("Special")
	parts.append("D%d" % d.sides)
	return " ".join(parts)

func _apply_scale():
	custom_minimum_size = current_base_size * current_scale_factor
	
	var cell_base_size = 16.0
	var scaled_cell_size = cell_base_size * current_scale_factor
	
	for cell in face_grid.get_children():
		cell.custom_minimum_size = Vector2(scaled_cell_size, scaled_cell_size)
		var label = cell.get_node("Label")
		if face_grid.columns == 1 and face_grid.get_child_count() == 1:
			label.add_theme_font_size_override("font_size", int(48 * current_scale_factor))
		else:
			label.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
	
	if die_label.visible:
		var base_font = 40
		if die_label.text.length() > 5:
			base_font = 18
		die_label.add_theme_font_size_override("font_size", int(base_font * current_scale_factor))
		die_label.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
			
	call_deferred("_update_layout")

func _update_layout():
	var current_y = 5 * current_scale_factor
	
	if die_label.visible:
		die_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		die_label.position.y = current_y
		die_label.size.x = size.x
		die_label.size.y = 0 # Reset to allow auto-sizing
		
		current_y += die_label.get_minimum_size().y + (2 * current_scale_factor)

	# Position the grid
	face_grid.position.y = current_y
	face_grid.size.x = size.x
	
	# If the upgrades list is visible, position it below the grid
	var content_bottom = face_grid.position.y + face_grid.get_minimum_size().y
	if upgrades_list.visible:
		upgrades_list.position.y = content_bottom + (5 * current_scale_factor)
		upgrades_list.size.x = size.x
		content_bottom = upgrades_list.position.y + upgrades_list.get_minimum_size().y

	custom_minimum_size.y = content_bottom + (5 * current_scale_factor)

func update_scale(factor: float):
	current_scale_factor = factor
	_apply_scale()

# --- Custom Tooltip Handlers ---

func _on_control_hover_entered(control: Control, p_tooltip_text: String):
	_tooltip_timer.stop()
	_hide_tooltip(false)
	_hovered_control = control
	_tooltip_label.text = p_tooltip_text
	_tooltip_timer.start()
	if not control.is_connected("mouse_exited", _on_control_hover_exited):
		control.mouse_exited.connect(_on_control_hover_exited)

func _on_control_hover_exited():
	_tooltip_timer.stop()
	_hovered_control = null
	_hide_tooltip()

func _show_tooltip():
	if not is_instance_valid(_hovered_control): return
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	_tooltip_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	var viewport_rect = get_viewport().get_visible_rect()
	var tooltip_size = _tooltip_panel.get_minimum_size()
	var mouse_pos = get_global_mouse_position()
	
	var tooltip_pos = mouse_pos + Vector2(15, 15)
	
	if tooltip_pos.x + tooltip_size.x > viewport_rect.end.x:
		tooltip_pos.x = mouse_pos.x - tooltip_size.x - 15
	if tooltip_pos.y + tooltip_size.y > viewport_rect.end.y:
		tooltip_pos.y = mouse_pos.y - tooltip_size.y - 15
		
	_tooltip_panel.global_position = tooltip_pos
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.visible = true
	_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.2)

func _hide_tooltip(animated: bool = true):
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	if animated and _tooltip_panel.visible:
		_tooltip_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 0.0, 0.1)
		_tooltip_tween.tween_callback(func(): if is_instance_valid(_tooltip_panel): _tooltip_panel.visible = false)
	else:
		_tooltip_panel.visible = false
