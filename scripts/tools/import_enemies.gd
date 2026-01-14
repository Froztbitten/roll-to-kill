@tool
extends EditorScript

const ENEMY_SAVE_PATH = "res://resources/enemies/"
const CSV_PATH = "res://resources/enemies.csv"

func _run():
	if not FileAccess.file_exists(CSV_PATH):
		print("Error: CSV file not found at ", CSV_PATH)
		return

	var file = FileAccess.open(CSV_PATH, FileAccess.READ)
	if not file:
		print("Error opening CSV file.")
		return

	# Ensure directories exist
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(ENEMY_SAVE_PATH):
		dir.make_dir_recursive(ENEMY_SAVE_PATH)

	# Skip header
	file.get_csv_line("\t") 

	var enemies_cache = {} # Name -> EnemyData
	var eval_sums = {} # Name -> float
	var eval_counts = {} # Name -> int
	
	while not file.eof_reached():
		var line = file.get_csv_line("\t")
		if line.size() < 5: continue # Empty line or invalid
		
		var char_name = line[4]
		
		if char_name.is_empty(): continue

		# Enemy Stats
		var min_hp = line[5].to_int()
		var hp_dice_sides = line[6].to_int()
		var hp_dice_count = line[7].to_int()
		
		# Action
		var action_name = line[10]
		var action_dice_count = line[11].to_int()
		var action_dice_sides = line[12].to_int()
		# line[13] is Eff (EVal calculation), ignored.
		var action_type_str = line[16]
		var additional_effects = line[17]
		var e_val = 0.0
		if line.size() > 19:
			e_val = line[19].to_float()
		
		# Create/Get EnemyData
		var enemy_data: EnemyData
		if enemies_cache.has(char_name):
			enemy_data = enemies_cache[char_name]
		else:
			enemy_data = EnemyData.new()
			enemy_data.enemy_name = char_name
			enemy_data.hp_dice_count = hp_dice_count
			enemy_data.hp_dice_sides = hp_dice_sides
			enemy_data.minimum_hp = min_hp
			enemy_data.action_pool = []
			enemy_data.passives = []
			
			var safe_char_name = char_name.to_lower().replace(" ", "_").replace("'", "")
			var sprite_path = "res://assets/ai/characters/" + safe_char_name + ".png"
			if FileAccess.file_exists(sprite_path):
				enemy_data.sprite_texture = load(sprite_path)
			else:
				push_warning("Sprite not found for '%s' at '%s'" % [char_name, sprite_path])
				
			enemies_cache[char_name] = enemy_data
			
		eval_sums[char_name] = eval_sums.get(char_name, 0.0) + e_val
		eval_counts[char_name] = eval_counts.get(char_name, 0) + 1

		# Create Action
		if not action_name.is_empty():
			var action = EnemyAction.new()
			action.action_name = action_name
			action.dice_count = action_dice_count
			action.dice_sides = action_dice_sides
			action.base_value = 0
			
			# Parse Action Type
			if "Attack" in action_type_str:
				if "Debuff" in action_type_str:
					action.action_type = EnemyAction.ActionType.DEBUFF
				else:
					action.action_type = EnemyAction.ActionType.ATTACK
			elif "Defense" in action_type_str:
				if "Shields All" in additional_effects or "allies" in additional_effects or "ally" in additional_effects:
					action.action_type = EnemyAction.ActionType.SUPPORT_SHIELD
				else:
					action.action_type = EnemyAction.ActionType.SHIELD
			elif "Heal" in action_type_str:
				action.action_type = EnemyAction.ActionType.HEAL_ALLY
			elif "Summon" in action_type_str:
				action.action_type = EnemyAction.ActionType.SPAWN_MINIONS
			elif "Buff" in action_type_str:
				action.action_type = EnemyAction.ActionType.BUFF
			elif "Flee" in action_type_str:
				action.action_type = EnemyAction.ActionType.FLEE
			elif "Nothing" in action_type_str:
				action.action_type = EnemyAction.ActionType.DO_NOTHING
			
			if "Piercing" in additional_effects or "Piercing" in action_type_str:
				action.action_type = EnemyAction.ActionType.PIERCING_ATTACK
			
			if "SD" in additional_effects or action_name == "De20nate":
				action.self_destructs = true
			
			# Parse Additional Effects for Status
			var lower_effects = additional_effects.to_lower()
			var lower_name = action_name.to_lower()
			
			if "bleed" in lower_effects: action.status_id = "bleeding"; action.charges = _extract_number(lower_effects, "bleed")
			elif "shrink" in lower_effects: action.status_id = "shrunk"; action.duration = _extract_number(lower_effects, "shrink")
			elif "daze" in lower_effects: action.status_id = "dazed"; action.charges = _extract_number(lower_effects, "daze")
			elif "silence" in lower_effects: action.status_id = "silence"; action.duration = _extract_number(lower_effects, "silence")
			elif "burn" in lower_effects: action.status_id = "burning"; action.charges = _extract_number(lower_effects, "burn")
			elif "taunt" in lower_effects: action.status_id = "taunting"; action.duration = _extract_number(lower_effects, "taunt")
			elif "charm" in lower_effects: action.status_id = "charming"; action.duration = _extract_number(lower_effects, "charm")
			elif "lock-down" in lower_effects: action.status_id = "lock_down"; action.duration = 1
			elif "crash out" in lower_name: action.status_id = "crash_out"; action.duration = -1
			elif "main character energy" in lower_name or "double tap" in lower_name: action.status_id = "main_character_energy"; action.charges = 1
			
			if "Passive" in action_type_str:
				enemy_data.passives.append(action)
			else:
				enemy_data.action_pool.append(action)



	# Save Resources with Gold Calculation
	for name in enemies_cache:
		var data = enemies_cache[name]
		
		# Calculate Gold
		var avg_eval = 0.0
		if eval_counts.has(name) and eval_counts[name] > 0:
			avg_eval = eval_sums[name] / eval_counts[name]
		
		var target_gold = avg_eval / 10.0
		# Variance: Use Dice (d6)
		# Avg d6 = 3.5
		# Dice Count = floor(target / 3.5)
		# Remainder = target - (count * 3.5)
		var dice_sides = 6
		var avg_die_val = 3.5
		var dice_count = floor(target_gold / avg_die_val)
		var remainder = target_gold - (dice_count * avg_die_val)
		
		# Ensure at least 0
		if dice_count < 0: dice_count = 0
		if remainder < 0: remainder = 0
		
		data.gold_dice = int(dice_count)
		data.gold_dice_sides = dice_sides
		data.gold_minimum = int(round(remainder))
		
		var safe_name = name.to_lower().replace(" ", "_").replace("'", "")
		ResourceSaver.save(data, ENEMY_SAVE_PATH + safe_name + ".tres")
	
	print("Import complete. Generated %d enemies." % [enemies_cache.size()])

func _extract_number(text: String, keyword: String) -> int:
	var regex = RegEx.new()
	regex.compile(keyword + "\\s*(\\d+)")
	var result = regex.search(text)
	if result:
		return result.get_string(1).to_int()
	return 1
