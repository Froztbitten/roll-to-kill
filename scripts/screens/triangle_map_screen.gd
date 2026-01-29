extends Control

signal node_selected(node_data)
signal open_quest_board

const DIE_RENDERER_SCENE = preload("res://scenes/ui/die_3d_renderer.tscn")
const REWARDS_DIE_DISPLAY = preload("res://scenes/screens/rewards_die_display.tscn")

@onready var map_container = $ScrollContainer/MapContainer
@onready var scroll_container = $ScrollContainer
@onready var player_icon = $ScrollContainer/MapContainer/PlayerIcon

var grid_data = {}
var current_node = null
var grid_width = 30
var grid_height = 12
var triangle_size = 100.0

var turns_left = 21
var turn_count = 0
var moves_remaining = 0
var path_line: Line2D
var full_path_line: Line2D
var distance_label: Label
var full_distance_label: Label
var moves_label: Label
var is_moving = false
var is_rolling = false
var current_tween: Tween
var pending_roll_result = 0
var current_roll_overlay: Control
var pending_movement_path = []
var final_moves_remaining = 0
var ui_layer: Control
var mountain_texture: ImageTexture
var water_texture: ImageTexture
var grass_texture: ImageTexture
var dirt_texture: ImageTexture
var town_ui: Control
var temp_labels: Array[Label] = []
var roll_id = 0
var quest_log_container: VBoxContainer
var fog_enabled = true
var fog_radius = 4
var explored_nodes = {}
var special_visuals = {}
var player = null
var inn_ui: Control
var inn_options_container: VBoxContainer
var dice_shop_ui: Control
var dice_shop_grid: GridContainer
var dice_removal_overlay: Control
var dice_removal_grid: GridContainer
var remove_die_button: Button
var forge_ui: Control
var forge_selection_overlay: Control
var forge_selection_grid: GridContainer
var forge_selection_title: Label
var forge_effect_overlay: Control
var forge_action_overlay: Control
var forge_action_container: VBoxContainer
var forge_grid: GridContainer
var forge_effect_container: VBoxContainer
var selected_forge_die: Die
var current_forge_mode: String = ""
var has_rested_in_town = false
var spell_shop_ui: Control
var spell_shop_abilities_grid: GridContainer
var spell_shop_charms_grid: GridContainer
var reroll_charms_button: Button
var reroll_charms_cost = 25
var spell_shop_generated = false
var dice_shop_generated = false
var view_only = false
var close_map_button: Button
var log_margin: MarginContainer
var current_highlighted_nodes = {} # node -> original_color
var current_highlighted_visuals = {} # "icon" -> icon_node, "label" -> label_node
var current_highlight_identifier = null
var highlight_clear_timer: Timer
var current_scale_factor = 1.0
var boss_room_nodes = []
var decayed_nodes = {}
var current_zoom = 1.0
var map_base_size = Vector2.ZERO

func _input(event):
	if not visible: return
	
	# If any menu is open, let the event propagate (for scrolling lists etc.)
	if (town_ui and town_ui.visible) or \
	   (inn_ui and inn_ui.visible) or \
	   (dice_shop_ui and dice_shop_ui.visible) or \
	   (forge_ui and forge_ui.visible) or \
	   (spell_shop_ui and spell_shop_ui.visible):
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			if is_rolling:
				_skip_roll_animation()
				get_viewport().set_input_as_handled()
			elif is_moving:
				_skip_movement_animation()
				get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		fog_enabled = !fog_enabled
		update_fog()
		get_viewport().set_input_as_handled()

func _ready():
	visible = false
	visibility_changed.connect(func(): 
		if ui_layer: ui_layer.visible = visible
		# Auto-start turn if we return to map with no moves (e.g. after combat)
		if visible and not view_only and moves_remaining == 0 and not is_rolling and not is_moving and current_node and current_node.type != "town":
			start_turn()
	)
	
	# Hide scrollbars
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Wrap MapContainer in a CenterContainer to handle centering
	var center_container = CenterContainer.new()
	center_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_container.get_parent().remove_child(map_container)
	center_container.add_child(map_container)
	scroll_container.add_child(center_container)
	
	# Disable native scrolling on ScrollContainer
	var scroll_script = GDScript.new()
	scroll_script.source_code = "extends ScrollContainer\nfunc _gui_input(event):\n\tif event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):\n\t\taccept_event()"
	scroll_script.reload()
	scroll_container.set_script(scroll_script)
	
	# Setup Static UI
	ui_layer = Control.new()
	ui_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.visible = visible
	add_child(ui_layer)
	
	# Quest Log (Top Left)
	log_margin = MarginContainer.new()
	log_margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Margin updated in _on_viewport_size_changed
	log_margin.add_theme_constant_override("margin_left", 20)
	ui_layer.add_child(log_margin)
	
	quest_log_container = VBoxContainer.new()
	log_margin.add_child(quest_log_container)
	
	# Movement Label on Player
	moves_label = Label.new()
	moves_label.text = ""
	moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_label.add_theme_font_size_override("font_size", 24)
	moves_label.add_theme_color_override("font_outline_color", Color.BLACK)
	moves_label.add_theme_constant_override("outline_size", 4)
	moves_label.custom_minimum_size = Vector2(100, 30)
	moves_label.position = Vector2(player_icon.size.x / 2.0 - 50, -80)
	player_icon.add_child(moves_label)
	
	# Initialize Procedural Textures
	# We generate Images synchronously to ensure they are ready immediately.
	var m_noise = FastNoiseLite.new()
	m_noise.seed = randi()
	m_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	m_noise.frequency = 0.02
	m_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	m_noise.fractal_octaves = 4
	
	var m_gradient = Gradient.new()
	m_gradient.set_color(0, Color(0.2, 0.2, 0.25))
	m_gradient.set_color(1, Color(0.7, 0.7, 0.75))
	mountain_texture = _create_noise_texture(m_noise, m_gradient)
	
	var w_noise = FastNoiseLite.new()
	w_noise.seed = randi()
	w_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	w_noise.frequency = 0.02
	
	var w_gradient = Gradient.new()
	w_gradient.set_color(0, Color(0.1, 0.3, 0.7))
	w_gradient.set_color(1, Color(0.2, 0.5, 0.9))
	water_texture = _create_noise_texture(w_noise, w_gradient)
	
	var g_noise = FastNoiseLite.new()
	g_noise.seed = randi()
	g_noise.frequency = 0.05
	var g_gradient = Gradient.new()
	g_gradient.set_color(0, Color(0.1, 0.25, 0.1))
	g_gradient.set_color(1, Color(0.2, 0.35, 0.2))
	grass_texture = _create_noise_texture(g_noise, g_gradient)
	
	var d_noise = FastNoiseLite.new()
	d_noise.seed = randi()
	d_noise.frequency = 0.05
	var d_gradient = Gradient.new()
	d_gradient.set_color(0, Color(0.4, 0.3, 0.2))
	d_gradient.set_color(1, Color(0.5, 0.4, 0.3))
	dirt_texture = _create_noise_texture(d_noise, d_gradient)
	
	_create_town_ui()
	_create_inn_ui()
	_create_dice_shop_ui()
	_create_forge_ui()
	_create_spell_shop_ui()
	
	# Create Close Button for view-only mode
	close_map_button = Button.new()
	close_map_button.text = "Close Map"
	close_map_button.custom_minimum_size = Vector2(200, 60)
	close_map_button.add_theme_font_size_override("font_size", 24)
	close_map_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close_map_button.offset_left = -220
	close_map_button.offset_top = -80
	close_map_button.offset_right = -20
	close_map_button.offset_bottom = -20
	close_map_button.pressed.connect(func(): visible = false)
	close_map_button.visible = false
	ui_layer.add_child(close_map_button)
	
	highlight_clear_timer = Timer.new()
	highlight_clear_timer.wait_time = 0.05
	highlight_clear_timer.one_shot = true
	highlight_clear_timer.timeout.connect(_perform_clear_highlights)
	add_child(highlight_clear_timer)
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

func _create_noise_texture(noise: FastNoiseLite, gradient: Gradient) -> ImageTexture:
	var tex_size = 512
	var image = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	
	for y in range(tex_size):
		for x in range(tex_size):
			var value = noise.get_noise_2d(x, y)
			# Normalize from [-1, 1] to [0, 1]
			var normalized = (value + 1.0) / 2.0
			var color = gradient.sample(normalized)
			image.set_pixel(x, y, color)
			
	return ImageTexture.create_from_image(image)

func _create_town_ui():
	town_ui = Control.new()
	town_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.z_index = 200
	town_ui.visible = false
	ui_layer.add_child(town_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	var title = TextureRect.new()
	title.texture = load("res://assets/ai/ui/town_banner.svg")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2(600, 187)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title)
	
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 30)
	vbox.add_child(grid)
	
	var create_town_btn = func(text: String, color: Color, icon_path: String):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(220, 180)
		
		var style = StyleBoxFlat.new()
		style.bg_color = color
		style.border_width_bottom = 6
		style.border_color = color.darkened(0.3)
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_right = 12
		style.corner_radius_bottom_left = 12
		
		btn.add_theme_stylebox_override("normal", style)
		
		var hover_style = style.duplicate()
		hover_style.bg_color = color.lightened(0.1)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style = style.duplicate()
		pressed_style.bg_color = color.darkened(0.1)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		
		var content = VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 10)
		btn.add_child(content)
		
		if icon_path != "":
			var icon = TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(80, 80)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(icon)
			
		var lbl = Label.new()
		lbl.text = text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		content.add_child(lbl)
		
		grid.add_child(btn)
		return btn

	create_town_btn.call("Quest Board", Color(0.55, 0.35, 0.15), "res://assets/ai/ui/quest_board.svg").pressed.connect(func(): emit_signal("open_quest_board"))
	create_town_btn.call("Spell Shop", Color(0.4, 0.2, 0.6), "res://assets/ai/ui/spell_shop.svg").pressed.connect(_open_spell_shop_menu)
	create_town_btn.call("Forge", Color(0.7, 0.3, 0.1), "res://assets/ai/ui/dice_forge.svg").pressed.connect(_open_forge_menu)
	create_town_btn.call("Dice Shop", Color(0.8, 0.7, 0.1), "res://assets/ai/ui/dice_shop.svg").pressed.connect(_open_dice_shop_menu)
	create_town_btn.call("Inn", Color(0.2, 0.5, 0.2), "res://assets/ai/ui/inn.svg").pressed.connect(_open_inn_menu)
	
	var leave_btn = Button.new()
	leave_btn.text = "Leave Town"
	leave_btn.custom_minimum_size = Vector2(200, 60)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.add_theme_font_size_override("font_size", 24)
	leave_btn.pressed.connect(func(): 
		town_ui.visible = false
		if moves_remaining <= 0:
			start_turn()
	)
	vbox.add_child(leave_btn)

