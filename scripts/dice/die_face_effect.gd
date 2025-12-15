extends Resource
class_name DieFaceEffect

var tier: int = 1
var name: String = "Effect Name"
var description: String = ""
var highlight_color: Color = Color.PALE_VIOLET_RED

var process_effect: Callable

func _init(pName: String = "", pDesc: String = "", pTier: int = 1, pHighlight_color: Color = Color.PALE_VIOLET_RED):
	self.name = pName
	self.description = pDesc
	self.tier = pTier
	self.highlight_color = pHighlight_color
