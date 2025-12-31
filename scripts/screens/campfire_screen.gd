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

func _ready():
	visible = false
	selection_overlay.visible = false
	effect_selection_overlay.visible = false

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
		btn.tooltip_text = _clean_bbcode(effect.description)
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
	
	# Pick a random face
	var target_face = selected_die.faces.pick_random()
	
	# Apply effect (replace existing)
	target_face.effects.clear()
	target_face.effects.append(effect)
	
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