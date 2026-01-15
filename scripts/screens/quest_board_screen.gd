extends Control
class_name QuestBoardScreen

signal quests_confirmed(quests_data)
signal close_requested

@onready var quests_container = $Panel/VBoxContainer/Content/QuestsContainer
@onready var dice_pool = $Panel/VBoxContainer/Content/DicePoolContainer/DicePool
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

const DIE_SLOT_SCENE = preload("res://scenes/ui/die_slot.tscn")
const DIE_RENDERER_SCENE = preload("res://scenes/ui/die_3d_renderer.tscn")

const QUEST_POOL = [
	{"id": "goblin_camp", "name": "Goblin's Camp", "desc": "A raiding party of goblins.", "icon": "res://assets/ai/ui/goblin_camp_node.svg"},
	{"id": "crypt", "name": "Crypt", "desc": "Restless dead stir within.", "icon": "res://assets/ai/ui/crypt_node.svg"},
	{"id": "dragon_roost", "name": "Dragon's Roost", "desc": "A dragon has been spotted.", "icon": "res://assets/ai/ui/dragon_roost_node.svg"},
	{"id": "dwarven_forge", "name": "Dwarven Forge", "desc": "Abandoned dwarven technology.", "icon": "res://assets/ai/ui/dwarven_forge_node.svg"}
]

var player: Player
var is_first_time = true
var active_quest_slots: Array[DieSlotUI] = []
var generated_quests_data = []
var is_rolling = false
var current_roll_overlay: Control
var current_tween: Tween
var pending_dice_results: Array[int] = []
var current_directions: Dictionary = {}
var is_confirmed = false

func _ready():
	visible = false
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = true

	# Move Back button to bottom next to Confirm button
	var header = $Panel/VBoxContainer/Header
	if header.has_node("CloseButton"):
		var close_btn = header.get_node("CloseButton")
		header.remove_child(close_btn)
		
		var btn_container = HBoxContainer.new()
		btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_container.add_theme_constant_override("separation", 20)
		
		var vbox = $Panel/VBoxContainer
		var confirm_idx = confirm_button.get_index()
		vbox.add_child(btn_container)
		vbox.move_child(btn_container, confirm_idx)
		
		confirm_button.get_parent().remove_child(confirm_button)
		btn_container.add_child(confirm_button)
		btn_container.add_child(close_btn)
		
		close_btn.custom_minimum_size = Vector2(200, 60)
		close_btn.add_theme_font_size_override("font_size", 24)

func _input(event):
	if not visible: return
	if is_rolling and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_skip_roll_animation()
		get_viewport().set_input_as_handled()

func open(p_player: Player, directions: Dictionary = {}):
	player = p_player
	visible = true
	current_directions = directions
	dice_pool.player = player
	
	if is_first_time:
		_generate_initial_quests()
		_roll_quest_dice()
		is_first_time = false
	
	# Refresh slots in case player changed (e.g. silence status)
	for slot in active_quest_slots:
		slot.player = player
		if is_confirmed:
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if is_confirmed:
		confirm_button.text = "Confirmed"
		confirm_button.disabled = true
	else:
		confirm_button.text = "Confirm Allocation"
		_check_confirm_status()

func _generate_initial_quests():
	# Clear existing
	for child in quests_container.get_children():
		child.queue_free()
	active_quest_slots.clear()
	generated_quests_data.clear()
	
	# Pick 3 unique quests
	var pool = QUEST_POOL.duplicate()
	pool.shuffle()
	var selected = pool.slice(0, 3)
	
	for q_data in selected:
		_create_quest_paper(q_data)
		generated_quests_data.append(q_data)

func _create_quest_paper(data: Dictionary):
	var paper = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.75, 0.6) # Parchment color
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = Color(0.4, 0.3, 0.2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 15
	style.content_margin_top = 15
	style.content_margin_right = 15
	style.content_margin_bottom = 15
	paper.add_theme_stylebox_override("panel", style)
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	paper.add_child(vbox)
	
	if data.has("icon") and data.icon != "":
		var icon_rect = TextureRect.new()
		icon_rect.texture = load(data.icon)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(80, 80)
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)
	
	var title = Label.new()
	title.text = data.name
	title.add_theme_color_override("font_color", Color(0.2, 0.1, 0.05))
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = data.desc
	desc.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size.y = 40
	vbox.add_child(desc)
	
	if current_directions.has(data.id):
		var dir_label = Label.new()
		dir_label.text = "Location: %s" % current_directions[data.id]
		dir_label.add_theme_color_override("font_color", Color(0.4, 0.1, 0.1))
		dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(dir_label)
	
	var slot_container = CenterContainer.new()
	vbox.add_child(slot_container)
	
	var slot = DIE_SLOT_SCENE.instantiate()
	slot.player = player
	slot.custom_minimum_size = Vector2(60, 60)
	slot.die_placed.connect(_on_die_placed_in_quest.bind(data, vbox))
	slot.die_removed.connect(_on_die_removed_from_quest.bind(data, vbox))
	slot_container.add_child(slot)
	active_quest_slots.append(slot)
	
	var info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Place a die to set\nDifficulty & Reward"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	vbox.add_child(info_label)
	
	quests_container.add_child(paper)

