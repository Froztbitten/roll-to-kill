extends Control

signal leave_campfire

@onready var rest_button = $Panel/VBoxContainer/HBoxContainer/RestButton
@onready var smith_button = $Panel/VBoxContainer/HBoxContainer/SmithButton
@onready var message_label = $Panel/VBoxContainer/MessageLabel
@onready var selection_overlay = $SelectionOverlay
@onready var selection_grid = $SelectionOverlay/ScrollContainer/GridContainer
@onready var effect_selection_overlay = $EffectSelectionOverlay
@onready var effect_options_container = $EffectSelectionOverlay/Panel/VBoxContainer/OptionsContainer

var player: Player
var selected_die: Die

# --- Custom Tooltip Variables ---
var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_timer: Timer
var _tooltip_tween: Tween
var _hovered_control: Control

func _ready():
	visible = false
	selection_overlay.visible = false
	effect_selection_overlay.visible = false

	# --- Custom Tooltip Setup ---
	_tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_label = Label.new()
	_tooltip_panel.add_child(_tooltip_label)
	_tooltip_panel.visible = false
	_tooltip_panel.set_as_top_level(true)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip_panel)

	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.1
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_show_tooltip)
	add_child(_tooltip_timer)

func open():
	player = get_node_or_null("../../Player")
	if not player: return
	
	visible = true
	message_label.text = "The fire is warm."
	rest_button.disabled = false
	smith_button.disabled = false
	
	if player.hp == player.max_hp:
		rest_button.text = "Rest\n(Full HP)"
	else:
		rest_button.text = "Rest\n(Heal 50%)"

func _on_rest_button_pressed():
	if not player: return
	var heal_amount = floor(player.max_hp * 0.5)
	player.heal(heal_amount)
	message_label.text = "You feel refreshed."
	rest_button.disabled = true

func _on_smith_button_pressed():
	_show_dice_selection()

func _show_dice_selection():
	selection_overlay.visible = true
	for child in selection_grid.get_children():
		child.queue_free()
	
	for die in player._game_dice_bag:
		var btn = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		selection_grid.add_child(btn)
		btn.set_die(die, true)
		btn.scale = Vector2.ONE
		btn.pressed.connect(_on_die_selected.bind(die))

func _on_die_selected(die: Die):
	selected_die = die
	selection_overlay.visible = false
	_show_effect_options(die)

func _show_effect_options(die: Die):
	effect_selection_overlay.visible = true
	for child in effect_options_container.get_children():
		child.queue_free()
	
	# Get all possible effects for this die size, shuffle them, and offer 3 unique ones.
	var all_effects_for_die = []
	if EffectLibrary.effects_by_die_size.has(die.sides):
		all_effects_for_die = EffectLibrary.effects_by_die_size[die.sides].duplicate()

	if all_effects_for_die.is_empty():
		_on_cancel_effect_pressed()
		message_label.text = "No inscriptions available for this die."
		return

	all_effects_for_die.shuffle()
	var effects_to_offer = all_effects_for_die.slice(0, 3)

	for effect in effects_to_offer:
		var btn = Button.new()
		btn.text = effect.name
		btn.mouse_entered.connect(_on_control_hover_entered.bind(btn, _clean_bbcode(effect.description)))
		btn.custom_minimum_size = Vector2(0, 60)
		btn.pressed.connect(_on_effect_chosen.bind(effect))
		
		# Add some styling
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
		style.border_color = effect.highlight_color
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		btn.add_theme_stylebox_override("normal", style)
		
		effect_options_container.add_child(btn)

func _on_effect_chosen(effect: DieFaceEffect):
	if not selected_die: return
	
	# Apply effect to die
	selected_die.effect = effect
	
	message_label.text = "Inscribed %s onto D%d." % [effect.name, selected_die.sides]
	effect_selection_overlay.visible = false
	smith_button.disabled = true

func _on_leave_button_pressed():
	visible = false
	emit_signal("leave_campfire")

func _on_cancel_selection_pressed():
	selection_overlay.visible = false

func _on_cancel_effect_pressed():
	effect_selection_overlay.visible = false

func _clean_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(text, "", true)

# --- Custom Tooltip Handlers ---

func _on_control_hover_entered(control: Control, text: String):
	_tooltip_timer.stop()
	_hide_tooltip(false)
	_hovered_control = control
	_tooltip_label.text = text
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