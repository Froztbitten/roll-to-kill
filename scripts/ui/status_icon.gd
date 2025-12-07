extends TextureRect

var status_effect: StatusEffect

func set_status(effect: StatusEffect):
	self.status_effect = effect
	self.texture = effect.icon
	self.tooltip_text = "%s\n%s" % [effect.status_name, effect.description]
