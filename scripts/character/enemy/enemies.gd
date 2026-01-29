extends Node2D

@export var spawn_area_width: float = 800.0

func _ready():
	arrange_enemies()

func arrange_enemies(animate: bool = false):
	var enemies = get_children().filter(func(c): return c is Enemy and not c._is_dead and not c.is_queued_for_deletion())
	var count = enemies.size()
	
	if count == 0:
		return

	# Determine the target scale factor. New enemies default to 1.0.
	# We look for any existing enemy that has been scaled to the viewport to find the correct factor.
	var scale_factor = 1.0
	for enemy in enemies:
		if not is_equal_approx(enemy.current_scale_factor, 1.0):
			scale_factor = enemy.current_scale_factor
			break

	# Calculate horizontal spacing to center enemies within the spawn_area_width
	var step_x = spawn_area_width / (count + 1)
	var start_x = -spawn_area_width / 2.0

	# Calculate crowding to prevent overlap
	# Base sprite is 140px width. Allow some padding (e.g. 180px total width per enemy).
	var enemy_visual_width = 180.0 * scale_factor
	var crowd_scale = 1.0
	
	if enemy_visual_width > step_x:
		crowd_scale = step_x / enemy_visual_width
		# Clamp to a minimum reasonable size
		crowd_scale = max(crowd_scale, 0.4)
	
	for i in range(count):
		var enemy = enemies[i]
		
		# Ensure the enemy is scaled to the screen size first (fixes newly spawned minions)
		if not is_equal_approx(enemy.current_scale_factor, scale_factor):
			enemy.update_scale(scale_factor)
		
		# Apply crowd scale to the enemy node itself
		enemy.scale = Vector2.ONE * crowd_scale
		
		# Calculate the target X position relative to this container's origin
		var new_x = start_x + (step_x * (i + 1))
		# Position the enemy. Y is 0 because it's centered on this container.
		var target_pos = Vector2(new_x, 0)
		
		if animate and enemy.is_inside_tree():
			var tween = create_tween()
			tween.tween_property(enemy, "position", target_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			enemy._resting_position = target_pos
		else:
			enemy.position = target_pos
			enemy.update_resting_state()
		
func clear_everything():
	for child in get_children():
		child.queue_free()
