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
		if res is EncounterData and res.resource_path.get_file() != "tutorial_encounter.tres":
			filtered_encounters.append(res)
	encounter_pool.assign(filtered_encounters)

	# Auto-populate the minion pool if it's empty, for convenience.
	if minion_pool.is_empty():
		var minion_paths = [
			"res://resources/enemies/dice/d4.tres",
			"res://resources/enemies/dice/d6.tres",
			"res://resources/enemies/dice/d8.tres",
			"res://resources/enemies/dice/d10.tres",
			"res://resources/enemies/dice/d12.tres",
			"res://resources/enemies/dice/d20.tres"
		]
		for path in minion_paths:
			var res = load(path)
			if res:
				minion_pool.append(res)
	# Auto-populate the invention pool if it's empty, for convenience.
	if invention_pool.is_empty():
		var invention_paths = [
			"res://resources/enemies/inventions/koko_the_pelican.tres",
			"res://resources/enemies/inventions/wick_walk.tres",
			"res://resources/enemies/inventions/shield_generator.tres"
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
		var number_to_spawn = randi_range(chosen_encounter.min_count, chosen_encounter.max_count)
		return _spawn_enemies(chosen_encounter, number_to_spawn)
	
	push_warning("%s pool is empty!", [encounter_type])
	return []

func spawn_specific_encounter(encounter: EncounterData) -> Array:
	if not encounter:
		push_error("spawn_specific_encounter: EncounterData is null.")
		return []
	var number_to_spawn = randi_range(encounter.min_count, encounter.max_count)
	return _spawn_enemies(encounter, number_to_spawn)

func _spawn_enemies(encounter: EncounterData, count: int) -> Array:
	var spawned_enemies = []
	var enemies_to_spawn_data: Array[EnemyData] = []
	var should_shuffle = true

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
	elif encounter.resource_path.get_file() == "gnomes.tres":
		# Special logic for Gnomes encounter: 2-3 tinkerers. If 2, add a random invention.
		var tinkerer_data = encounter.enemy_types[0]
		for i in range(count):
			enemies_to_spawn_data.append(tinkerer_data)
		
		if count == 2 and not invention_pool.is_empty():
			var random_invention = invention_pool.pick_random()
			enemies_to_spawn_data.append(random_invention)
		elif count == 2:
			push_warning("Invention pool is empty, cannot add to Gnomes encounter.")
	elif encounter.resource_path.get_file() == "chivalry_cavalry.tres":
		# Special logic for Chivalry Calvalry: Always 1 White Knight, 1 Femme Fatale, 1 Keyboard Warrior in order.
		enemies_to_spawn_data.append_array(encounter.enemy_types)
		should_shuffle = false
	else:
		# Default logic: pick randomly from the encounter's pool
		for i in range(count):
			enemies_to_spawn_data.append(encounter.enemy_types.pick_random())

	# Shuffle the list so the leader doesn't always appear in the same position
	if should_shuffle:
		enemies_to_spawn_data.shuffle()
	
	for enemy_data in enemies_to_spawn_data:
		var enemy: Enemy = ENEMY_UI.instantiate()
		enemy.enemy_data = enemy_data
		# Hide the intent display immediately on spawn to prevent a 1-frame flicker of default data.
		enemy.get_node("Visuals/EnemyIntentDisplay").visible = false
		enemy_container.add_child(enemy)
		spawned_enemies.append(enemy)

	return spawned_enemies
