extends PanelContainer
class_name AbilityUI

@onready var title_label: Label = $VBoxContainer/Header/Title
@onready var description_label: RichTextLabel = $VBoxContainer/DescriptionWrapper/Description
@onready var icon_texture: TextureRect = $VBoxContainer/Header/Icon
@onready var dice_slots_container: HBoxContainer = $VBoxContainer/Header/DiceSlots
@onready var cooldown_label: Label = $VBoxContainer/Header/CooldownLabel
@onready var description_wrapper: Control = $VBoxContainer/DescriptionWrapper

const DIE_SLOT_SCENE = preload("res://scenes/ui/die_slot.tscn")

var ability_data: AbilityData
var player: Player
var original_stylebox: StyleBox
var active_stylebox: StyleBoxFlat

var is_consumed_this_turn := false
var current_cooldown: int = 0
var tween: Tween
var hide_timer: Timer

signal die_returned_from_slot(die_display)
signal ability_activated(ability_ui)

func _ready():
	# Store the original style and create a new one for the "active" state.
	# This is done in _ready to ensure the node is fully initialized and has its theme.
	original_stylebox = get_theme_stylebox("panel")
	if original_stylebox:
		active_stylebox = original_stylebox.duplicate(true) as StyleBoxFlat
		active_stylebox.set_border_width_all(4)
		active_stylebox.border_color = Color.GOLD
	else:
		push_error("Could not find 'panel' stylebox for AbilityUI. Theming will not work correctly.")

	# Setup hover animation
	mouse_entered.connect(_on_any_mouse_entered)
	mouse_exited.connect(_on_any_mouse_exited)
	
	# Set mouse filter to IGNORE for all child nodes that shouldn't block hover.
	# This ensures the main AbilityUI panel captures hover events for the entire area,
	# except for the interactive DieSlots.
	$VBoxContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$VBoxContainer/Header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$VBoxContainer/Header/Spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Timer to delay hiding the description, to handle mouse moving between elements.
	hide_timer = Timer.new()
	hide_timer.wait_time = 0.05
	hide_timer.one_shot = true
	add_child(hide_timer)
	hide_timer.timeout.connect(_contract_description)
	
	# Hide description initially
	description_wrapper.custom_minimum_size.y = 0

func initialize(data: AbilityData, p_player: Player):
	self.ability_data = data
	self.player = p_player
	if not ability_data: return
	
	title_label.text = ability_data.title
	description_label.text = ability_data.description
	icon_texture.texture = ability_data.icon
	cooldown_label.visible = false

	# Clear any existing/placeholder slots from the editor
	for child in dice_slots_container.get_children():
		child.queue_free()

	# Create the required number of slots
	for i in range(ability_data.dice_slots):
		# Use a cast (`as`) to safely handle the instantiated node.
		var slot := DIE_SLOT_SCENE.instantiate() as DieSlotUI
		if slot:
			slot.player = player
			dice_slots_container.add_child(slot)
			slot.die_placed.connect(_on_die_placed)
			slot.die_removed.connect(_on_die_removed)
			slot.mouse_entered.connect(_on_any_mouse_entered)
			slot.mouse_exited.connect(_on_any_mouse_exited)
		else:
			push_error("Failed to instantiate DieSlotUI. Check that 'die_slot.tscn' has the 'DieSlotUI' script attached to its root node.")

func _on_die_placed(die_display, die_data: Die):
	# This function is called when a die is successfully placed in a slot.
	# You can add logic here to check if all slots are filled and then activate the ability.
	_check_if_all_slots_filled()

func _on_die_removed(die_display):
	# Pass the signal up to the main script so it can be returned to the pool.
	emit_signal("die_returned_from_slot", die_display)
	# When a die is removed, the ability is no longer active, so revert the style.
	add_theme_stylebox_override("panel", original_stylebox)

func _check_if_all_slots_filled():
	if is_consumed_this_turn or current_cooldown > 0:
		return

	var all_filled = true
	for slot in dice_slots_container.get_children():
		if slot is DieSlotUI and slot.current_die_display == null:
			all_filled = false
			break
	
	if all_filled:
		print("Ability '%s' has been triggered!" % ability_data.title)
		is_consumed_this_turn = true
		add_theme_stylebox_override("panel", active_stylebox)
		emit_signal("ability_activated", self)
		
		# Gray out the ability to show it's been used this turn.
		modulate = Color(0.5, 0.5, 0.5)
		
		# Immediately display the cooldown timer when the ability is activated.
		if ability_data.cooldown_duration > 0:
			cooldown_label.text = str(ability_data.cooldown_duration)
			cooldown_label.visible = true

		# Disable slots until the end of the turn to prevent further interaction.
		for slot in dice_slots_container.get_children():
			if slot is DieSlotUI:
				slot.mouse_filter = MOUSE_FILTER_IGNORE

func get_slotted_dice_displays() -> Array[DieDisplay]:
	var displays: Array[DieDisplay] = []
	for slot in dice_slots_container.get_children():
		if slot is DieSlotUI and slot.current_die_display:
			displays.append(slot.current_die_display)
	return displays
	
func reset_for_new_turn() -> Array[Die]:
	var dice_to_discard: Array[Die] = []

	if is_consumed_this_turn:
		# The ability was used last turn. Put it on cooldown.
		is_consumed_this_turn = false
		current_cooldown = ability_data.cooldown_duration
		for slot in dice_slots_container.get_children():
			if slot is DieSlotUI and slot.current_die_display:
				var die_display = slot.current_die_display
				if ability_data.discard_dice_on_reset:
					dice_to_discard.append(die_display.die)
				slot.remove_child(die_display)
				die_display.queue_free()
				slot.current_die_display = null
	
	# Tick down any active cooldown. This happens after setting it,
	# so a 1-turn cooldown becomes 0 and is ready next turn.
	if current_cooldown > 0:
		current_cooldown -= 1

	# Update UI based on the new state
	if current_cooldown > 0:
		modulate = Color(0.5, 0.5, 0.5) # Stay grayed out
		cooldown_label.text = str(current_cooldown)
		cooldown_label.visible = true
	else:
		# Cooldown is over, so make the ability usable again.
		modulate = Color.WHITE
		cooldown_label.visible = false
		add_theme_stylebox_override("panel", original_stylebox)
		for slot in dice_slots_container.get_children():
			if slot is DieSlotUI:
				slot.mouse_filter = MOUSE_FILTER_STOP
				
	return dice_to_discard

func update_scale(factor: float):
	var base_width = 250.0
	custom_minimum_size.x = base_width * factor

	# Scale slots
	for slot in dice_slots_container.get_children():
		if slot.has_method("update_scale"):
			slot.update_scale(factor)
	
	# Scale icon
	var base_icon_size = 40.0
	if icon_texture:
		icon_texture.custom_minimum_size = Vector2(base_icon_size, base_icon_size) * factor

func _on_any_mouse_entered():
	hide_timer.stop()
	_expand_description()

func _on_any_mouse_exited():
	hide_timer.start()

func _expand_description():
	if tween: tween.kill()
	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Calculate target height based on content
	var target_height = description_label.get_content_height() + 10 # Add padding
	
	tween.tween_property(description_wrapper, "custom_minimum_size:y", target_height, 0.2)

func _contract_description():
	if tween: tween.kill()
	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_property(description_wrapper, "custom_minimum_size:y", 0.0, 0.2)
