extends Resource
class_name StatusEffect

var status_name: String
var description: String
var duration: int
var charges: int
var icon: Texture2D
var is_debuff: bool = false

func _init(p_name: String = "", p_is_debuff: bool = false, p_desc: String = "", p_icon: Texture2D = null, p_duration: int = -1, p_charges: int = -1, ):
	status_name = p_name
	description = p_desc
	icon = p_icon
	duration = p_duration
	charges = p_charges
	is_debuff = p_is_debuff
