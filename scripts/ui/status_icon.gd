extends TextureRect

var status_effect: StatusEffect

var status_value: int = 0
@onready var count_label: Label = $CountLabel
@onready var hover_timer: Timer = $HoverTimer
@onready var tooltip: PanelContainer = $Tooltip
@onready var description_label: RichTextLabel = $Tooltip/DescriptionLabel

func _ready():
	# Make the tooltip render on top of other UI elements and ensure it's hidden at start.
	tooltip.set_as_top_level(true)
	tooltip.visible = false

func set_status(effect: StatusEffect, value: int):
	self.status_effect = effect
	self.status_value = value
	self.texture = effect.icon
	# The built-in tooltip is replaced by our custom implementation.
	# self.tooltip_text = "%s\n%s" % [effect.status_name, effect.description]
	if count_label:
		count_label.text = str(value)

func _on_mouse_entered():
	hover_timer.start()

func _on_mouse_exited():
	hover_timer.stop()
	tooltip.visible = false

func _on_hover_timer_timeout():
	if not status_effect:
		return

	var final_description = status_effect.description
	# If the description contains 'X', replace it with the actual value.
	final_description = final_description.replace("X", "X ([color=yellow]%d[/color])" % status_value)

	# Set the text, which will define the tooltip's size.
	description_label.text = "[b]%s[/b]\n%s" % [status_effect.status_name, final_description]
	
	# Wait a frame for the label to resize with the new text, which resizes the container.
	await get_tree().process_frame
	
	# Position the tooltip to be centered above the icon.
	tooltip.global_position = global_position + Vector2(size.x / 2 - tooltip.size.x / 2, -tooltip.size.y - 5)
	tooltip.visible = true
