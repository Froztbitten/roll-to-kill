extends Node2D

@onready var spawn_zone: ReferenceRect = $"../../ReferenceRect"

func _ready():
	arrange_enemies()

func arrange_enemies():
	var enemies = get_children()
	var count = enemies.size()
	
	if count == 0 or not spawn_zone:
		return

	# 1. Get the bounds from the UI node
	# We use global_position so it works even if the nodes are in different parents
	var zone_top = spawn_zone.global_position.y
	var zone_height = spawn_zone.size.y
	var zone_center_x = spawn_zone.global_position.x + (spawn_zone.size.x / 2.0)
	
	# 2. Calculate the spacing
	# (count + 1) creates even padding at top and bottom
	var step_y = zone_height / (count + 1)
	
	for i in range(count):
		var enemy = enemies[i]
		
		# 3. Calculate target Y position
		# Start at top edge + step down for each enemy
		var new_y = zone_top + (step_y * (i + 1))
		
		# 4. Apply Global Position
		# We force the X to be the center of the box, and Y to be the calculated step
		enemy.global_position = Vector2(zone_center_x, new_y)
		
func clear_everything():
	for child in get_children():
		child.queue_free()
