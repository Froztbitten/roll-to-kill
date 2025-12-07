extends Node

func load_all_resources(folder_path: String) -> Array[Resource]:
	var files: Array[Resource] = []
	
	# 1. Open the directory
	var dir = DirAccess.open(folder_path)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			# 2. Check for resource files
			# Note: We check for .remap to support Exported Games (see below)
			if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
				
				# 3. Clean the filename for loading
				# (Godot's loader expects "file.tres", not "file.tres.remap")
				var load_path = folder_path + "/" + file_name.replace(".remap", "")
				
				# 4. Load and Add
				var resource = load(load_path)
				if resource:
					files.append(resource)
			
			file_name = dir.get_next()
	else:
		print("Error: Could not access folder " + folder_path)
		
	return files