func _create_inn_ui():
	inn_ui = Control.new()
	inn_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	inn_ui.z_index = 201 # Above town UI
	inn_ui.visible = false
	ui_layer.add_child(inn_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	inn_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	inn_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "The Inn"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	var options_container = VBoxContainer.new()
	options_container.name = "Options"
	inn_options_container = options_container
	options_container.add_theme_constant_override("separation", 20)
	vbox.add_child(options_container)
	
	var create_room_btn = func(text: String, cost: int, heal_percent: float):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(400, 80)
		btn.text = "%s\nHeal %.0f%% HP (%dg)" % [text, heal_percent * 100, cost]
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(func(): _on_rest_selected(cost, heal_percent))
		btn.set_meta("cost", cost)
		btn.set_meta("base_text", text)
		btn.set_meta("percent", heal_percent)
		options_container.add_child(btn)
		return btn

	create_room_btn.call("Straw Bed", 10, 0.25)
	create_room_btn.call("Standard Room", 25, 0.50)
	create_room_btn.call("Luxury Suite", 50, 0.75)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(_close_inn_menu)
	vbox.add_child(back_btn)

func _open_inn_menu():
	town_ui.visible = false
	inn_ui.visible = true
	_update_inn_buttons()

func _close_inn_menu():
	inn_ui.visible = false
	town_ui.visible = true

func _update_inn_buttons():
	var options = inn_options_container
	for btn in options.get_children():
		var cost = btn.get_meta("cost")
		var base_text = btn.get_meta("base_text")
		var percent = btn.get_meta("percent")
		
		if has_rested_in_town:
			btn.disabled = true
			btn.text = base_text + "\n(Already Rested)"
		elif player and player.gold < cost:
			btn.disabled = true
			btn.modulate = Color(0.7, 0.7, 0.7)
			btn.text = "%s\nHeal %.0f%% HP (%dg)" % [base_text, percent * 100, cost]
		else:
			btn.disabled = false
			btn.modulate = Color.WHITE
			btn.text = "%s\nHeal %.0f%% HP (%dg)" % [base_text, percent * 100, cost]

func _on_rest_selected(cost: int, percent: float):
	if has_rested_in_town or not player: return
	if player.gold >= cost:
		player.add_gold(-cost)
		var heal_amount = floor(player.max_hp * percent)
		player.heal(heal_amount)
		has_rested_in_town = true
		_update_inn_buttons()

func _create_dice_shop_ui():
	dice_shop_ui = Control.new()
	dice_shop_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_shop_ui.z_index = 201
	dice_shop_ui.visible = false
	ui_layer.add_child(dice_shop_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_shop_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_shop_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "Dice Shop"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	dice_shop_grid = GridContainer.new()
	dice_shop_grid.columns = 3
	dice_shop_grid.add_theme_constant_override("h_separation", 40)
	dice_shop_grid.add_theme_constant_override("v_separation", 40)
	vbox.add_child(dice_shop_grid)
	
	remove_die_button = Button.new()
	remove_die_button.text = "Remove Die"
	remove_die_button.custom_minimum_size = Vector2(300, 60)
	remove_die_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	remove_die_button.add_theme_font_size_override("font_size", 24)
	remove_die_button.pressed.connect(_on_remove_die_shop_pressed)
	vbox.add_child(remove_die_button)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(_close_dice_shop_menu)
	vbox.add_child(back_btn)
	
	# Create Removal Overlay
	dice_removal_overlay = Control.new()
	dice_removal_overlay.visible = false
	dice_removal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_removal_overlay.z_index = 202
	ui_layer.add_child(dice_removal_overlay)
	
	var overlay_bg = ColorRect.new()
	overlay_bg.color = Color(0, 0, 0, 0.95)
	overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_removal_overlay.add_child(overlay_bg)
	
	var overlay_center = CenterContainer.new()
	overlay_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_removal_overlay.add_child(overlay_center)
	
	var overlay_vbox = VBoxContainer.new()
	overlay_vbox.add_theme_constant_override("separation", 30)
	overlay_center.add_child(overlay_vbox)
	
	var overlay_title = Label.new()
	overlay_title.text = "Select Die to Remove"
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", 32)
	overlay_vbox.add_child(overlay_title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 500)
	overlay_vbox.add_child(scroll)
	
	dice_removal_grid = GridContainer.new()
	dice_removal_grid.columns = 5
	dice_removal_grid.add_theme_constant_override("h_separation", 20)
	dice_removal_grid.add_theme_constant_override("v_separation", 20)
	dice_removal_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dice_removal_grid)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(200, 50)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(func(): dice_removal_overlay.visible = false)
	overlay_vbox.add_child(cancel_btn)

func _open_dice_shop_menu():
	town_ui.visible = false
	dice_shop_ui.visible = true
	if player:
		remove_die_button.text = "Remove Die (%dg)" % player.die_removal_cost
		remove_die_button.disabled = player.gold < player.die_removal_cost
	
	if not dice_shop_generated:
		_generate_dice_shop_inventory()
		dice_shop_generated = true

func _close_dice_shop_menu():
	dice_shop_ui.visible = false
	town_ui.visible = true

func _generate_dice_shop_inventory():
	for child in dice_shop_grid.get_children():
		child.queue_free()
	
	# 6 dice: 2 normal, 2 custom values, 2 effects (randomized order)
	var types = ["normal", "normal", "custom", "custom", "effect", "effect"]
	types.shuffle()
	
	for type in types:
		var sides = [4, 6, 8, 10, 12].pick_random()
		var die = Die.new(sides)
		var cost = sides * 5 # Base cost
		
		if type == "custom":
			var normal_total = 0
			var new_total = 0
			for i in range(die.faces.size()):
				normal_total += (i + 1)
				var face = die.faces[i]
				face.value = max(1, face.value + randi_range(-3, 4))
				new_total += face.value
			
			# Sort faces numerically
			die.faces.sort_custom(func(a, b): return a.value < b.value)
			
			cost += (new_total - normal_total) * 3
			cost = max(10, cost)
		elif type == "effect":
			var effect = EffectLibrary.get_random_effect_for_die(sides)
			if effect:
				die.effect = effect
				cost += 75 * effect.tier # More expensive for better effects on all faces
				
				# Rare chance for custom values AND effect
				if randf() < 0.1: # 10% chance
					var bonus = randi_range(1, 3)
					for face in die.faces:
						face.value += bonus
					cost += bonus * sides * 2
		
		var item_vbox = VBoxContainer.new()
		item_vbox.add_theme_constant_override("separation", 10)
		dice_shop_grid.add_child(item_vbox)
		
		var display = REWARDS_DIE_DISPLAY.instantiate()
		item_vbox.add_child(display)
		display.set_die(die, true) # force_grid = true
		
		# Extract name and hide internal label to show it above the die
		var die_name = display.die_label.text
		display.die_label.visible = false
		
		var name_label = Label.new()
		name_label.text = die_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		item_vbox.add_child(name_label)
		item_vbox.move_child(name_label, 0)
		
		display.mouse_filter = Control.MOUSE_FILTER_PASS
		display.custom_minimum_size = Vector2(120, 120)
		
		var buy_btn = Button.new()
		buy_btn.text = "Buy (%dg)" % cost
		buy_btn.custom_minimum_size = Vector2(120, 40)
		buy_btn.pressed.connect(_on_buy_die_pressed.bind(die, cost, buy_btn))
		item_vbox.add_child(buy_btn)
		
		if player and player.gold < cost:
			buy_btn.disabled = true

func _on_buy_die_pressed(die: Die, cost: int, button: Button):
	if player and player.gold >= cost:
		player.add_gold(-cost)
		player.add_to_game_bag([die])
		button.disabled = true
		button.text = "Sold"

func _on_remove_die_shop_pressed():
	if not player or player.gold < player.die_removal_cost: return
	
	dice_removal_overlay.visible = true
	for child in dice_removal_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var display = REWARDS_DIE_DISPLAY.instantiate()
		dice_removal_grid.add_child(display)
		display.set_die(die, true)
		display.custom_minimum_size = Vector2(100, 100)
		display.pressed.connect(_on_shop_die_removal_selected.bind(die))

func _on_shop_die_removal_selected(die: Die):
	if player.gold >= player.die_removal_cost:
		player.add_gold(-player.die_removal_cost)
		player.remove_die_from_bag(die)
		player.die_removal_cost += 25
		
		dice_removal_overlay.visible = false
		_open_dice_shop_menu() # Refresh UI

func _create_forge_ui():
	forge_ui = Control.new()
	forge_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_ui.z_index = 201
	forge_ui.visible = false
	ui_layer.add_child(forge_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "The Forge"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 500)
	vbox.add_child(scroll)
	
	forge_grid = GridContainer.new()
	forge_grid.columns = 5
	forge_grid.add_theme_constant_override("h_separation", 20)
	forge_grid.add_theme_constant_override("v_separation", 20)
	forge_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(forge_grid)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(_close_forge_menu)
	vbox.add_child(back_btn)
	
	# Action Selection Overlay (Promote/Inscribe)
	forge_action_overlay = Control.new()
	forge_action_overlay.visible = false
	forge_action_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_action_overlay.z_index = 202
	ui_layer.add_child(forge_action_overlay)
	
	var act_bg = ColorRect.new()
	act_bg.color = Color(0, 0, 0, 0.95)
	act_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_action_overlay.add_child(act_bg)
	
	var act_center = CenterContainer.new()
	act_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_action_overlay.add_child(act_center)
	
	forge_action_container = VBoxContainer.new()
	forge_action_container.add_theme_constant_override("separation", 20)
	act_center.add_child(forge_action_container)
	
	# Effect Selection Overlay
	# Effect Selection Overlay
	forge_effect_overlay = Control.new()
	forge_effect_overlay.visible = false
	forge_effect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_effect_overlay.z_index = 203
	ui_layer.add_child(forge_effect_overlay)
	
	var eff_bg = ColorRect.new()
	eff_bg.color = Color(0, 0, 0, 0.95)
	eff_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_effect_overlay.add_child(eff_bg)
	
	var eff_center = CenterContainer.new()
	eff_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	forge_effect_overlay.add_child(eff_center)
	
	forge_effect_container = VBoxContainer.new()
	forge_effect_container.add_theme_constant_override("separation", 20)
	eff_center.add_child(forge_effect_container)

func _open_forge_menu():
	town_ui.visible = false
	forge_ui.visible = true
	_refresh_forge_grid()

func _close_forge_menu():
	forge_ui.visible = false
	town_ui.visible = true

func _refresh_forge_grid():
	if not player: return
	for child in forge_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var display = REWARDS_DIE_DISPLAY.instantiate()
		forge_grid.add_child(display)
		display.set_die(die, true)
		display.custom_minimum_size = Vector2(100, 100)
		display.pressed.connect(_on_forge_die_clicked.bind(die))

func _on_forge_die_clicked(die: Die):
	selected_forge_die = die
	forge_action_overlay.visible = true
	
	for child in forge_action_container.get_children():
		child.queue_free()
		
	var title = Label.new()
	title.text = "Modify Die"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	forge_action_container.add_child(title)
	
	var upgrades = die.get_meta("upgrade_count", 0)
	var promote_cost = 25 + (25 * upgrades)
	
	var promote_btn = Button.new()
	promote_btn.text = "Promote (+1 to rolls) (%dg)" % promote_cost
	promote_btn.custom_minimum_size = Vector2(300, 60)
	promote_btn.pressed.connect(_on_forge_promote_confirm.bind(die, promote_cost))
	if player.gold < promote_cost:
		promote_btn.disabled = true
	forge_action_container.add_child(promote_btn)
	
	var inscribe_label = Label.new()
	inscribe_label.text = "Inscribe Effect"
	inscribe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_action_container.add_child(inscribe_label)
	
	# Get existing effects on this die to disable duplicates
	var existing_effect_names = []
	if die.effect:
		existing_effect_names.append(die.effect.name)
	
	# Get 3 random effects suitable for this die
	var available_effects = []
	if EffectLibrary.effects_by_die_size.has(die.sides):
		available_effects = EffectLibrary.effects_by_die_size[die.sides].duplicate()
	available_effects.shuffle()
	
	for i in range(min(3, available_effects.size())):
		var template = available_effects[i]
		# Duplicate effect to ensure unique instance
		var eff = DieFaceEffect.new(template.name, template.description, template.tier, template.highlight_color)
		eff.process_effect = template.process_effect
		
		var cost = 75 * eff.tier
		var btn = Button.new()
		btn.text = "%s (%dg)\n%s" % [eff.name, cost, eff.description]
		btn.custom_minimum_size = Vector2(300, 60)
		btn.pressed.connect(_on_forge_effect_chosen.bind(eff, cost))
		
		if existing_effect_names.has(eff.name):
			btn.disabled = true
			btn.text = "%s (Owned)" % eff.name
		elif player.gold < cost:
			btn.disabled = true
			
		forge_action_container.add_child(btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): forge_action_overlay.visible = false)
	forge_action_container.add_child(cancel_btn)

