extends PanelContainer
class_name AbilityUI

@onready var icon_texture_rect: TextureRect = $VBoxContainer/Header/Icon
@onready var title_label: Label = $VBoxContainer/Header/Title
@onready var description_label: RichTextLabel = $VBoxContainer/HBoxContainer/Description
@onready var dice_slots_container: HBoxContainer = $VBoxContainer/HBoxContainer/DiceSlots

const DieSlotUI = preload("res://scenes/ui/die_slot.tscn")

func initialize(ability_data: AbilityData) -> void:
	print(ability_data.title)
	icon_texture_rect.texture = ability_data.icon
	title_label.text = ability_data.title
	description_label.text = ability_data.description
	
	for child in dice_slots_container.get_children():
		child.queue_free()
	
	for i in range(ability_data.dice_slots):
		dice_slots_container.add_child(DieSlotUI.instantiate())
