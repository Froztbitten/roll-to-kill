extends Control

var FACES = {}
var ACTION_ICONS = {}

@onready var icon: TextureRect = $IconContainer/Icon
@onready var action_type_icon: TextureRect = $IconContainer/ActionTypeIcon
@onready var roll_label: Label = $IconContainer/ActionTypeIcon/RollLabel
@onready var action_name_label: Label = $ActionNameLabel
@onready var dice_count_label: Label = $IconContainer/Icon/DiceCountLabel
@onready var status_icon: TextureRect = $IconContainer/StatusIcon

var current_status_effect: StatusEffect
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _tooltip_timer: Timer
var _tooltip_tween: Tween
var _tooltip_layer: CanvasLayer

func _ready():
	# Use load() at runtime instead of preload() at parse time to avoid importer issues.
	FACES = {
		2: load("res://assets/ai/dice/d2.svg"),
		4: load("res://assets/ai/dice/d4.svg"),
		6: load("res://assets/ai/dice/d6.svg"),
		8: load("res://assets/ai/dice/d8.svg"),
		10: load("res://assets/ai/dice/d10.svg"),
		12: load("res://assets/ai/dice/d12.svg"),
		20: load("res://assets/ai/dice/d20.svg")
	}
	ACTION_ICONS = {
		"attack": load("res://assets/ai/ui/sword.svg"),
		"shield": load("res://assets/ai/ui/shield.svg"),
		"charge": load("res://assets/ai/ui/reload.svg"),
		"heal": load("res://assets/ai/ability_icons/heal_ability_icon.svg")
	}
	
	_setup_tooltip()
	
	$IconContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	status_icon.mouse_default_cursor_shape = Control.CURSOR_HELP
	status_icon.mouse_entered.connect(_on_status_mouse_entered)
	status_icon.mouse_exited.connect(_on_status_mouse_exited)

func _setup_tooltip():
	_tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 128 # Ensure it's above everything (Main UI is usually 20)
	_tooltip_layer.visible = true
	add_child(_tooltip_layer)
	
	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.custom_minimum_size = Vector2(200, 0)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)
	
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_layer.add_child(_tooltip_panel)
	
	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.1
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_show_tooltip)
	add_child(_tooltip_timer)

func update_display(action_name: String, value: int, sides: int, action_type: String, dice_count: int, status_id: String = ""):
	action_name_label.text = action_name

	if action_type == "charge":
		# For charging actions, hide the value and die icon, and show the reload icon.
		roll_label.visible = false
		icon.visible = false
		action_type_icon.texture = ACTION_ICONS["charge"]
		action_type_icon.visible = true
		dice_count_label.visible = false
		icon.modulate = Color.WHITE # Reset color just in case
	else:
		# For standard attack/shield actions, show all info.
		roll_label.visible = true
		icon.visible = true
		
		if dice_count > 1:
			dice_count_label.text = "x%d" % dice_count
			dice_count_label.visible = true
		else:
			dice_count_label.visible = false
		roll_label.text = str(value)
		
		if FACES.has(sides):
			icon.texture = FACES[sides]
		else:
			icon.texture = FACES[8]
		
		if ACTION_ICONS.has(action_type):
			action_type_icon.texture = ACTION_ICONS[action_type]
			action_type_icon.visible = true
		else:
			action_type_icon.visible = false

		if action_type == "attack":
			icon.modulate = Color.CRIMSON
		elif action_type == "shield":
			icon.modulate = Color(0.6, 0.7, 1, 1) # Same blue as player's shield
		elif action_type == "heal":
			icon.modulate = Color.PALE_GREEN
		else:
			icon.modulate = Color.WHITE # Default color

	if status_id != "" and status_id != "bone_apart":
		var status = StatusLibrary.get_status(status_id)
		if status:
			status_icon.texture = status.icon
			status_icon.visible = true
			current_status_effect = status
		else:
			status_icon.visible = false
			current_status_effect = null
	else:
		status_icon.visible = false
		current_status_effect = null

func _on_status_mouse_entered():
	_tooltip_timer.start()

func _on_status_mouse_exited():
	_tooltip_timer.stop()
	_hide_tooltip()

func _show_tooltip():
	if not current_status_effect or not status_icon.is_visible_in_tree(): return
	
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	_tooltip_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	# Force white text to ensure visibility
	_tooltip_label.text = "[color=white][b]%s[/b]\n%s[/color]" % [current_status_effect.status_name, current_status_effect.description]
	
	# Force layout update immediately
	_tooltip_panel.reset_size()
	_tooltip_label.reset_size()
	
	# Use mouse position for reliable screen-space positioning
	var mouse_pos = get_viewport().get_mouse_position()
	var tooltip_size = _tooltip_panel.get_minimum_size()
	var viewport_rect = get_viewport().get_visible_rect()
	
	var target_pos = mouse_pos + Vector2(15, 15)
	
	# Clamp to screen
	if target_pos.x + tooltip_size.x > viewport_rect.size.x:
		target_pos.x = mouse_pos.x - tooltip_size.x - 15
	if target_pos.y + tooltip_size.y > viewport_rect.size.y:
		target_pos.y = mouse_pos.y - tooltip_size.y - 15
	
	# Ensure it doesn't go off the top/left
	if target_pos.x < 0: target_pos.x = 0
	if target_pos.y < 0: target_pos.y = 0
	
	_tooltip_panel.global_position = target_pos
	_tooltip_panel.modulate.a = 1.0
	_tooltip_panel.visible = true

func _hide_tooltip():
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	if _tooltip_panel.visible:
		_tooltip_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 0.0, 0.1)
		_tooltip_tween.tween_callback(func(): _tooltip_panel.visible = false)
