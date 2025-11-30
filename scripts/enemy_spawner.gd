extends Node

@export var encounter_pool: Array[Encounter]
@export var boss_enemy_scene: PackedScene
@export var enemy_container: Node

func spawn_regular_enemy():
	if encounter_pool.is_empty():
		push_warning("Encounter pool is empty!")
		return []
	
	var chosen_encounter: Encounter = encounter_pool.pick_random()
	var number_to_spawn = randi_range(chosen_encounter.min_count, chosen_encounter.max_count)
	
	return _spawn_enemies(chosen_encounter.enemy_scene, number_to_spawn)

func spawn_boss():
	var enemy = boss_enemy_scene.instantiate()
	return _spawn_enemies(boss_enemy_scene, 1)

func _spawn_enemies(scene: PackedScene, count: int) -> Array:
	var spawned_enemies = []
	var screen_size = get_viewport().get_visible_rect().size
	var spawn_x = screen_size.x * 0.8 # Move them slightly to the right
	
	# Define vertical margins to keep enemies from the screen edges
	var top_margin = 100
	var bottom_margin = 100
	var available_height = screen_size.y - top_margin - bottom_margin
	
	for i in range(count):
		var enemy = scene.instantiate()
		var spawn_y: float
		if count == 1:
			# If there's only one enemy, center it in the available space
			spawn_y = top_margin + available_height / 2
		else:
			# If there are multiple, distribute them evenly
			spawn_y = top_margin + (float(i) / (count - 1)) * available_height
		enemy.position = Vector2(spawn_x, spawn_y)
		enemy_container.add_child(enemy)
		spawned_enemies.append(enemy)
	return spawned_enemies