func _on_forge_promote_confirm(die: Die, cost: int):
	if player.gold >= cost:
		player.add_gold(-cost)
		player.upgrade_die(die)
		forge_action_overlay.visible = false
		_refresh_forge_grid()

func _on_forge_effect_chosen(effect: DieFaceEffect, cost: int):
	if player.gold >= cost:
		player.add_gold(-cost)
		selected_forge_die.effect = effect
		forge_action_overlay.visible = false
		_refresh_forge_grid()

func _create_spell_shop_ui():
	spell_shop_ui = Control.new()
	spell_shop_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	spell_shop_ui.z_index = 201
	spell_shop_ui.visible = false
	ui_layer.add_child(spell_shop_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	spell_shop_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	spell_shop_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "Spell Shop"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	# Abilities Section
	var lbl_abilities = Label.new()
	lbl_abilities.text = "Abilities"
	lbl_abilities.add_theme_font_size_override("font_size", 32)
	vbox.add_child(lbl_abilities)
	
	spell_shop_abilities_grid = GridContainer.new()
	spell_shop_abilities_grid.columns = 3
	spell_shop_abilities_grid.add_theme_constant_override("h_separation", 20)
	spell_shop_abilities_grid.add_theme_constant_override("v_separation", 20)
	vbox.add_child(spell_shop_abilities_grid)
	
	# Charms Section
	var lbl_charms = Label.new()
	lbl_charms.text = "Charms (Permanent Buffs)"
	lbl_charms.add_theme_font_size_override("font_size", 32)
	vbox.add_child(lbl_charms)
	
	spell_shop_charms_grid = GridContainer.new()
	spell_shop_charms_grid.columns = 3
	spell_shop_charms_grid.add_theme_constant_override("h_separation", 20)
	spell_shop_charms_grid.add_theme_constant_override("v_separation", 20)
	vbox.add_child(spell_shop_charms_grid)
	
	reroll_charms_button = Button.new()
	reroll_charms_button.text = "Reroll Charms (25g)"
	reroll_charms_button.custom_minimum_size = Vector2(200, 50)
	reroll_charms_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reroll_charms_button.pressed.connect(_on_reroll_charms_pressed)
	vbox.add_child(reroll_charms_button)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(_close_spell_shop_menu)
	vbox.add_child(back_btn)

func _open_spell_shop_menu():
	town_ui.visible = false
	spell_shop_ui.visible = true
	if not spell_shop_generated:
		_generate_spell_shop_inventory()
		spell_shop_generated = true
	_update_spell_shop_ui()

func _close_spell_shop_menu():
	spell_shop_ui.visible = false
	town_ui.visible = true

func _update_spell_shop_ui():
	reroll_charms_button.text = "Reroll Charms (%dg)" % reroll_charms_cost
	if player:
		reroll_charms_button.disabled = player.gold < reroll_charms_cost

func _generate_spell_shop_inventory():
	_generate_abilities()
	_generate_charms()

func _generate_abilities():
	for child in spell_shop_abilities_grid.get_children():
		child.queue_free()
		
	var all_abilities = Utils.load_all_resources("res://resources/abilities")
	var available = []
	for res in all_abilities:
		if res is AbilityData:
			if player and not player.abilities.has(res):
				available.append(res)
	
	available.shuffle()
	for i in range(min(3, available.size())):
		var ability = available[i]
		var cost = 150
		
		var btn = Button.new()
		btn.text = "%s\n(%dg)" % [ability.title, cost]
		btn.custom_minimum_size = Vector2(150, 80)
		btn.pressed.connect(_on_buy_ability_pressed.bind(ability, cost, btn))
		
		if player and player.gold < cost:
			btn.disabled = true
			
		spell_shop_abilities_grid.add_child(btn)

func _generate_charms():
	for child in spell_shop_charms_grid.get_children():
		child.queue_free()
		
	var buff_keys = []
	if StatusLibrary.statuses:
		for key in StatusLibrary.statuses:
			var status = StatusLibrary.statuses[key]
			if not status.is_debuff:
				buff_keys.append(key)
	
	buff_keys.shuffle()
	for i in range(min(3, buff_keys.size())):
		var key = buff_keys[i]
		var status = StatusLibrary.statuses[key]
		var cost = 100
		
		var btn = Button.new()
		btn.text = "%s\n(%dg)" % [status.status_name, cost]
		btn.custom_minimum_size = Vector2(150, 80)
		btn.tooltip_text = status.description
		btn.pressed.connect(_on_buy_charm_pressed.bind(key, cost, btn))
		
		if player and player.gold < cost:
			btn.disabled = true
			
		spell_shop_charms_grid.add_child(btn)

func _on_buy_ability_pressed(ability, cost, btn):
	if player and player.gold >= cost:
		player.add_gold(-cost)
		player.add_ability(ability)
		btn.disabled = true
		btn.text = "Sold"
		_update_spell_shop_ui()

func _on_buy_charm_pressed(status_id, cost, btn):
	if player and player.gold >= cost:
		player.add_gold(-cost)
		player.apply_duration_status(status_id, -1)
		btn.disabled = true
		btn.text = "Sold"
		_update_spell_shop_ui()

func _on_reroll_charms_pressed():
	if player and player.gold >= reroll_charms_cost:
		player.add_gold(-reroll_charms_cost)
		reroll_charms_cost += 25
		_generate_charms()
		_update_spell_shop_ui()

func _process(delta):
	# Animate water UVs
	if visible:
		var time = Time.get_ticks_msec() / 1000.0
		var _offset = Vector2(time * 0.05, time * 0.02)
		for child in map_container.get_children():
			if child is TriangleButton:
				for sub in child.get_children():
					if sub is Polygon2D and sub.texture == water_texture:
						# Shift UVs
						var uvs = sub.uv
						for i in range(uvs.size()):
							uvs[i] += Vector2(delta * 0.1, delta * 0.05)
						sub.uv = uvs
	

func generate_new_map():
	grid_data.clear()
	current_node = null
	explored_nodes.clear()
	boss_room_nodes.clear()
	decayed_nodes.clear()
	
	# 1. Initialize Grid
	for child in map_container.get_children():
		if child != player_icon:
			child.queue_free()
			
	turns_left = 21
	var height = triangle_size * sqrt(3) / 2.0
	var total_grid_width = (grid_width * triangle_size / 2.0) + (triangle_size / 2.0)
	map_base_size = Vector2(total_grid_width, grid_height * height)
	# map_container.custom_minimum_size is set in _fit_map_to_screen
	var x_offset = 0.0
	var y_offset = 0.0
	
	for row in range(grid_height):
		for col in range(grid_width):
			var points_up = (row + col) % 2 == 0
			var x_pos = x_offset + col * (triangle_size / 2.0) + (triangle_size / 2.0)
			var y_pos = 0.0
			if points_up:
				y_pos = y_offset + row * height + (height * 2.0 / 3.0)
			else:
				y_pos = y_offset + row * height + (height / 3.0)
			
			var node = {
				"row": row,
				"col": col,
				"type": "normal", # Default
				"pos": Vector2(x_pos, y_pos),
				"points_up": points_up,
				"cleared": false,
				"defeated": false,
				"button": null
			}
			grid_data[Vector2(row, col)] = node

	# 2. Place Start (Bottom Center)
	var start_row = grid_height - 1
	var start_col = int(grid_width / 2.0)
	var start_node = grid_data[Vector2(start_row, start_col)]
	start_node.type = "start"
	current_node = start_node
	start_node.cleared = true

	# 3. Place Town (Roughly Center)
	var town_row = randi_range(int(grid_height * 0.4), int(grid_height * 0.6))
	var town_col = randi_range(int(grid_width * 0.4), int(grid_width * 0.6))
	var town_nodes = []
	for i in range(3):
		var n = grid_data[Vector2(town_row, town_col + i)]
		n.type = "town"
		town_nodes.append(n)

	# 3b. Create Path from Start to Town
	var path_to_town = _find_path_ignoring_terrain(start_node, town_nodes[1])
	for n in path_to_town:
		if n.type == "normal":
			n.type = "safe_path"

	# 4. Place Goblin Camp (2 triangles, near water, no mountains)
	# We pick a spot first, then enforce terrain constraints later
	var valid_goblin_starts = _get_nodes_in_range(town_nodes, 6, 12)
	var goblin_nodes = _pick_random_cluster(2, ["start", "town", "safe_path"], valid_goblin_starts)
	for n in goblin_nodes: n.type = "goblin_camp"
	
	# 5. Place Dragon's Roost (2 triangles, near mountains)
	var valid_dragon_starts = _get_nodes_in_range(town_nodes, 6, 12)
	var dragon_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "safe_path"], valid_dragon_starts)
	for n in dragon_nodes: n.type = "dragon_roost"

	# 6. Place Crypt (2 triangles, no water in 2 tile radius)
	var valid_crypt_starts = _get_nodes_in_range(town_nodes, 6, 12)
	var crypt_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost", "safe_path"], valid_crypt_starts)
	for n in crypt_nodes: n.type = "crypt"

	# 7. Place Dwarven Forge (2 triangles, 5 mountains in 2 radius, 1 touching)
	var valid_forge_starts = _get_nodes_in_range(town_nodes, 6, 12)
	var dwarven_forge_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost", "crypt", "safe_path"], valid_forge_starts)
	for n in dwarven_forge_nodes: n.type = "dwarven_forge"

	# 7.5 Place Boss Room (2 triangles, near corners)
	var corners = [
		grid_data[Vector2(0, 0)],
		grid_data[Vector2(0, grid_width - 1)],
		grid_data[Vector2(grid_height - 1, 0)],
		grid_data[Vector2(grid_height - 1, grid_width - 1)]
	]
	var valid_boss_starts = []
	for corner in corners:
		var near_corner = _get_nodes_in_radius([corner], 3)
		for n in near_corner:
			valid_boss_starts.append(n)
	var generated_boss_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge", "safe_path"], valid_boss_starts)
	
	# Fallback: If corner placement fails, place randomly anywhere valid
	if generated_boss_nodes.is_empty():
		print("Warning: Could not place Boss Room near corners. Placing randomly.")
		generated_boss_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge", "safe_path"])
	
	for n in generated_boss_nodes: n.type = "final_boss"
	self.boss_room_nodes = generated_boss_nodes

	# 8. Generate Terrain & Enforce Constraints
	var goblin_zone = _get_nodes_in_radius(goblin_nodes, 2)
	var dragon_zone = _get_nodes_in_radius(dragon_nodes, 2)
	var crypt_zone = _get_nodes_in_radius(crypt_nodes, 2)
	var dwarven_forge_zone = _get_nodes_in_radius(dwarven_forge_nodes, 2)
	
	# Fill constraints first
	# Note: Boss Room has no specific terrain constraints other than location
	# Goblin: Need 1 water (clump of 3)
	# Ensure we don't place water in the crypt zone
	var water_candidates = goblin_zone.filter(func(n): return n.type == "normal" and not n in crypt_zone)
	if not water_candidates.is_empty():
		_grow_clump(water_candidates.pick_random(), "water", 3, 4, crypt_zone)
	
	# Dragon: Need 4 mountains (clump of 4)
	var mountain_candidates = dragon_zone.filter(func(n): return n.type == "normal")
	if not mountain_candidates.is_empty():
		_grow_clump(mountain_candidates.pick_random(), "mountain", 4, 5, goblin_zone, dragon_zone)
		
	# Dwarven Forge: Need 1 touching mountain, 5 total in radius 2
	var forge_neighbors = []
	for fn in dwarven_forge_nodes:
		for n in get_neighbors(fn):
			if n.type == "normal" and not n in forge_neighbors:
				forge_neighbors.append(n)
	
	if not forge_neighbors.is_empty():
		_grow_clump(forge_neighbors.pick_random(), "mountain", 5, 7, goblin_zone, dwarven_forge_zone)

	# Random fill rest
	var keys = grid_data.keys()
	keys.shuffle()
	for pos in keys:
		var node = grid_data[pos]
		if node.type != "normal": continue
		
		# Goblin constraint: No mountains in radius 2
		if node in goblin_zone:
			if randf() < 0.05: _grow_clump(node, "water", 3, 5, crypt_zone)
			continue
			
		var rand = randf()
		if rand < 0.04: _grow_clump(node, "mountain", 3, 6, goblin_zone)
		elif rand < 0.08: _grow_clump(node, "water", 3, 6, crypt_zone)

	# Restore safe path
	for pos in grid_data:
		if grid_data[pos].type == "safe_path":
			grid_data[pos].type = "road"

	# 9. Ensure Connectivity
	_ensure_connectivity()

	draw_map()
	update_fog()
	start_turn()

