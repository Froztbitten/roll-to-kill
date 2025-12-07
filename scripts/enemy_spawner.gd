extends Node

@onready var enemy_container: Node2D = $Enemies

@export var encounter_pool: Array[EncounterData]
@export var minion_pool: Array[EnemyData]

const ENEMY_UI = preload("res://scenes/characters/enemy/enemy.tscn")

func _ready():
	encounter_pool.assign(Utils.load_all_resources("res://resources/encounters"))
	# Auto-populate the minion pool if it's empty, for convenience.
	if minion_pool.is_empty():
		var minion_paths = [
			"res://resources/enemies/d4.tres",
			"res://resources/enemies/d6.tres",
			"res://resources/enemies/d8.tres",
			"res://resources/enemies/d10.tres",
			"res://resources/enemies/d12.tres",
			"res://resources/enemies/d20.tres"
		]
		for path in minion_paths:
			var res = load(path)
			if res:
				minion_pool.append(res)

func spawn_random_encounter(encounter_type: EncounterData.EncounterType):	
	var chosen_encounter: EncounterData = encounter_pool.filter(
		func(encounter: EncounterData): return encounter.encounter_type == encounter_type).pick_random()
		
	print(encounter_pool.size())
	if chosen_encounter:
		var number_to_spawn = randi_range(chosen_encounter.min_count, chosen_encounter.max_count)
		return _spawn_enemies(chosen_encounter.enemy_types, number_to_spawn)
	
	push_warning("%s pool is empty!", [encounter_type])
	return []

func _spawn_enemies(enemy_types: Array[EnemyData], count: int) -> Array:
	var spawned_enemies = []
	var screen_size = get_viewport().get_visible_rect().size
	var spawn_x = screen_size.x * 0.8 # Move them slightly to the right
	
	# Define vertical margins to keep enemies from the screen edges
	var top_margin = 100
	var bottom_margin = 100
	var available_height = screen_size.y - top_margin - bottom_margin
	
	for i in range(count):
		var picked_enemy: EnemyData = enemy_types.pick_random()
		var enemy: Enemy = ENEMY_UI.instantiate()
		print(enemy)
		
		enemy.enemy_data = picked_enemy
		
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
	
	enemy_container.arrange_enemies()
	return spawned_enemies
