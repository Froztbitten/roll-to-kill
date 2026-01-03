extends Control

@onready var gold_label: Label = $Panel/VBoxContainer/Header/GoldLabel
@onready var remove_die_button: Button = $Panel/VBoxContainer/Options/RemoveDieButton
@onready var upgrade_die_button: Button = $Panel/VBoxContainer/Options/UpgradeDieButton
@onready var effects_container: HBoxContainer = $Panel/VBoxContainer/Options/EffectsContainer
@onready var abilities_container: HBoxContainer = $Panel/VBoxContainer/Options/AbilitiesContainer
@onready var selection_overlay: Control = $SelectionOverlay
@onready var selection_grid: GridContainer = $SelectionOverlay/ScrollContainer/GridContainer
@onready var selection_title: Label = $SelectionOverlay/TitleLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var player: Player
var current_mode = "" # "remove" or "upgrade"

# --- Custom Tooltip Variables ---
var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_timer: Timer
var _tooltip_tween: Tween
var _hovered_control: Control

func _ready():
	visible = false
	selection_overlay.visible = false
	
	# Set tooltips for static shop buttons
	remove_die_button.mouse_entered.connect(_on_control_hover_entered.bind(remove_die_button, "Select a die to permanently remove from your bag."))
	upgrade_die_button.mouse_entered.connect(_on_control_hover_entered.bind(upgrade_die_button, "Select a die to increase the value of all its faces by 1.\nCost increases with each upgrade."))
	
	# Style static buttons
	_style_shop_button(remove_die_button)
	_style_shop_button(upgrade_die_button)
	_style_shop_button(close_button)
	
	# Auto-connect to MapScreen if present in the scene tree
	var map_screen = get_node_or_null("../MapScreen")
	if map_screen:
		map_screen.node_selected.connect(_on_map_node_selected)
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
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

func _on_map_node_selected(node_data):
	if node_data.type == "shop":
		open()

func open():
	player = get_node_or_null("../../Player")
	if not player: return
	
	visible = true
	_update_ui()
	_generate_shop_inventory()
	_on_viewport_size_changed()

func _update_ui():
	gold_label.text = "Gold: %d" % player.gold
	remove_die_button.text = "Remove Die (%dg)" % player.die_removal_cost
	
	if player.gold < player.die_removal_cost:
		remove_die_button.disabled = true
	else:
		remove_die_button.disabled = false

func _generate_shop_inventory():
	# Clear previous
	for child in effects_container.get_children():
		child.queue_free()
	for child in abilities_container.get_children():
		child.queue_free()
		
	# Generate 3 Random Upgrades
	for i in range(3):
		_generate_offer()

	# Generate 3 Random Abilities
	var ability_files = DirAccess.get_files_at("res://resources/abilities/")
	if ability_files:
		var shuffled_files = Array(ability_files)
		shuffled_files.shuffle()
		for i in range(min(3, shuffled_files.size())):
			var file_name = shuffled_files[i]
			if file_name.ends_with(".tres") or file_name.ends_with(".remap"):
				file_name = file_name.replace(".remap", "")
				var ability = load("res://resources/abilities/" + file_name) as AbilityData
				if ability:
					var btn = Button.new()
					btn.text = "%s (150g)" % ability.title					
					btn.mouse_entered.connect(_on_control_hover_entered.bind(btn, _clean_bbcode(ability.description)))
					btn.custom_minimum_size = Vector2(100, 50)
					btn.pressed.connect(_on_buy_ability_pressed.bind(ability, 150, btn))
					_style_shop_button(btn)
					abilities_container.add_child(btn)

func _generate_offer(existing_container: VBoxContainer = null):
	if player._game_dice_bag.is_empty():
		if existing_container:
			existing_container.queue_free()
		return

	var random_die = player._game_dice_bag.pick_random()
	var random_face = random_die.faces.pick_random()
	
	# Use EffectLibrary to get a compatible effect
	var effect = EffectLibrary.get_random_effect_for_die(random_die.sides)
	
	if effect:
		var offer_vbox = existing_container
		if not offer_vbox:
			offer_vbox = VBoxContainer.new()
			offer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			offer_vbox.custom_minimum_size.x = 240
			effects_container.add_child(offer_vbox)
		else:
			for child in offer_vbox.get_children():
				offer_vbox.remove_child(child)
				child.queue_free()
		
		var die_display = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		offer_vbox.add_child(die_display)
		
		var upgraded_faces_info = [{
			"face_value": random_face.value,
			"effect_name": effect.name,
			"effect_color": effect.highlight_color.to_html()
		}]
		die_display.set_die(random_die, true, true, upgraded_faces_info)
		die_display.size_flags_horizontal = SIZE_SHRINK_CENTER
		die_display.disabled = true
		die_display.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var sep = HSeparator.new()
		sep.custom_minimum_size.y = 10
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sep_style = StyleBoxLine.new()
		sep_style.color = Color(1, 1, 1, 0.2)
		sep_style.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_style)
		offer_vbox.add_child(sep)
		
		var desc_container = HFlowContainer.new()
		desc_container.alignment = FlowContainer.ALIGNMENT_CENTER
		offer_vbox.add_child(desc_container)
		
		if random_face.effects.is_empty():
			_add_text_label(desc_container, "Add")
			_add_effect_label(desc_container, effect, random_face.value)
			_add_text_label(desc_container, "to Face %d" % random_face.value)
		else:
			var old_effect = random_face.effects[0]
			_add_text_label(desc_container, "Replace")
			_add_effect_label(desc_container, old_effect, random_face.value)
			_add_text_label(desc_container, "with")
			_add_effect_label(desc_container, effect, random_face.value)
			_add_text_label(desc_container, "on Face %d" % random_face.value)
		
		var btn = Button.new()
		btn.text = "Buy (50g)"
		btn.custom_minimum_size = Vector2(100, 40)
		_style_shop_button(btn)
		btn.pressed.connect(_on_buy_specific_upgrade_pressed.bind(random_die, random_face, effect, 50, btn, die_display))
		offer_vbox.add_child(btn)