func draw_map():
	special_visuals.clear()
	var height = triangle_size * sqrt(3) / 2.0
	var crypt_nodes_for_visuals = []
	var goblin_nodes_for_visuals = []
	var dragon_nodes_for_visuals = []
	var town_nodes_for_visuals = []
	var dwarven_forge_nodes_for_visuals = []
	var boss_room_nodes_for_visuals = []
	
	var shadow_container = CanvasGroup.new()
	shadow_container.modulate = Color(1, 1, 1, 0.3)
	map_container.add_child(shadow_container)
	map_container.move_child(shadow_container, 0)
	
	# Full Path Line (Red)
	full_path_line = Line2D.new()
	full_path_line.width = 5
	full_path_line.default_color = Color.RED
	full_path_line.z_index = 49
	map_container.add_child(full_path_line)
	
	# Path Line
	path_line = Line2D.new()
	path_line.width = 5
	path_line.default_color = Color.WHITE
	path_line.z_index = 50
	map_container.add_child(path_line)
	
	# Distance Label
	distance_label = Label.new()
	distance_label.z_index = 100
	distance_label.add_theme_font_size_override("font_size", 24)
	distance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	distance_label.add_theme_constant_override("outline_size", 4)
	distance_label.visible = false
	map_container.add_child(distance_label)
	
	# Full Distance Label
	full_distance_label = Label.new()
	full_distance_label.z_index = 100
	full_distance_label.add_theme_font_size_override("font_size", 24)
	full_distance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	full_distance_label.add_theme_constant_override("outline_size", 4)
	full_distance_label.visible = false
	map_container.add_child(full_distance_label)
	
	for pos in grid_data:
		var node = grid_data[pos]
		var btn = TriangleButton.new()
		btn.triangle_size = triangle_size
		btn.points_up = node.points_up
		btn.size = Vector2(triangle_size, triangle_size * sqrt(3) / 2.0)
		btn.position = node.pos - btn.size / 2.0
		btn.flat = true
		btn.self_modulate = Color(1, 1, 1, 0) # Ensure button background is invisible
		var center_offset = btn.size / 2.0
		
		var vertices = PackedVector2Array()
		if node.points_up:
			vertices = PackedVector2Array([
				Vector2(0, -2.0 / 3.0 * height),
				Vector2(triangle_size / 2.0, 1.0 / 3.0 * height),
				Vector2(-triangle_size / 2.0, 1.0 / 3.0 * height)
			])
		else:
			vertices = PackedVector2Array([
				Vector2(0, 2.0 / 3.0 * height),
				Vector2(-triangle_size / 2.0, -1.0 / 3.0 * height),
				Vector2(triangle_size / 2.0, -1.0 / 3.0 * height)
			])
		
		# Create base polygon for all nodes
		var poly = Polygon2D.new()
		poly.polygon = vertices
		poly.position = center_offset
		
		# Calculate UVs based on world position for seamless tiling
		var uvs = PackedVector2Array()
		for v in vertices:
			uvs.append((node.pos + v) / 128.0)
		poly.uv = uvs
		
		btn.add_child(poly)
		node["bg"] = poly
		
		if node.type == "mountain":
			var shadow = Polygon2D.new()
			shadow.polygon = vertices
			shadow.color = Color.BLACK
			shadow.position = node.pos + Vector2(-10, 10)
			shadow_container.add_child(shadow)
			node["shadow"] = shadow

		if node.type == "mountain":
			poly.color = Color.WHITE
			poly.texture = mountain_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Add shadow to make it look pointy
			var shadow = Polygon2D.new()
			var s_verts = PackedVector2Array()
			if node.points_up:
				s_verts.append(vertices[0]) # Top
				s_verts.append(vertices[2]) # Bottom Left
				s_verts.append(Vector2(0, 1.0 / 3.0 * height)) # Bottom Mid
			else:
				s_verts.append(vertices[0]) # Bottom
				s_verts.append(vertices[1]) # Top Left
				s_verts.append(Vector2(0, -1.0 / 3.0 * height)) # Top Mid
			shadow.polygon = s_verts
			shadow.color = Color(0, 0, 0, 0.3)
			shadow.position = center_offset
			btn.add_child(shadow)
		elif node.type == "water":
			poly.color = Color.WHITE
			poly.texture = water_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		elif node.type == "crypt":
			poly.color = Color(0.5, 0.5, 0.55, 1.0) # Gray fill
			crypt_nodes_for_visuals.append(node)
		elif node.type == "goblin_camp":
			poly.color = Color(0.6, 0.8, 0.6, 1.0) # Pale green
			goblin_nodes_for_visuals.append(node)
		elif node.type == "dragon_roost":
			poly.color = Color(0.95, 0.75, 0.3, 1.0) # Pale yellowish orange
			dragon_nodes_for_visuals.append(node)
		elif node.type == "town":
			poly.color = Color(0.4, 0.9, 0.4, 1.0) # Light Green
			town_nodes_for_visuals.append(node)
		elif node.type == "dwarven_forge":
			poly.color = Color(0.55, 0.27, 0.07, 1.0) # Bronze/SaddleBrown
			dwarven_forge_nodes_for_visuals.append(node)
		elif node.type == "final_boss":
			poly.color = Color(0.5, 0.0, 0.5, 1.0) # Purple
			boss_room_nodes_for_visuals.append(node)
		
		if node.type == "crypt" or node.type == "goblin_camp" or node.type == "dragon_roost" or node.type == "town" or node.type == "mountain" or node.type == "dwarven_forge" or node.type == "final_boss":
				# Draw outlines only on edges NOT shared with another node of the same type
				var r = node.row
				var c = node.col
				var neighbors_check = []
				var edges_indices = []
				
				if node.points_up:
					# Edges: Right (0-1), Bottom (1-2), Left (2-0)
					neighbors_check = [Vector2(r, c+1), Vector2(r+1, c), Vector2(r, c-1)]
					edges_indices = [[0, 1], [1, 2], [2, 0]]
				else:
					# Edges: Left (0-1), Top (1-2), Right (2-0)
					neighbors_check = [Vector2(r, c-1), Vector2(r-1, c), Vector2(r, c+1)]
					edges_indices = [[0, 1], [1, 2], [2, 0]]
				
				for i in range(3):
					var n_pos = neighbors_check[i]
					# Draw edge if neighbor is NOT the same type (or doesn't exist)
					if not grid_data.has(n_pos) or grid_data[n_pos].type != node.type:
						var line = Line2D.new()
						line.points = PackedVector2Array([vertices[edges_indices[i][0]], vertices[edges_indices[i][1]]])
						line.width = 3.0
						if node.type == "crypt":
							line.default_color = Color(0.2, 0.2, 0.25, 1.0) # Darker grey outline
						elif node.type == "goblin_camp":
							line.default_color = Color(0.4, 0.25, 0.1, 1.0) # Brown outline
						elif node.type == "dragon_roost":
							line.default_color = Color.CRIMSON # Crimson red border
						elif node.type == "town":
							line.default_color = Color(0.1, 0.4, 0.1, 1.0) # Dark green border
						elif node.type == "mountain":
							line.default_color = Color(0.2, 0.2, 0.2, 1.0) # Dark grey border
						elif node.type == "dwarven_forge":
							line.default_color = Color(0.3, 0.1, 0.0, 1.0) # Dark Rust border
						elif node.type == "final_boss":
							line.default_color = Color.BLACK # Black border
						line.position = center_offset
						btn.add_child(line)
		
		# Defeated Visual (X)
		if node.type in ["crypt", "goblin_camp", "dragon_roost", "dwarven_forge", "rare_combat", "boss", "final_boss"]:
			var x_node = Node2D.new()
			x_node.name = "DefeatedX"
			x_node.visible = node.get("defeated", false)
			x_node.position = center_offset
			x_node.z_index = 25
			
			var l1 = Line2D.new()
			l1.points = [Vector2(-25, -25), Vector2(25, 25)]
			l1.width = 6
			l1.default_color = Color(0.9, 0.1, 0.1, 0.8)
			x_node.add_child(l1)
			
			var l2 = Line2D.new()
			l2.points = [Vector2(25, -25), Vector2(-25, 25)]
			l2.width = 6
			l2.default_color = Color(0.9, 0.1, 0.1, 0.8)
			x_node.add_child(l2)
			
			btn.add_child(x_node)
			node["defeated_visual"] = x_node

		elif node.type == "start" or node.type == "road":
			poly.color = Color.WHITE
			poly.texture = dirt_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Add faint outline to distinguish tiles
			var outline = Line2D.new()
			var outline_points = vertices.duplicate()
			outline_points.append(vertices[0])
			outline.points = outline_points
			outline.width = 1.0
			outline.default_color = Color(0.3, 0.2, 0.1, 0.3)
			outline.position = center_offset
			btn.add_child(outline)
		elif node.type == "normal":
			poly.color = Color.WHITE
			poly.texture = grass_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Add faint outline to distinguish tiles
			var outline = Line2D.new()
			var outline_points = vertices.duplicate()
			outline_points.append(vertices[0])
			outline.points = outline_points
			outline.width = 1.0
			outline.default_color = Color(0.1, 0.2, 0.1, 0.3)
			outline.position = center_offset
			btn.add_child(outline)
		
		btn.pressed.connect(_on_node_pressed.bind(node))
		btn.mouse_entered.connect(_on_node_hover.bind(node))
		btn.mouse_exited.connect(_on_node_exit)
		node["button"] = btn
		map_container.add_child(btn)
		
	# Draw Crypt Icon and Title centered
	if not crypt_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in crypt_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= crypt_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/crypt_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Crypt"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["crypt"] = {"icon": icon, "label": lbl, "nodes": crypt_nodes_for_visuals}
		
	# Draw Goblin Camp Icon and Title centered
	if not goblin_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in goblin_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= goblin_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/goblin_camp_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Goblin Camp"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["goblin_camp"] = {"icon": icon, "label": lbl, "nodes": goblin_nodes_for_visuals}
		
	# Draw Dragon Roost Icon and Title centered
	if not dragon_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in dragon_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= dragon_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/dragon_roost_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Dragon Roost"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["dragon_roost"] = {"icon": icon, "label": lbl, "nodes": dragon_nodes_for_visuals}
		
	# Draw Town Icon and Title centered
	if not town_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in town_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= town_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/town_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Town"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["town"] = {"icon": icon, "label": lbl, "nodes": town_nodes_for_visuals}
		
	# Draw Dwarven Forge Icon and Title centered
	if not dwarven_forge_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in dwarven_forge_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= dwarven_forge_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/dwarven_forge_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Dwarven Forge"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["dwarven_forge"] = {"icon": icon, "label": lbl, "nodes": dwarven_forge_nodes_for_visuals}

	# Draw Boss Room Icon and Title centered
	if not boss_room_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in boss_room_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= boss_room_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/boss_encounter.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(50, 50)
		icon.pivot_offset = icon.size / 2.0
		icon.position = center_pos - (icon.size / 2.0)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Boss Room"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		lbl.size = Vector2(200, 30)
		lbl.pivot_offset = lbl.size / 2.0
		var offset_y = 28 * current_scale_factor
		icon.position = center_pos - (icon.size / 2.0)
		lbl.position = center_pos - (lbl.size / 2.0) - Vector2(0, offset_y)
		lbl.visible = false
		lbl.z_index = 21
		map_container.add_child(lbl)
		special_visuals["final_boss"] = {"icon": icon, "label": lbl, "nodes": boss_room_nodes_for_visuals}
		
	_fit_map_to_screen()
	update_visuals()

