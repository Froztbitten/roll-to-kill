extends PanelContainer
class_name AbilityUI

@onready var title_label: Label = $VBoxContainer/Header/Title
@onready var description_label: RichTextLabel = $VBoxContainer/HBoxContainer/Description
@onready var icon_texture: TextureRect = $VBoxContainer/Header/Icon
@onready var dice_slots_container: HBoxContainer = $VBoxContainer/HBoxContainer/DiceSlots
@onready var cooldown_label: Label = $VBoxContainer/Header/CooldownLabel

const DIE_SLOT_SCENE = preload("res://scenes/ui/die_slot.tscn")

var ability_data: AbilityData
var original_stylebox: StyleBox
var active_stylebox: StyleBoxFlat

var is_consumed_this_turn := false
var current_cooldown: int = 0

signal die_returned_from_slot(die_display)
signal ability_activated(ability_ui)

func initialize(data: AbilityData):
	self.ability_data = data
	if not ability_data: return
	
	title_label.text = ability_data.title
	description_label.text = ability_data.description
	icon_texture.texture = ability_data.icon
	cooldown_label.visible = false

	# Store the original style and create a new one for the "active" state.
	original_stylebox = get_theme_stylebox("panel")
	active_stylebox = original_stylebox.duplicate(true) as StyleBoxFlat
	active_stylebox.set_border_width_all(4)
	active_stylebox.border_color = Color.GOLD

	# Clear any existing/placeholder slots from the editor
	for child in dice_slots_container.get_children():
		child.queue_free()

	# Create the required number of slots
	for i in range(ability_data.dice_slots):
		# Use a cast (`as`) to safely handle the instantiated node.
		var slot := DIE_SLOT_SCENE.instantiate() as DieSlotUI
		if slot:
			dice_slots_container.add_child(slot)
			slot.die_placed.connect(_on_die_placed)
			slot.die_removed.connect(_on_die_removed)
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
