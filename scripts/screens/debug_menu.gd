extends Control

signal encounter_selected(type, data)
signal close_requested

@onready var encounters_container = $MarginContainer/VBoxContainer/ScrollContainer/EncountersContainer

func setup_encounters(combat_encounters: Array):
	# Clear existing children
	for child in encounters_container.get_children():
		child.queue_free()
	
	for encounter in combat_encounters:
		var btn = Button.new()
		var name_str = encounter.resource_path.get_file().get_basename().capitalize()
		
		var type_str = "NORMAL"
		if encounter.encounter_type == EncounterData.EncounterType.BOSS:
			type_str = "BOSS"
		elif encounter.encounter_type == EncounterData.EncounterType.RARE:
			type_str = "RARE"
			
		btn.text = "[%s] %s" % [type_str, name_str]
		btn.custom_minimum_size = Vector2(0, 60)
		btn.size_flags_horizontal = 3
		btn.pressed.connect(func(): encounter_selected.emit("combat", encounter))
		encounters_container.add_child(btn)

func _on_close_button_pressed():
	close_requested.emit()