func update_visuals():
	if not current_node: return
	player_icon.position = current_node.pos - (player_icon.size / 2.0)
	player_icon.z_index = 100
	
	for pos in grid_data:
		var node = grid_data[pos]
		var btn = node["button"]
		
		# Impassible terrain
		var is_known = explored_nodes.has(pos)
		if is_known and (node.type == "mountain" or node.type == "water"):
			btn.disabled = true
			continue
			
		if node == current_node:
			btn.disabled = true
		else:
			btn.disabled = false
			if node.has("defeated_visual"):
				node["defeated_visual"].visible = node.get("defeated", false)
	
	# _center_view_on_player() is no longer needed as map fits screen

func is_neighbor(node_a, node_b):
	var r1 = node_a.row
	var c1 = node_a.col
	var r2 = node_b.row
	var c2 = node_b.col
	
	if r1 == r2 and abs(c1 - c2) == 1:
		return true
		
	if node_a.points_up:
		if r2 == r1 + 1 and c2 == c1: return true
	else:
		if r2 == r1 - 1 and c2 == c1: return true
		
	return false

func get_neighbors(node):
	var neighbors = []
	var r = node.row
	var c = node.col
	
	var candidates = [
		Vector2(r, c - 1),
		Vector2(r, c + 1)
	]
	if node.points_up:
		candidates.append(Vector2(r + 1, c))
	else:
		candidates.append(Vector2(r - 1, c))
		
	for cand in candidates:
		if grid_data.has(cand):
			neighbors.append(grid_data[cand])
	return neighbors

func _pick_random_cluster(cluster_size: int, excluded_types: Array, valid_starts: Array = []) -> Array:
	var attempts = 0
	while attempts < 100:
		attempts += 1
		var start_node
		
		if valid_starts.is_empty():
			var start_pos = Vector2(randi() % grid_height, randi() % grid_width)
			if not grid_data.has(start_pos): continue
			start_node = grid_data[start_pos]
		else:
			start_node = valid_starts.pick_random()
		
		if start_node.type in excluded_types: continue
		
		var cluster = [start_node]
		var neighbors = get_neighbors(start_node)
		neighbors.shuffle()
		
		for n in neighbors:
			if cluster.size() >= cluster_size: break
			if n.type not in excluded_types:
				cluster.append(n)
		
		if cluster.size() == cluster_size:
			return cluster
	return []

func _get_visible_nodes_with_los(center_nodes: Array, radius: int) -> Array:
	var result = {}
	var queue = []
	for n in center_nodes:
		queue.append({"node": n, "dist": 0})
		result[n] = true
		
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		# Mountains block line of sight (cannot see PAST them)
		# We can see the mountain itself, but we don't expand from it.
		var is_start_node = current.node in center_nodes
		
		if current.node.type == "mountain" and not is_start_node:
			continue

		if current.dist >= radius: continue
		
		var neighbors = get_neighbors(current.node)
		for n in neighbors:
			if not result.has(n):
				result[n] = true
				queue.append({"node": n, "dist": current.dist + 1})
				
	return result.keys()

func _get_nodes_in_radius(center_nodes: Array, radius: int) -> Array:
	var result = {}
	var queue = []
	for n in center_nodes:
		queue.append({"node": n, "dist": 0})
		result[n] = true
		
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		if current.dist >= radius: continue
		
		var neighbors = get_neighbors(current.node)
		for n in neighbors:
			if not result.has(n):
				result[n] = true
				queue.append({"node": n, "dist": current.dist + 1})
				
	return result.keys()

func _get_nodes_in_range(center_nodes: Array, min_dist: int, max_dist: int) -> Array:
	var nodes_in_max = _get_nodes_in_radius(center_nodes, max_dist)
	var nodes_in_min = _get_nodes_in_radius(center_nodes, min_dist - 1)
	
	var result = []
	for n in nodes_in_max:
		if not n in nodes_in_min:
			result.append(n)
	return result

func _grow_clump(start_node, type, min_size, max_size, forbidden_zone = [], allowed_zone = []):
	if start_node.type != "normal": return
	if not forbidden_zone.is_empty() and start_node in forbidden_zone: return
	if not allowed_zone.is_empty() and not start_node in allowed_zone: return
	
	var clump = [start_node]
	start_node.type = type
	
	var queue = [start_node]
	var target_size = randi_range(min_size, max_size)
	
	while clump.size() < target_size and not queue.is_empty():
		var curr = queue.pop_front()
		var neighbors = get_neighbors(curr)
		neighbors.shuffle()
		
		for n in neighbors:
			if clump.size() >= target_size: break
			if n.type == "normal":
				if not forbidden_zone.is_empty() and n in forbidden_zone: continue
				if not allowed_zone.is_empty() and not n in allowed_zone: continue
				
				n.type = type
				clump.append(n)
				queue.append(n)

func _ensure_connectivity():
	# 1. Find all walkable nodes
	var walkable_nodes = []
	var start_node = null
	for pos in grid_data:
		var n = grid_data[pos]
		if n.type != "mountain" and n.type != "water":
			walkable_nodes.append(n)
			if n.type == "start":
				start_node = n
	
	if not start_node: return
	
	# 2. Flood fill from start
	var visited = {start_node: true}
	var queue = [start_node]
	var head = 0
	
	while head < queue.size():
		var curr = queue[head]
		head += 1
		for n in get_neighbors(curr):
			if n.type != "mountain" and n.type != "water" and not visited.has(n):
				visited[n] = true
				queue.append(n)
	
	# 3. If disconnected, carve path to nearest unvisited walkable node
	var unvisited = []
	for n in walkable_nodes:
		if not visited.has(n):
			unvisited.append(n)
			
	while not unvisited.is_empty():
		# Find closest pair (visited_node, unvisited_node)
		# This is expensive O(N*M), but grid is small (360 nodes).
		# Optimization: Just pick one unvisited and path to Start ignoring terrain.
		var target = unvisited[0]
		var path = _find_path_ignoring_terrain(start_node, target)
		
		for n in path:
			if n.type == "mountain" or n.type == "water":
				n.type = "normal" # Carve path
			if not visited.has(n):
				visited[n] = true
				# Add neighbors to queue to continue flood fill from new path
				queue.append(n)
		
		# Resume flood fill to update visited set
		while head < queue.size():
			var curr = queue[head]
			head += 1
			for n in get_neighbors(curr):
				if n.type != "mountain" and n.type != "water" and not visited.has(n):
					visited[n] = true
					queue.append(n)
		
		# Re-evaluate unvisited
		unvisited = []
		for n in walkable_nodes:
			if not visited.has(n):
				unvisited.append(n)

