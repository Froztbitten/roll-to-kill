extends ProgressBar

@onready var label: Label = $Label
@onready var health_bar_fill: ProgressBar = $HealthBarFill
@onready var damage_preview_bar: ProgressBar = $DamagePreviewBar
@onready var shield_bar: ProgressBar = $ShieldBar

func update_display(current_value: int, new_max_value: int, block_value: int, intended_damage: int = 0):
	# The max value of the bars should accommodate health + block if it exceeds max health.
	var display_max = max(new_max_value, current_value + block_value)
	health_bar_fill.max_value = display_max
	damage_preview_bar.max_value = display_max
	shield_bar.max_value = display_max
	
	# The blue bar shows total effective health (HP + Block). It's drawn first.
	shield_bar.value = current_value + block_value
	
	# The red bar shows the current health. It's drawn on top of the shield bar.
	damage_preview_bar.value = current_value
	
	# The green bar shows what the health will be after damage. It's drawn on top of the red bar.
	health_bar_fill.value = current_value - intended_damage
	
	# Update the text label
	if block_value > 0:
		label.text = "%d+%d / %d" % [current_value, block_value, new_max_value]
	else:
		label.text = "%d / %d" % [current_value, new_max_value]
