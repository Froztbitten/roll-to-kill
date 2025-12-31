extends Node2D

@export var spawn_area_height: float = 500.0

func _ready():
	arrange_enemies()

func arrange_enemies():
	var enemies = get_children().filter(func(c): return c is Enemy and not c._is_dead and not c.is_queued_for_deletion())
	var count = enemies.size()
	
	if count == 0:
		return

	# Calculate vertical spacing to center enemies within the spawn_area_height
	var step_y = spawn_area_height / (count + 1)
	var start_y = -spawn_area_height / 2.0
	
	for i in range(count):
		var enemy = enemies[i]
		# Calculate the target Y position relative to this container's origin
		var new_y = start_y + (step_y * (i + 1))
		# Position the enemy. X is 0 because it's centered on this container.
		enemy.position = Vector2(0, new_y)
		enemy.update_resting_state()
		
func clear_everything():
	for child in get_children():
		child.queue_free()
