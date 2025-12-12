extends Resource
class_name DieFaceEffect

var tier: int = 1
var name: String = "Effect Name"
var highlight_color: Color = Color.PALE_VIOLET_RED

var process_effect: Callable

func _init(pName: String = "", pTier: int = 1, pHighlight_color: Color = Color.PALE_VIOLET_RED):
	self.name = pName
	self.tier = pTier
	self.highlight_color = pHighlight_color
