extends TextureRect

var status_effect: StatusEffect

var status_value: int = 0
@onready var count_label: Label = $CountLabel
@onready var hover_timer: Timer = $HoverTimer
@onready var tooltip: PanelContainer = $Tooltip
@onready var description_label: RichTextLabel = $Tooltip/DescriptionLabel
var tooltip_tween: Tween

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
		if value == -1:
			count_label.text = ""
		else:
			count_label.text = str(value)

func _on_mouse_entered():
	hover_timer.start()

func _on_mouse_exited():
	hover_timer.stop()
	if tooltip_tween and tooltip_tween.is_running():
		tooltip_tween.kill()
	if tooltip.visible:
		tooltip_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tooltip_tween.tween_property(tooltip, "modulate:a", 0.0, 0.1)
		tooltip_tween.tween_callback(func(): if is_instance_valid(tooltip): tooltip.visible = false)

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
	
	# Position the tooltip to be centered above the icon, but clamp to screen edges.
	var viewport_rect = get_viewport().get_visible_rect()
	var tooltip_size = tooltip.size
	var icon_rect = get_global_rect()
	
	var tooltip_pos_x = icon_rect.position.x + (icon_rect.size.x / 2.0) - (tooltip_size.x / 2.0)
	tooltip_pos_x = clamp(tooltip_pos_x, viewport_rect.position.x, viewport_rect.end.x - tooltip_size.x)
	tooltip.global_position = Vector2(tooltip_pos_x, icon_rect.position.y - tooltip_size.y - 5)
	
	if tooltip_tween and tooltip_tween.is_running():
		tooltip_tween.kill()
	tooltip_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tooltip.modulate.a = 0.0
	tooltip.visible = true
	tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, 0.2)
