extends Control
class_name QuestBoardScreen

signal quests_confirmed(quests_data)
signal close_requested

@onready var quests_container = $Panel/VBoxContainer/Content/QuestsContainer
@onready var dice_pool = $Panel/VBoxContainer/Content/DicePoolContainer/DicePool
@onready var confirm_button = $Panel/VBoxContainer/ConfirmButton

const DIE_SLOT_SCENE = preload("res://scenes/ui/die_slot.tscn")

const QUEST_POOL = [
	{"id": "goblin_camp", "name": "Goblin's Camp", "desc": "A raiding party of goblins.", "icon": "res://assets/ai/ui/goblin_camp_node.svg"},
	{"id": "crypt", "name": "Crypt", "desc": "Restless dead stir within.", "icon": "res://assets/ai/ui/crypt_node.svg"},
	{"id": "dragons_roost", "name": "Dragon's Roost", "desc": "A dragon has been spotted.", "icon": "res://assets/ai/ui/dragon_roost_node.svg"},
	{"id": "dwarven_forge", "name": "Dwarven Forge", "desc": "Abandoned dwarven technology.", "icon": "res://assets/ai/ui/dwarven_forge_node.svg"}
]

var player: Player
var is_first_time = true
var active_quest_slots: Array[DieSlotUI] = []
var generated_quests_data = []

func _ready():
	visible = false
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = true

func open(p_player: Player):
	player = p_player
	visible = true
	dice_pool.player = player
	
	if is_first_time:
		_generate_initial_quests()
		_roll_quest_dice()
		is_first_time = false
	
	# Refresh slots in case player changed (e.g. silence status)
	for slot in active_quest_slots:
		slot.player = player

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
	dice_pool.clear_pool()
	var dice: Array[Die] = []
	for i in range(3):
		var d = Die.new(6)
		d.roll()
		dice.append(d)
	dice_pool.add_dice_instantly(dice)

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
	visible = false

func _on_close_button_pressed():
	visible = false
	emit_signal("close_requested")
