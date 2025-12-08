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
		return _spawn_enemies(chosen_encounter, number_to_spawn)
	
	push_warning("%s pool is empty!", [encounter_type])
	return []

func _spawn_enemies(encounter: EncounterData, count: int) -> Array:
	var spawned_enemies = []
	var enemies_to_spawn_data: Array[EnemyData] = []

	# Check for the special Goblin Warchief encounter
	var warchief_data: EnemyData = null
	var bodyguard_data: EnemyData = null
	var is_warchief_encounter = false
	for type in encounter.enemy_types:
		if type.enemy_name == "Goblin Warchief":
			warchief_data = type
			is_warchief_encounter = true
		elif type.enemy_name == "Ogre Bodyguard":
			bodyguard_data = type

	if is_warchief_encounter and warchief_data and bodyguard_data:
		# Special logic: 1 warchief, rest are bodyguards
		enemies_to_spawn_data.append(warchief_data)
		for i in range(count - 1):
			enemies_to_spawn_data.append(bodyguard_data)
	else:
		# Default logic: pick randomly from the encounter's pool
		for i in range(count):
			enemies_to_spawn_data.append(encounter.enemy_types.pick_random())

	# Shuffle the list so the leader doesn't always appear in the same position
	enemies_to_spawn_data.shuffle()
	
	for enemy_data in enemies_to_spawn_data:
		var enemy: Enemy = ENEMY_UI.instantiate()
		enemy.enemy_data = enemy_data
		enemy_container.add_child(enemy)
		spawned_enemies.append(enemy)
	
	enemy_container.arrange_enemies()
	return spawned_enemies