func _find_path_ignoring_terrain(from_node, to_node):
	# BFS for shortest path
	var came_from = {}
	var queue = [from_node]
	came_from[from_node] = null
	
	while not queue.is_empty():
		var processing_node = queue.pop_front()
		if processing_node == to_node: break
		
		for n in get_neighbors(processing_node):
			if not came_from.has(n):
				came_from[n] = processing_node
				queue.append(n)
	
	# Reconstruct
	var path = []
	var curr = to_node
	while curr != null:
		path.append(curr)
		curr = came_from.get(curr)
	return path

func find_path(from_node, to_node):
	# BFS for pathfinding respecting terrain
	var queue = [from_node]
	var came_from = {from_node: null}
	
	while not queue.is_empty():
		var processing_node = queue.pop_front()
		if processing_node == to_node:
			break
		
		for next in get_neighbors(processing_node):
			var is_known = explored_nodes.has(Vector2(next.row, next.col))
			# Only treat as obstacle if we know it is one
			if is_known and (next.type == "mountain" or next.type == "water"):
				continue

			if not came_from.has(next):
				came_from[next] = processing_node
				queue.append(next)
	
	if not came_from.has(to_node):
		return []
		
	var path = []
	var current = to_node
	while current != null:
		path.append(current)
		current = came_from[current]
	path.reverse()
	return path

func get_quest_directions() -> Dictionary:
	var directions = {}
	var town_center = Vector2.ZERO
	var town_count = 0
	
	# Calculate centers
	var type_centers = {}
	var type_counts = {}
	
	for pos in grid_data:
		var node = grid_data[pos]
		if node.type == "town":
			town_center += node.pos
			town_count += 1
		elif node.type in ["goblin_camp", "crypt", "dragon_roost", "dwarven_forge", "final_boss"]:
			if not type_centers.has(node.type):
				type_centers[node.type] = Vector2.ZERO
				type_counts[node.type] = 0
			type_centers[node.type] += node.pos
			type_counts[node.type] += 1
			
	if town_count > 0:
		town_center /= town_count
		
	for type in type_centers:
		var center = type_centers[type] / type_counts[type]
		var dir_vec = center - town_center
		
		var angle = dir_vec.angle()
		var octant = round(angle / (PI / 4.0))
		var dir_str = "Unknown"
		match int(octant):
			0: dir_str = "East"
			1: dir_str = "South East"
			2: dir_str = "South"
			3: dir_str = "South West"
			4, -4: dir_str = "West"
			-1: dir_str = "North East"
			-2: dir_str = "North"
			-3: dir_str = "North West"
		
		directions[type] = dir_str
		
	return directions

func update_quest_log(active_quests: Array):
	for child in quest_log_container.get_children():
		child.queue_free()
		
	if active_quests.is_empty(): return
	
	var directions = get_quest_directions()
	
	for q in active_quests:
		var lbl = Label.new()
		var dir = directions.get(q.id, "")
		var text = "- %s" % q.name
		if dir != "":
			text += " (%s)" % dir
		lbl.text = text
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_font_size_override("font_size", int(16 * current_scale_factor))
		lbl.add_theme_constant_override("outline_size", int(4 * current_scale_factor))
		quest_log_container.add_child(lbl)

