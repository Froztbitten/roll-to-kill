extends HBoxContainer

const STATUS_ICON_SCENE = preload("res://scenes/ui/status_icon.tscn")

func update_display(statuses: Dictionary):
	# Clear existing icons
	for child in get_children():
		child.queue_free()
	
	# Add new icons for current statuses
	for status_effect in statuses:
		var icon_instance = STATUS_ICON_SCENE.instantiate()
		add_child(icon_instance)
		var value = statuses[status_effect]
		icon_instance.set_status(status_effect, value)
