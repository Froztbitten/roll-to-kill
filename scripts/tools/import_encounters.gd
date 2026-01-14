@tool
extends EditorScript

const ENCOUNTER_SAVE_PATH = "res://resources/encounters/"
const ENEMY_SEARCH_PATH = "res://resources/enemies/"
const CSV_PATH = "res://resources/encounters.csv"

func _run():
	if not FileAccess.file_exists(CSV_PATH):
		print("Error: CSV file not found at ", CSV_PATH)
		return

	var file = FileAccess.open(CSV_PATH, FileAccess.READ)
	if not file:
		print("Error opening CSV file.")
		return

	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(ENCOUNTER_SAVE_PATH):
		dir.make_dir_recursive(ENCOUNTER_SAVE_PATH)

	# Skip header
	file.get_csv_line("\t")

	var enemies_map = _build_enemy_map()
	var generated_count = 0

	while not file.eof_reached():
		var line = file.get_csv_line("\t")
		if line.size() < 2: continue

		var encounter_name = line[0]
		if encounter_name.is_empty(): continue

		# Try to load existing encounter to preserve other fields (Region, Type), or create new
		var safe_name = encounter_name.to_lower().replace(" ", "_").replace("'", "")
		var resource_path = ENCOUNTER_SAVE_PATH + safe_name + ".tres"
		var encounter: EncounterData
		
		if FileAccess.file_exists(resource_path):
			# Use CACHE_MODE_IGNORE to avoid getting a read-only cached resource
			encounter = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		else:
			encounter = EncounterData.new()
		
		var new_enemies: Array[Dictionary] = []
		
		# Iterate over enemy groups (Enemy, EVal, Min, Max)
		# Starting at index 1. Each group is 4 columns.
		# The CSV has 7 enemy slots based on the header structure provided.
		for i in range(7):
			var base_idx = 1 + (i * 4)
			if base_idx + 3 >= line.size(): break
			
			var char_name = line[base_idx]
			if char_name.is_empty(): continue
			
			var min_str = line[base_idx + 2]
			var max_str = line[base_idx + 3]
			
			var min_val = _parse_number(min_str)
			var max_val = _parse_number(max_str)
			
			# Find EnemyData
			var enemy_safe_name = char_name.to_lower().replace(" ", "_").replace("'", "")
			if enemies_map.has(enemy_safe_name):
				var enemy_res = enemies_map[enemy_safe_name]
				new_enemies.append({
					"data": enemy_res,
					"min": min_val,
					"max": max_val
				})
			else:
				push_warning("Encounter '%s': Could not find EnemyData for '%s' (expected at %s)" % [encounter_name, char_name, ENEMY_SEARCH_PATH + enemy_safe_name + ".tres"])
		
		encounter.enemies = new_enemies
		
		# Save
		ResourceSaver.save(encounter, resource_path)
		generated_count += 1

	print("Import Encounters complete. Updated %d encounters." % generated_count)

func _build_enemy_map() -> Dictionary:
	var map = {}
	var dir = DirAccess.open(ENEMY_SEARCH_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				var clean_name = file_name.replace(".tres", "").replace(".remap", "")
				var full_path = ENEMY_SEARCH_PATH + file_name.replace(".remap", "")
				map[clean_name] = load(full_path)
			file_name = dir.get_next()
	return map

func _parse_number(text: String) -> float:
	text = text.strip_edges()
	if text.is_empty(): return 0.0
	
	# Handle fractions like "1/100" or "1 1/3"
	if "/" in text:
		var parts = text.split(" ")
		var total = 0.0
		for part in parts:
			if "/" in part:
				var fraction = part.split("/")
				if fraction.size() == 2 and fraction[1].to_float() != 0:
					total += fraction[0].to_float() / fraction[1].to_float()
			else:
				total += part.to_float()
		return total
	
	return text.to_float()