extends Node

@onready var enemy_container: Node2D = $Enemies

@export var encounter_pool: Array[EncounterData]
@export var minion_pool: Array[EnemyData]
@export var invention_pool: Array[EnemyData]

const ENEMY_UI = preload("res://scenes/characters/enemy/enemy.tscn")

func _ready():
	var all_encounters = Utils.load_all_resources("res://resources/encounters")
	var filtered_encounters: Array[EncounterData] = []
	for res in all_encounters:
		if res is EncounterData and res.resource_path.get_file() != "tutorial.tres":
			filtered_encounters.append(res)
	encounter_pool.assign(filtered_encounters)

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
	# Auto-populate the invention pool if it's empty, for convenience.
	if invention_pool.is_empty():
		var invention_paths = [
			"res://resources/enemies/koko_the_pelican.tres",
			"res://resources/enemies/wick-wock.tres",
			"res://resources/enemies/shield_generator.tres"
		]
		for path in invention_paths:
			var res = load(path)
			if res:
				invention_pool.append(res)

func spawn_random_encounter(encounter_type: EncounterData.EncounterType):	
	var chosen_encounter: EncounterData = encounter_pool.filter(
		func(encounter: EncounterData): return encounter.encounter_type == encounter_type).pick_random()
		
	print(encounter_pool.size())
	if chosen_encounter:
		return _spawn_enemies(chosen_encounter)
	
	push_warning("%s pool is empty!", [encounter_type])
	return []

func spawn_specific_encounter(encounter: EncounterData) -> Array:
	if not encounter:
		push_error("spawn_specific_encounter: EncounterData is null.")
		return []
	return _spawn_enemies(encounter)

func _spawn_enemies(encounter: EncounterData) -> Array:
	var spawned_enemies = []
	var enemies_to_spawn_data: Array[EnemyData] = []

	for entry in encounter.enemies:
		var enemy_data = entry["data"]
		var min_val = entry["min"]
		var max_val = entry["max"]
		
		# Determine count based on range and probability
		var val = randf_range(min_val, max_val)
		var count = floor(val)
		# Probabilistic rounding for fractional part
		if randf() < (val - count):
			count += 1
		
		for i in range(count):
			enemies_to_spawn_data.append(enemy_data)
	
	for enemy_data in enemies_to_spawn_data:
		var enemy: Enemy = ENEMY_UI.instantiate()
		enemy.enemy_data = enemy_data
		# Hide the intent display immediately on spawn to prevent a 1-frame flicker of default data.
		enemy.get_node("Visuals/EnemyIntentDisplay").visible = false
		enemy_container.add_child(enemy)
		spawned_enemies.append(enemy)

	return spawned_enemies
