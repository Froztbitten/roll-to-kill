extends TextureRect

var status_effect: StatusEffect

@onready var count_label: Label = $CountLabel

func set_status(effect: StatusEffect, value: int):
	self.status_effect = effect
	self.texture = effect.icon
	self.tooltip_text = "%s\n%s" % [effect.status_name, effect.description]
	if count_label:
		count_label.text = str(value)
