extends ProgressBar

@onready var label: Label = $Label
@onready var health_bar_fill: ProgressBar = $HealthBarFill
@onready var damage_preview_bar: ProgressBar = $DamagePreviewBar
@onready var shield_bar: ProgressBar = $ShieldBar

var current_tween: Tween

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

func update_with_animation(old_hp: int, new_hp: int, old_block: int, new_block: int, new_max: int):
	# If a tween is already running, kill it to start the new one.
	if current_tween and current_tween.is_running():
		current_tween.kill()

	# Update label and max values instantly
	if new_block > 0:
		label.text = "%d+%d / %d" % [new_hp, new_block, new_max]
	else:
		label.text = "%d / %d" % [new_hp, new_max]
	var display_max = max(new_max, new_hp + new_block)
	health_bar_fill.max_value = display_max
	damage_preview_bar.max_value = display_max
	shield_bar.max_value = display_max

	# Green bar snaps to new health value (since this is for immediate damage/heal, not preview)
	if old_hp != new_hp or new_block < old_block:
		health_bar_fill.value = new_hp

	# Set animation start points
	damage_preview_bar.value = old_hp
	shield_bar.value = old_hp + old_block

	# Create a new tween to animate the bars catching up.
	# This tween should continue processing when the game is paused for UI screens,
	# so the health bar animation can complete in the background.
	current_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	current_tween.tween_property(damage_preview_bar, "value", new_hp, 0.6)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)\
		.set_delay(0.1)
	
	current_tween.parallel().tween_property(shield_bar, "value", new_hp + new_block, 0.4)\
		.set_ease(Tween.EASE_OUT)