func _on_remove_die_pressed():
	if player.gold < player.die_removal_cost: return
	current_mode = "remove"
	_show_dice_selection("Select Die to Remove")

func _on_upgrade_die_pressed():
	current_mode = "upgrade"
	_show_dice_selection("Select Die to Upgrade")

func _show_dice_selection(title: String):
	selection_title.text = title
	selection_overlay.visible = true
	
	for child in selection_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var btn = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		selection_grid.add_child(btn)
		btn.set_die(die, true)
		btn.scale = Vector2.ONE
		btn.pressed.connect(_on_die_selected.bind(die))
	_on_viewport_size_changed()

func _on_die_selected(die: Die):
	if current_mode == "remove":
		if player.gold >= player.die_removal_cost:
			player.add_gold(-player.die_removal_cost)
			player.remove_die_from_bag(die)
			player.die_removal_cost += 25
			
			# Reroll any shop offers that were for this die
			for offer_vbox in effects_container.get_children():
				if offer_vbox.get_child_count() > 0:
					var display = offer_vbox.get_child(0)
					if display is RewardsDieDisplay and display.die == die:
						_generate_offer(offer_vbox)
			
			_update_ui()
			selection_overlay.visible = false
			_on_viewport_size_changed()
			
	elif current_mode == "upgrade":
		var upgrades = die.get_meta("upgrade_count", 0)
		if upgrades >= 3:
			print("Die is fully upgraded!")
			return
			
		var cost = 50 * (upgrades + 1)
		if player.gold >= cost:
			player.add_gold(-cost)
			player.upgrade_die(die)
			_update_ui()
			selection_overlay.visible = false
		else:
			print("Not enough gold!")

func _on_buy_specific_upgrade_pressed(die: Die, face, effect: DieFaceEffect, cost: int, button: Button, die_display: Control):
	if player.gold >= cost:
		player.add_gold(-cost)
		face.effects.clear()
		face.effects.append(effect)
		button.disabled = true
		button.text = "Sold"
		_update_ui()
		
		die_display.set_die(die)
		die_display.scale = Vector2.ONE
		_on_viewport_size_changed()

func _on_buy_ability_pressed(ability, cost, button):
	if player.gold >= cost:
		player.add_gold(-cost)
		player.add_ability(ability)
		button.disabled = true
		button.text = "Sold"
		_update_ui()

func _on_close_button_pressed():
	visible = false
	# Signal Main to continue or go back to map?
	# Assuming Main handles state, but for now we just hide.
	# If MapScreen is visible behind, we might need to re-enable it.
	if not MainGame.debug_mode:
		var map_screen = get_node_or_null("../MapScreen")
		if map_screen:
			map_screen.visible = true

func _on_cancel_selection_pressed():
	selection_overlay.visible = false

func _clean_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(text, "", true)

func _add_text_label(parent: Control, text: String):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _add_effect_label(parent: Control, effect: DieFaceEffect, face_value: int):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_width_bottom = 2
	style.border_color = effect.highlight_color
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = effect.name
	label.add_theme_color_override("font_color", effect.highlight_color)
	panel.add_child(label)
	
	var tooltip_desc = effect.description
	tooltip_desc = tooltip_desc.replace("{value}", str(face_value))
	tooltip_desc = tooltip_desc.replace("{value / 2}", str(ceili(face_value / 2.0)))	
	panel.mouse_entered.connect(_on_control_hover_entered.bind(panel, _clean_bbcode(tooltip_desc)))
	panel.mouse_default_cursor_shape = Control.CURSOR_HELP
	
	parent.add_child(panel)

func _style_shop_button(btn: Button):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.3, 0.3, 0.35, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)

func _on_viewport_size_changed():
	var base_height = 648.0
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_factor = viewport_size.y / base_height
	
	for offer_vbox in effects_container.get_children():
		for child in offer_vbox.get_children():
			if child.has_method("update_scale"):
				child.update_scale(scale_factor)
	
	for child in selection_grid.get_children():
		if child.has_method("update_scale"):
			child.update_scale(scale_factor)

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
