extends PanelContainer
class_name AbilityUI

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/Title
@onready var description_label: RichTextLabel = $MarginContainer/VBoxContainer/Description
@onready var icon_texture_rect: TextureRect = $MarginContainer/VBoxContainer/Header/Icon
@onready var dice_slots_container: HBoxContainer = $MarginContainer/VBoxContainer/DiceSlots

const DieSlotUI = preload("res://scenes/die_slot_ui.tscn")

@export var ability: Ability:
	set(value):
		ability = value
		# If the node is already ready, we can update the display immediately.
		# This handles cases where the ability might be changed later in the game.
		if is_node_ready(): update_display()

func update_display() -> void:
	if not ability:
		return

	title_label.text = ability.title
	description_label.text = ability.description
	icon_texture_rect.texture = ability.icon
	
	# Clear any previously added die slots before adding new ones.
	for child in dice_slots_container.get_children():
		child.queue_free()
	
	for i in range(ability.dice_slots):
		dice_slots_container.add_child(DieSlotUI.instantiate())

func _ready() -> void:	
	update_display()