func start_turn():
	if is_rolling: return
	
	if current_roll_overlay and is_instance_valid(current_roll_overlay):
		current_roll_overlay.queue_free()
	
	turns_left -= 1
	
	var main_game = get_tree().current_scene as MainGame
	if main_game and main_game.turns_label:
		main_game.turns_label.text = "Turns: %d" % max(0, turns_left)
		
		if turns_left <= 5:
			var t = 1.0 - (float(turns_left) / 5.0)
			main_game.turns_label.modulate = Color.WHITE.lerp(Color(1, 0.2, 0.2), t)
		else:
			main_game.turns_label.modulate = Color.WHITE

	if turns_left <= 0:
		await _process_decay()
		if not visible: return

	roll_id += 1
	var my_roll_id = roll_id

	# Roll Animation
	var d1 = Die.new(4)
	var d2 = Die.new(4)
	d1.roll()
	d2.roll()
	
	pending_roll_result = d1.result_value + d2.result_value
	is_rolling = true
	
	# Create visual displays for the roll
	var roll_overlay = Control.new()
	current_roll_overlay = roll_overlay
	roll_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.z_index = 200 # Ensure it's on top
	add_child(roll_overlay)
	
	var center_cont = CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.add_child(center_cont)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	center_cont.add_child(hbox)
	
	var disp = DIE_RENDERER_SCENE.instantiate()
	disp.custom_minimum_size = Vector2(800, 800)
	hbox.add_child(disp)
	
	# Add 2 d4s
	disp.add_die(0, 4, 0)
	disp.add_die(1, 4, 0)
	
	disp.roll_all()

	# Animate dice appearing
	disp.scale = Vector2.ZERO
	
	var tween = create_tween()
	current_tween = tween
	tween.tween_property(disp, "scale", Vector2(1.5, 1.5), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	if not is_rolling or roll_id != my_roll_id: return
	
	# Wait for physics results
	var results_map = {}
	var on_finished = func(id, val): 
		results_map[id] = val
		# Update pending result immediately if we have all dice, to prevent race condition on skip
		if results_map.size() == 2:
			pending_roll_result = results_map.get(0, 0) + results_map.get(1, 0)
			
	disp.roll_finished.connect(on_finished)
	
	var timeout_frames = 600 # 10 seconds safety timeout
	while results_map.size() < 2 and is_rolling and roll_id == my_roll_id and timeout_frames > 0:
		await get_tree().process_frame
		timeout_frames -= 1
	
	if timeout_frames <= 0 and is_rolling:
		print("Dice roll timed out in TriangleMapScreen")
		if not results_map.has(0): results_map[0] = 1
		if not results_map.has(1): results_map[1] = 1
		
	if not is_rolling or roll_id != my_roll_id: return
	
	# Sync pending result so skipping logic has the right value
	var val1 = results_map.get(0, 1)
	var val2 = results_map.get(1, 1)
	pending_roll_result = val1 + val2
	
	# Small pause to let the player see the result on the dice
	var pause_tween = create_tween()
	current_tween = pause_tween
	pause_tween.tween_interval(0.5)
	await pause_tween.finished
	if not is_rolling or roll_id != my_roll_id: return

	# --- Floating Numbers Animation ---
	var label1 = Label.new()
	var label2 = Label.new()
	temp_labels = [label1, label2]
	var values = [val1, val2]
	
	for i in range(2):
		var lbl = temp_labels[i]
		lbl.text = str(values[i])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 64)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 12)
		lbl.modulate.a = 0.0
		lbl.z_index = 300 # Above overlay
		add_child(lbl)
	
	# Wait for layout
	await get_tree().process_frame
	if not is_rolling or roll_id != my_roll_id: return

	label1.pivot_offset = label1.size / 2.0
	label2.pivot_offset = label2.size / 2.0
	
	# Position labels at the dice center
	label1.global_position = disp.get_die_screen_position(0) - label1.pivot_offset
	label2.global_position = disp.get_die_screen_position(1) - label2.pivot_offset
	
	var anim_tween = create_tween()
	current_tween = anim_tween
	anim_tween.set_parallel(true)
	
	# 1. Fade OUT the dice display & Fade IN the numbers + Float Up
	anim_tween.tween_property(disp, "modulate:a", 0.0, 0.4)
	
	for lbl in temp_labels:
		anim_tween.tween_property(lbl, "modulate:a", 1.0, 0.3)
		anim_tween.tween_property(lbl, "global_position:y", lbl.global_position.y - 80, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	await anim_tween.finished
	if not is_rolling or roll_id != my_roll_id: return
	
	# 2. Move numbers to Player Movement label
	var move_tween = create_tween()
	current_tween = move_tween
	move_tween.set_parallel(true)
	
	var target_center = moves_label.global_position + moves_label.size / 2.0
	
	for i in range(2):
		var lbl = temp_labels[i]
		var delay = i * 0.1
		var target_pos = target_center - lbl.pivot_offset
		
		# Move to player's counter
		move_tween.tween_property(lbl, "global_position", target_pos, 0.5).set_delay(delay).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		# Shrink as it arrives
		move_tween.tween_property(lbl, "scale", Vector2(0.5, 0.5), 0.5).set_delay(delay)
		# Fade out at the end
		move_tween.tween_property(lbl, "modulate:a", 0.0, 0.2).set_delay(delay + 0.3)
	
	await move_tween.finished
	
	for lbl in temp_labels:
		if is_instance_valid(lbl): lbl.queue_free()
	temp_labels.clear()
	
	if not is_rolling or roll_id != my_roll_id: return
	
	# Apply final value
	moves_remaining = val1 + val2
	moves_label.text = "%d" % moves_remaining
	
	# Fade out overlay background (dice are already gone)
	var out_tween = create_tween()
	current_tween = out_tween
	out_tween.tween_property(roll_overlay, "modulate:a", 0.0, 0.3)
	await out_tween.finished
	if not is_rolling or roll_id != my_roll_id: return
	
	roll_overlay.queue_free()
	current_roll_overlay = null
	is_rolling = false

func _process_decay():
	var new_decayed = []
	
	if decayed_nodes.is_empty():
		# Initial Decay: 3 furthest tiles from boss room
		if boss_room_nodes.is_empty(): return
		
		# Calculate distances from boss room
		var distances = {}
		var queue = []
		for bn in boss_room_nodes:
			queue.append({"node": bn, "dist": 0})
			distances[bn] = 0
			
		var head = 0
		while head < queue.size():
			var curr = queue[head]
			head += 1
			
			var neighbors = get_neighbors(curr.node)
			for n in neighbors:
				if not distances.has(n):
					distances[n] = curr.dist + 1
					queue.append({"node": n, "dist": curr.dist + 1})
		
		# Sort nodes by distance descending
		var sorted_nodes = distances.keys()
		sorted_nodes.sort_custom(func(a, b): return distances[a] > distances[b])
		
		# Pick top 3 valid nodes (not mountains/water/boss)
		var count = 0
		for n in sorted_nodes:
			if n.type != "final_boss":
				new_decayed.append(n)
				count += 1
				if count >= 3: break
	else:
		# Spread Decay: All tiles 3 tiles away from existing decayed
		var spread_sources = decayed_nodes.keys()
		var candidates = _get_nodes_in_radius(spread_sources, 3)
		
		for n in candidates:
			if not decayed_nodes.has(n) and n.type != "final_boss":
				new_decayed.append(n)

	# Apply Decay
	for n in new_decayed:
		decayed_nodes[n] = true
		_animate_decay(n)
	
	if not new_decayed.is_empty():
		await get_tree().create_timer(1.0).timeout
		
	# Check if player is caught
	if current_node and decayed_nodes.has(current_node):
		print("Player caught in decay! Triggering boss fight.")
		# Find a boss room node to trigger the encounter
		var boss_node = null
		if not boss_room_nodes.is_empty():
			boss_node = boss_room_nodes[0]
		else:
			# Fallback data if boss room nodes are missing
			boss_node = {"type": "final_boss", "pos": Vector2.ZERO, "row": 0, "col": 0}
		
		if boss_node:
			emit_signal("node_selected", boss_node)

func _animate_decay(node):
	if not node.has("bg") or not node.bg: return
	
	var poly = node.bg
	var tween = create_tween()
	
	# Flash purple then turn dark
	tween.tween_property(poly, "color", Color(0.8, 0.0, 0.8), 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(poly, "color", Color(0.1, 0.0, 0.1), 0.5).set_trans(Tween.TRANS_SINE)
	
	# Add a visual marker if needed, or just rely on color
	# Do NOT change node.type here, as it breaks MainGame logic. Rely on decayed_nodes set.

func _on_end_turn_pressed():
	start_turn()

func get_best_path_to(target_node):
	var source_nodes = [current_node]
	if current_node and current_node.type in ["town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge", "final_boss"]:
		source_nodes = []
		for pos in grid_data:
			var n = grid_data[pos]
			if n.type == current_node.type:
				source_nodes.append(n)

	var target_nodes = [target_node]
	if target_node.type in ["town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge", "final_boss"]:
		target_nodes = []
		for pos in grid_data:
			var n = grid_data[pos]
			if n.type == target_node.type:
				target_nodes.append(n)
	
	var best_path = []
	var min_dist = 999999
	
	for source in source_nodes:
		for target in target_nodes:
			if source == target:
				return [source]
				
			var path = find_path(source, target)
			if path.is_empty(): continue
			
			var dist = path.size() - 1
			if dist < min_dist:
				min_dist = dist
				best_path = path
			elif dist == min_dist:
				if source == current_node:
					best_path = path
			
	return best_path

func _on_node_hover(node):
	highlight_clear_timer.stop()
	
	var is_known = explored_nodes.has(Vector2(node.row, node.col))
	
	# Check if this is a special node that we should show info for
	var is_special_visual = false
	for type in special_visuals:
		if node in special_visuals[type].nodes:
			is_special_visual = true
			break
			
	# If it's a known special node, highlight it immediately to show text
	if is_known and is_special_visual:
		_highlight_node_structure(node)
	
	if view_only: return
	if is_moving: return
	if not current_node or node == current_node: return
	
	if is_known and (node.type == "mountain" or node.type == "water"): return
	
	var path = get_best_path_to(node)
	if path.is_empty(): return
	
	# Truncate path at first special node (stop at encounters)
	var safe_path = []
	if not path.is_empty():
		safe_path.append(path[0])
		for i in range(1, path.size()):
			var n = path[i]
			safe_path.append(n)
			if n.type != "normal" and n.type != "road" and n.type != "start" and not n.get("defeated", false):
				break
	path = safe_path
	
	var distance = path.size() - 1
	var display_path = path
	var display_distance = distance
	
	if distance > moves_remaining:
		display_distance = moves_remaining
		display_path = path.slice(0, moves_remaining + 1)
	
	# Update Full Path Line
	full_path_line.clear_points()
	if not path.is_empty() and path[0] != current_node:
		full_path_line.add_point(current_node.pos)
	for p_node in path:
		full_path_line.add_point(p_node.pos)
	
	# Update Path Line
	path_line.clear_points()
	if not display_path.is_empty() and display_path[0] != current_node:
		path_line.add_point(current_node.pos)
	for p_node in display_path:
		path_line.add_point(p_node.pos)
	
	# Update Distance Label
	distance_label.text = str(display_distance)
	if not display_path.is_empty():
		distance_label.position = display_path.back().pos + Vector2(0, -50)
	distance_label.visible = true
	
	distance_label.modulate = Color.WHITE
	path_line.default_color = Color.WHITE
	
	if distance > moves_remaining:
		full_distance_label.text = str(distance)
		full_distance_label.position = node.pos + Vector2(0, -50)
		full_distance_label.modulate = Color.RED
		full_distance_label.visible = true
	else:
		full_distance_label.visible = false
		
	if not display_path.is_empty():
		# Only highlight the path end if we didn't already highlight a special node target
		if not (is_known and is_special_visual):
			_highlight_node_structure(display_path.back())

func _on_node_exit():
	highlight_clear_timer.start()

func _on_node_pressed(node):
	if view_only: return
	if is_moving: return
	if node == current_node: return
	if moves_remaining <= 0: return
	
	var path = get_best_path_to(node)
	if path.is_empty(): return
	
	_clear_highlights()
	
	# Truncate path at first special node (stop at encounters)
	# This allows pathfinding to "see" through nodes but forces the player to stop and interact.
	var safe_path = []
	if not path.is_empty():
		safe_path.append(path[0])
		for i in range(1, path.size()):
			var n = path[i]
			safe_path.append(n)
			if n.type != "normal" and n.type != "road" and n.type != "start" and not n.get("defeated", false):
				break
	path = safe_path

	var distance = path.size() - 1
	
	if distance > moves_remaining:
		path = path.slice(0, moves_remaining + 1)
		distance = moves_remaining
	
	is_moving = true
	pending_movement_path = path
	
	# If destination is special, we will lose all remaining moves
	var destination_node = path.back()
	if destination_node.type != "normal" and destination_node.type != "road" and destination_node.type != "start" and not destination_node.get("defeated", false):
		final_moves_remaining = 0
	
	path_line.clear_points()
	full_path_line.clear_points()
	distance_label.visible = false
	full_distance_label.visible = false

	# Step-by-step movement loop
	var path_index = 0
	while path_index < path.size() - 1:
		if not is_moving: break
		
		var next_node = path[path_index + 1]
		
		# Check if the next step is blocked (now that we might have revealed it)
		if next_node.type == "mountain" or next_node.type == "water":
			print("Movement blocked by terrain!")
			break
			
		var start_pos = path[path_index].pos
		var end_pos = next_node.pos
		
		var tween = create_tween()
		current_tween = tween
		tween.tween_method(func(t): _animate_hop(t, start_pos, end_pos), 0.0, 1.0, 0.2)
		
		await tween.finished
		
		if not is_moving: break # Skipped
		
		moves_remaining -= 1
		if moves_remaining > 0:
			moves_label.text = "%d" % moves_remaining
		else:
			moves_label.text = ""
		
		current_node = next_node
		current_node.cleared = true
		update_fog()
		
		# Apply special node movement penalty immediately upon entering
		if current_node.type != "normal" and current_node.type != "road" and current_node.type != "start" and not current_node.get("defeated", false):
			moves_remaining = 0
			moves_label.text = ""
			path_index += 1 # Advance index to match current_node
			break
			
		path_index += 1
		if moves_remaining <= 0: break

	if not is_moving: return
	
	pending_movement_path = [] # Movement finished, prevent skip logic from re-running movement completion
	
	update_visuals()
	update_fog()
	
	if decayed_nodes.has(current_node):
		print("Player moved into decay! Triggering boss fight.")
		var boss_node = null
		if not boss_room_nodes.is_empty():
			boss_node = boss_room_nodes[0]
		else:
			# Fallback data if boss room nodes are missing
			boss_node = {"type": "final_boss", "pos": Vector2.ZERO, "row": 0, "col": 0}
		
		if boss_node:
			emit_signal("node_selected", boss_node)
			return
	
	# Only trigger an encounter (switch to main game view) if it's a special node.
	if current_node.type == "town":
		town_ui.visible = true
		has_rested_in_town = false
		spell_shop_generated = false
		dice_shop_generated = false
		reroll_charms_cost = 25
	elif current_node.type != "normal" and current_node.type != "road" and current_node.type != "start" and not current_node.get("defeated", false):
		emit_signal("node_selected", current_node)
	
	if moves_remaining == 0:
		var timer_tween = create_tween()
		current_tween = timer_tween
		timer_tween.tween_interval(0.5)
		await timer_tween.finished
		if not is_moving: return
		if current_node.type != "town" and visible:
			start_turn()
		
	is_moving = false

func mark_current_node_defeated():
	if current_node:
		current_node.defeated = true
		update_visuals()

func _highlight_node_structure(target_node):
	var new_identifier = target_node
	var structure_found = false
	
	var is_explored = explored_nodes.has(Vector2(target_node.row, target_node.col))
	
	# Check special visuals to determine identifier
	for type in special_visuals:
		if target_node in special_visuals[type].nodes:
			if is_explored:
				new_identifier = type
			break
	
	if typeof(current_highlight_identifier) == typeof(new_identifier) and current_highlight_identifier == new_identifier:
		return

	_clear_highlights()
	current_highlight_identifier = new_identifier
	
	# Check special visuals
	for type in special_visuals:
		var vis = special_visuals[type]
		if target_node in vis.nodes:
			if is_explored:
				structure_found = true
				
				# Highlight nodes
				for n in vis.nodes:
					if n.has("button") and n.button:
						current_highlighted_nodes[n] = n.button.modulate
						n.button.modulate = Color(1.5, 1.5, 1.5) # Brighten
						_add_highlight_outline(n, vis.nodes)
				
				# Enlarge visuals
				if vis.icon:
					vis.icon.scale = Vector2(1.3, 1.3)
					current_highlighted_visuals["icon"] = vis.icon
				if vis.label:
					vis.label.scale = Vector2(1.3, 1.3)
					vis.label.visible = true
					current_highlighted_visuals["label"] = vis.label
			break
	
	if not structure_found:
		# Just highlight the single node
		if target_node.has("button") and target_node.button:
			current_highlighted_nodes[target_node] = target_node.button.modulate
			if is_explored:
				target_node.button.modulate = Color(1.5, 1.5, 1.5)
			_add_highlight_outline(target_node)

func _clear_highlights():
	for n in current_highlighted_nodes:
		if n.has("button") and n.button:
			n.button.modulate = current_highlighted_nodes[n]
			_remove_highlight_outline(n)
			_remove_highlight_outline(n)
	current_highlighted_nodes.clear()
	
	if current_highlighted_visuals.has("icon"):
		current_highlighted_visuals["icon"].scale = Vector2.ONE
	if current_highlighted_visuals.has("label"):
		current_highlighted_visuals["label"].scale = Vector2.ONE
		current_highlighted_visuals["label"].visible = false
	current_highlighted_visuals.clear()
	current_highlight_identifier = null

func _add_highlight_outline(node, group_nodes = []):
	if not node.has("button") or not node.button: return
	
	var btn = node.button
	if btn.has_node("HighlightContainer"): return

	var container = Node2D.new()
	container.name = "HighlightContainer"
	container.position = btn.size / 2.0
	container.z_index = 10
	btn.add_child(container)

	var height = triangle_size * sqrt(3) / 2.0
	var vertices = PackedVector2Array()
	
	if node.points_up:
		vertices = PackedVector2Array([
			Vector2(0, -2.0 / 3.0 * height),
			Vector2(triangle_size / 2.0, 1.0 / 3.0 * height),
			Vector2(-triangle_size / 2.0, 1.0 / 3.0 * height)
		])
	else:
		vertices = PackedVector2Array([
			Vector2(0, 2.0 / 3.0 * height),
			Vector2(-triangle_size / 2.0, -1.0 / 3.0 * height),
			Vector2(triangle_size / 2.0, -1.0 / 3.0 * height)
		])
	
	if group_nodes.is_empty():
		# Close the loop for single tile
		var points = vertices.duplicate()
		points.append(vertices[0])
		
		var line = Line2D.new()
		line.points = points
		line.width = 4.0
		line.default_color = Color(1.0, 1.0, 1.0, 0.8)
		container.add_child(line)
	else:
		var r = node.row
		var c = node.col
		var neighbors_check = []
		var edges_indices = []
		
		if node.points_up:
			# Edges: Right (0-1), Bottom (1-2), Left (2-0)
			neighbors_check = [Vector2(r, c+1), Vector2(r+1, c), Vector2(r, c-1)]
			edges_indices = [[0, 1], [1, 2], [2, 0]]
		else:
			# Edges: Left (0-1), Top (1-2), Right (2-0)
			neighbors_check = [Vector2(r, c-1), Vector2(r-1, c), Vector2(r, c+1)]
			edges_indices = [[0, 1], [1, 2], [2, 0]]
			
		for i in range(3):
			var n_pos = neighbors_check[i]
			var is_shared = false
			
			if grid_data.has(n_pos):
				var neighbor = grid_data[n_pos]
				if neighbor in group_nodes:
					is_shared = true
			
			if not is_shared:
				var line = Line2D.new()
				line.points = PackedVector2Array([vertices[edges_indices[i][0]], vertices[edges_indices[i][1]]])
				line.width = 4.0
				line.default_color = Color(1.0, 1.0, 1.0, 0.8)
				container.add_child(line)

func _remove_highlight_outline(node):
	if not node.has("button") or not node.button: return
	var btn = node.button
	var container = btn.get_node_or_null("HighlightContainer")
	if container:
		container.queue_free()
	var line = btn.get_node_or_null("HighlightOutline") # Legacy cleanup
	if line:
		line.queue_free()

func _perform_clear_highlights():
	path_line.clear_points()
	full_path_line.clear_points()
	distance_label.visible = false
	full_distance_label.visible = false
	_clear_highlights()

func get_node_by_indices(_layer, _index):
	return null

func _animate_hop(t: float, start_pos: Vector2, end_pos: Vector2):
	var current_pos = start_pos.lerp(end_pos, t)
	var hop_height = 30.0
	var height_offset = 4.0 * t * (1.0 - t) * hop_height
	player_icon.position = current_pos - Vector2(0, height_offset) - (player_icon.size / 2.0)

func _skip_roll_animation():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	
	moves_remaining = pending_roll_result
	moves_label.text = "%d" % moves_remaining
	
	if current_roll_overlay:
		current_roll_overlay.queue_free()
		current_roll_overlay = null
	
	for lbl in temp_labels:
		if is_instance_valid(lbl): lbl.queue_free()
	temp_labels.clear()
	
	is_rolling = false

func _skip_movement_animation():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	
	# Calculate where we end up by simulating the remaining path
	var target_node = current_node
	var start_index = pending_movement_path.find(current_node)
	if start_index == -1: start_index = 0
	
	for i in range(start_index + 1, pending_movement_path.size()):
		var next_node = pending_movement_path[i]
		
		# Stop at obstacles
		if next_node.type == "mountain" or next_node.type == "water":
			break
			
		if moves_remaining <= 0:
			break
			
		target_node = next_node
		moves_remaining -= 1
		
		if target_node.type != "normal" and target_node.type != "road" and target_node.type != "start" and not target_node.get("defeated", false):
			moves_remaining = 0
			break
	
	if moves_remaining > 0:
		moves_label.text = "%d" % moves_remaining
	else:
		moves_label.text = ""
	
	current_node = target_node
	current_node.cleared = true
	
	player_icon.position = current_node.pos - (player_icon.size / 2.0)
	update_visuals()
	update_fog()
	
	if decayed_nodes.has(current_node):
		print("Player skipped move into decay! Triggering boss fight.")
		var boss_node = null
		if not boss_room_nodes.is_empty():
			boss_node = boss_room_nodes[0]
		else:
			boss_node = {"type": "final_boss", "pos": Vector2.ZERO, "row": 0, "col": 0}
		
		if boss_node:
			emit_signal("node_selected", boss_node)
			return
	
	if current_node.type == "town":
		town_ui.visible = true
		has_rested_in_town = false
		spell_shop_generated = false
		dice_shop_generated = false
		reroll_charms_cost = 25
	elif current_node.type != "normal" and current_node.type != "road" and current_node.type != "start":
		emit_signal("node_selected", current_node)
	
	is_moving = false
	
	if moves_remaining == 0 and current_node.type != "town" and visible:
		start_turn()

func set_view_only(val: bool):
	view_only = val
	if close_map_button:
		close_map_button.visible = val

func _on_viewport_size_changed():
	var viewport_size = get_viewport().get_visible_rect().size
	var base_height = 648.0
	var scale_factor = viewport_size.y / base_height
	current_scale_factor = scale_factor
	
	# Top bar is roughly 60px base.
	var top_margin = 60 * scale_factor
	
	if log_margin:
		log_margin.add_theme_constant_override("margin_top", int(top_margin))
		
	if scroll_container:
		scroll_container.offset_top = top_margin

	if moves_label:
		moves_label.add_theme_font_size_override("font_size", int(24 * scale_factor))
		moves_label.add_theme_constant_override("outline_size", int(4 * scale_factor))

	if close_map_button:
		close_map_button.custom_minimum_size = Vector2(200, 60) * scale_factor
		close_map_button.add_theme_font_size_override("font_size", int(24 * scale_factor))
		close_map_button.offset_left = -220 * scale_factor
		close_map_button.offset_top = -80 * scale_factor
		close_map_button.offset_right = -20 * scale_factor
		close_map_button.offset_bottom = -20 * scale_factor

	if quest_log_container:
		for child in quest_log_container.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", int(16 * scale_factor))
				child.add_theme_constant_override("outline_size", int(4 * scale_factor))

	if distance_label:
		distance_label.add_theme_font_size_override("font_size", int(24 * scale_factor))
		distance_label.add_theme_constant_override("outline_size", int(4 * scale_factor))

	if full_distance_label:
		full_distance_label.add_theme_font_size_override("font_size", int(24 * scale_factor))
		full_distance_label.add_theme_constant_override("outline_size", int(4 * scale_factor))

	# Scale labels on the map (e.g. "Town", "Crypt")
	for type in special_visuals:
		var vis = special_visuals[type]
		
		var center_pos = Vector2.ZERO
		if vis.nodes.size() > 0:
			for n in vis.nodes:
				center_pos += n.pos
			center_pos /= vis.nodes.size()
			
		if vis.label:
			vis.label.add_theme_font_size_override("font_size", int(14 * scale_factor))
			vis.label.add_theme_constant_override("outline_size", int(4 * scale_factor))
			vis.label.size = Vector2(200, 30) * scale_factor
			vis.label.pivot_offset = vis.label.size / 2.0
			var offset_y = 28 * scale_factor
			vis.label.position = center_pos - (vis.label.size / 2.0) - Vector2(0, offset_y)
	_fit_map_to_screen()
			

func close_town_menu():
	if town_ui:
		town_ui.visible = false

func open_town_menu():
	if town_ui:
		town_ui.visible = true

func update_fog():
	if not current_node: return
	
	if not fog_enabled:
		for pos in grid_data:
			var node = grid_data[pos]
			if node.has("button") and node.button:
				node.button.visible = true
				node.button.modulate = Color.WHITE
			if node.has("shadow") and node.shadow:
				node.shadow.visible = true
		
		for type in special_visuals:
			var vis = special_visuals[type]
			if vis.icon: 
				vis.icon.visible = true
				vis.icon.modulate = Color.WHITE
			if vis.label: 
				vis.label.visible = true
				vis.label.modulate = Color.WHITE
		return

	var visible_nodes = _get_visible_nodes_with_los([current_node], fog_radius)
	
	for n in visible_nodes:
		explored_nodes[Vector2(n.row, n.col)] = true
		
	# Reveal entire special structures if partially explored
	for type in special_visuals:
		var vis = special_visuals[type]
		var structure_revealed = false
		
		for n in vis.nodes:
			if explored_nodes.has(Vector2(n.row, n.col)):
				structure_revealed = true
				break
		
		if structure_revealed:
			for n in vis.nodes:
				explored_nodes[Vector2(n.row, n.col)] = true

	for pos in grid_data:
		var node = grid_data[pos]
		if not node.has("button") or not node.button: continue
		
		if explored_nodes.has(pos):
			node.button.visible = true
			if node.has("shadow") and node.shadow:
				node.shadow.visible = true
			if node in visible_nodes:
				node.button.modulate = Color.WHITE
			else:
				node.button.modulate = Color(0.5, 0.5, 0.5)
		else:
			node.button.visible = true
			node.button.modulate = Color(0, 0, 0, 0)
			if node.has("shadow") and node.shadow:
				node.shadow.visible = false

	for type in special_visuals:
		var vis = special_visuals[type]
		var is_explored = false
		var is_currently_visible = false
		
		for n in vis.nodes:
			if explored_nodes.has(Vector2(n.row, n.col)):
				is_explored = true
			if n in visible_nodes:
				is_currently_visible = true
		
		if vis.icon: 
			vis.icon.visible = is_explored
			vis.icon.modulate = Color.WHITE if is_currently_visible else Color(0.5, 0.5, 0.5)
		if vis.label: 
			vis.label.modulate = Color.WHITE if is_currently_visible else Color(0.5, 0.5, 0.5)

func _fit_map_to_screen():
	var content_size = Vector2.ZERO
	
	# Calculate actual content size from grid data
	if not grid_data.is_empty():
		var max_x = 0.0
		var max_y = 0.0
		for pos in grid_data:
			var node = grid_data[pos]
			if node.has("button") and is_instance_valid(node.button):
				var rect = node.button.get_rect()
				if rect.end.x > max_x: max_x = rect.end.x
				if rect.end.y > max_y: max_y = rect.end.y
		if max_x > 0 and max_y > 0:
			content_size = Vector2(max_x, max_y)
	
	if content_size == Vector2.ZERO:
		content_size = map_base_size
		
	if content_size == Vector2.ZERO: return
	
	# Add padding
	content_size += Vector2(50, 50)
	
	current_zoom = 1.0
	map_container.scale = Vector2.ONE
	map_container.custom_minimum_size = content_size
