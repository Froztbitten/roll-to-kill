extends Resource
class_name DieFaceEffect

enum EffectType {
	SHIELD_ON_ATTACK,
}

@export var type: EffectType
@export_range(1, 3) var tier: int = 1
@export var explicit_name: String = "Effect Name"
@export_color_no_alpha var cell_color: Color = Color.PALE_VIOLET_RED
@export var glow_color: Color = Color.WEB_PURPLE