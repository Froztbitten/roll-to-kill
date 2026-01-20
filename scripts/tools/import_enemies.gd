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
		if line.size() < 24: continue # Ensure we have enough columns
		
		var char_name = line[4]
		
		if char_name.is_empty(): continue

		# Enemy Stats
		var min_hp = line[5].to_int()
		var hp_dice_count = line[6].to_int() # N
		var hp_dice_sides = line[7].to_int() # M
		
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
		
		# Gold
		if line.size() > 28:
			var min_gold = line[26].to_int()
			var gold_dice_count = line[27].to_int()
			var gold_dice_sides = line[28].to_int()
			
			enemy_data.gold_minimum = min_gold
			enemy_data.gold_dice = gold_dice_count
			enemy_data.gold_dice_sides = gold_dice_sides

		# Parse Passive
		var p_name = line[10]
		if not p_name.is_empty():
			var has_passive = false
			for p in enemy_data.passives:
				if p.action_name == p_name:
					has_passive = true
					break
			
			if not has_passive:
				var passive = EnemyAction.new()
				passive.action_name = p_name
				passive.action_type = EnemyAction.ActionType.BUFF # Default for passive
				
				var p_type = line[11].to_lower()
				var p_val = line[12].to_int()
				
				if "thorns" in p_type:
					passive.status_id = "spiky"
					passive.charges = p_val
				elif "rage" in p_type:
					passive.status_id = "raging"
					passive.duration = -1
				elif "revive" in p_type:
					passive.status_id = "main_character_energy"
					passive.charges = 1
				elif "reanimate" in p_type:
					passive.status_id = "reanimate_passive"
					passive.duration = -1
				elif "crash out" in p_name.to_lower():
					passive.status_id = "crash_out"
					passive.duration = -1
				
				enemy_data.passives.append(passive)

		# Create Action
		var action_name = line[13]
		if not action_name.is_empty():
			var action = EnemyAction.new()
			action.action_name = action_name
			action.dice_count = line[14].to_int()
			action.dice_sides = line[15].to_int()
			
			var action_type_str = line[19]
			var additional_effects = line[23]
			var applied_effect_str = ""
			if line.size() > 22: applied_effect_str = line[22].strip_edges()
			
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
			
			# Parse Applied Effect Column
			if not applied_effect_str.is_empty():
				var clean_effect = applied_effect_str.to_lower().replace(" ", "_")
				
				# Map variations to StatusLibrary IDs
				if clean_effect == "silenced": clean_effect = "silence"
				elif clean_effect == "charmed": clean_effect = "charming"
				elif clean_effect == "taunted": clean_effect = "taunting"
				elif clean_effect == "locked_down": clean_effect = "lock_down"
				elif clean_effect == "ri-posted_up": clean_effect = "ri-posted up"
				
				if clean_effect == "bone_apart":
					pass # Bone Apart is a self-damage effect, not a status.
				else:
					print("Setting status_id '%s' for action '%s'" % [clean_effect, action_name])
					action.status_id = clean_effect
				
				var val = 1 # Default to 1 as DVal (col 25) is an evaluation metric, not duration
				
				if clean_effect in ["bleeding", "burning", "spiky", "dazed", "echoing_impact", "main_character_energy", "ri-posted up"]:
					action.charges = val
				else:
					action.duration = val

			# Parse Additional Effects for Status
			if action.status_id == "":
				var lower_effects = additional_effects.to_lower()
				if "bleed" in lower_effects: action.status_id = "bleeding"; action.charges = _extract_number(lower_effects, "bleed")
				elif "shrink" in lower_effects: action.status_id = "shrunk"; action.duration = _extract_number(lower_effects, "shrink")
				elif "daze" in lower_effects: action.status_id = "dazed"; action.charges = _extract_number(lower_effects, "daze")
				elif "silence" in lower_effects: action.status_id = "silence"; action.duration = _extract_number(lower_effects, "silence")
				elif "burn" in lower_effects: action.status_id = "burning"; action.charges = _extract_number(lower_effects, "burn")
				elif "taunt" in lower_effects: action.status_id = "taunting"; action.duration = _extract_number(lower_effects, "taunt")
				elif "charm" in lower_effects: action.status_id = "charming"; action.duration = _extract_number(lower_effects, "charm")
				elif "lock-down" in lower_effects: action.status_id = "lock_down"; action.duration = 1
			
			if "bone apart" in additional_effects.to_lower() or "bone apart" in applied_effect_str.to_lower():
				action.self_damage = 2
			
			enemy_data.action_pool.append(action)

	# Save Resources with Gold Calculation
	for name in enemies_cache:
		var data = enemies_cache[name]
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