func _roll_quest_dice():
	is_rolling = true
	pending_dice_results.clear()
	
	# Create Overlay
	var roll_overlay = Control.new()
	current_roll_overlay = roll_overlay
	roll_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.z_index = 200
	
	# Dimmer
	var dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.add_child(dimmer)
	
	add_child(roll_overlay)
	
	var center_cont = CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.add_child(center_cont)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", -100)
	center_cont.add_child(hbox)
	
	var disp = DIE_RENDERER_SCENE.instantiate()
	disp.custom_minimum_size = Vector2(600, 600)
	hbox.add_child(disp)
	
	var results_map = {}
	var finished_count = 0
	
	disp.roll_finished.connect(func(id, val): 
		results_map[id] = val
		finished_count += 1
		# If all dice are done, update pending results immediately
		if finished_count == 3:
			var temp_results: Array[int] = []
			for i in range(3):
				temp_results.append(results_map.get(i, 1))
			pending_dice_results = temp_results
	)

	for i in range(3):
		disp.add_die(i, 6, 0) # ID is index, 6 sides
	
	disp.roll_all()
	
	# Animate in while rolling
	hbox.scale = Vector2.ZERO
	var tween = create_tween()
	current_tween = tween
	tween.tween_property(hbox, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Wait for results with timeout to prevent hanging
	var timeout_frames = 300 # Approx 5 seconds
	while finished_count < 3 and is_rolling and timeout_frames > 0:
		await get_tree().process_frame
		timeout_frames -= 1
		
	if not is_rolling: return
	
	# Force finish any stuck dice
	if finished_count < 3:
		disp.skip_animation()
		# Allow signals to propagate
		await get_tree().process_frame
	
	var results: Array[int] = []
	var start_positions = []
	
	# Collect results in order of renderers (Left to Right)
	for i in range(3):
		results.append(results_map.get(i, 1))
		start_positions.append(disp.get_die_screen_position(i))
	
	pending_dice_results = results.duplicate()
	
	# Small delay to see results
	await get_tree().create_timer(0.5).timeout
	if not is_rolling: return
	
	# Add to pool
	await _finalize_dice_roll(results, start_positions)
	
	# Fade out
	var out_tween = create_tween()
	current_tween = out_tween
	out_tween.tween_property(roll_overlay, "modulate:a", 0.0, 0.3)
	await out_tween.finished
	
	if is_instance_valid(roll_overlay):
		roll_overlay.queue_free()
	current_roll_overlay = null
	is_rolling = false

func _on_die_placed_in_quest(die_display, die_data, quest_data, vbox_container):
	var val = die_data.result_value
	var info_label = vbox_container.get_node("InfoLabel")
	
	var difficulty = "Normal"
	var reward = "Standard"
	
	if val <= 2:
		difficulty = "Easy"
		reward = "Low (Gold)"
	elif val <= 4:
		difficulty = "Medium"
		reward = "Medium (Gold + Item)"
	else:
		difficulty = "Hard"
		reward = "High (Rare Item)"
		
	info_label.text = "Difficulty: %s\nReward: %s" % [difficulty, reward]
	info_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	
	_check_confirm_status()

func _on_die_removed_from_quest(die_display, quest_data, vbox_container):
	# Return die to pool
	dice_pool.add_die_display(die_display)
	
	var info_label = vbox_container.get_node("InfoLabel")
	info_label.text = "Place a die to set\nDifficulty & Reward"
	info_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	
	_check_confirm_status()

func _check_confirm_status():
	if is_confirmed: return
	var all_filled = true
	for slot in active_quest_slots:
		if slot.current_die_display == null:
			all_filled = false
			break
	confirm_button.disabled = not all_filled

func _on_confirm_pressed():
	# Gather final data
	var final_quests = []
	for i in range(active_quest_slots.size()):
		var slot = active_quest_slots[i]
		var q_data = generated_quests_data[i].duplicate()
		if slot.current_die_display:
			q_data["die_value"] = slot.current_die_display.die.result_value
			final_quests.append(q_data)
	
	emit_signal("quests_confirmed", final_quests)
	
	is_confirmed = true
	confirm_button.disabled = true
	confirm_button.text = "Confirmed"
	
	for slot in active_quest_slots:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_close_button_pressed():
	visible = false
	emit_signal("close_requested")

func _finalize_dice_roll(values: Array, start_positions: Array = []):
	dice_pool.clear_pool()
	var dice: Array[Die] = []
	for val in values:
		var d = Die.new(6)
		d.result_value = val
		if d.faces.size() >= val:
			d.result_face = d.faces[val - 1]
		dice.append(d)
	
	# Animate adding to pool from center of screen
	if start_positions.is_empty():
		var center = get_viewport_rect().size / 2.0
		await dice_pool.animate_add_dice(dice, center)
	else:
		await dice_pool.animate_add_dice(dice, start_positions)

func _skip_roll_animation():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
		
	# If we skipped before results were ready, generate random ones
	while pending_dice_results.size() < 3:
		pending_dice_results.append(randi_range(1, 6))
	
	_finalize_dice_roll(pending_dice_results)
	
	if current_roll_overlay:
		current_roll_overlay.queue_free()
		current_roll_overlay = null
		
	is_rolling = false
