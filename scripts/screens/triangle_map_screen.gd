extends Control

signal node_selected(node_data)
signal open_quest_board
signal open_shop
signal open_forge
signal open_dice_shop
signal open_inn

const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")
const TriangleButton = preload("res://scripts/ui/triangle_button.gd")

@onready var map_container = $ScrollContainer/MapContainer
@onready var scroll_container = $ScrollContainer
@onready var player_icon = $ScrollContainer/MapContainer/PlayerIcon

var grid_data = {}
var current_node = null
var grid_width = 30
var grid_height = 12
var triangle_size = 100.0

var turns_left = 21
var turn_count = 0
var moves_remaining = 0
var path_line: Line2D
var full_path_line: Line2D
var distance_label: Label
var full_distance_label: Label
var turn_limit_label: Label
var moves_label: Label
var is_moving = false
var is_rolling = false
var current_tween: Tween
var pending_roll_result = 0
var current_roll_overlay: Control
var pending_movement_path = []
var final_moves_remaining = 0
var ui_layer: Control
var mountain_texture: ImageTexture
var water_texture: ImageTexture
var grass_texture: ImageTexture
var town_ui: Control

func _input(event):
	if not visible: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		if is_rolling:
			_skip_roll_animation()
			get_viewport().set_input_as_handled()
		elif is_moving:
			_skip_movement_animation()
			get_viewport().set_input_as_handled()

func _ready():
	visible = false
	visibility_changed.connect(func(): if ui_layer: ui_layer.visible = visible)
	
	# Setup Static UI
	ui_layer = Control.new()
	ui_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.visible = visible
	add_child(ui_layer)
	
	# Turn Limit Label (Top Right)
	var limit_container = MarginContainer.new()
	limit_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	limit_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	limit_container.add_theme_constant_override("margin_top", 20)
	limit_container.add_theme_constant_override("margin_right", 80)
	ui_layer.add_child(limit_container)
	
	turn_limit_label = Label.new()
	turn_limit_label.add_theme_font_size_override("font_size", 32)
	turn_limit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	turn_limit_label.add_theme_constant_override("outline_size", 4)
	turn_limit_label.text = "Turns: 20"
	limit_container.add_child(turn_limit_label)
	
	# Movement Label on Player
	moves_label = Label.new()
	moves_label.text = ""
	moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_label.add_theme_font_size_override("font_size", 24)
	moves_label.add_theme_color_override("font_outline_color", Color.BLACK)
	moves_label.add_theme_constant_override("outline_size", 4)
	moves_label.custom_minimum_size = Vector2(100, 30)
	moves_label.position = Vector2(player_icon.size.x / 2.0 - 50, -35)
	player_icon.add_child(moves_label)
	
	# Initialize Procedural Textures
	# We generate Images synchronously to ensure they are ready immediately.
	var m_noise = FastNoiseLite.new()
	m_noise.seed = randi()
	m_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	m_noise.frequency = 0.02
	m_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	m_noise.fractal_octaves = 4
	
	var m_gradient = Gradient.new()
	m_gradient.set_color(0, Color(0.2, 0.2, 0.25))
	m_gradient.set_color(1, Color(0.7, 0.7, 0.75))
	mountain_texture = _create_noise_texture(m_noise, m_gradient)
	
	var w_noise = FastNoiseLite.new()
	w_noise.seed = randi()
	w_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	w_noise.frequency = 0.02
	
	var w_gradient = Gradient.new()
	w_gradient.set_color(0, Color(0.1, 0.3, 0.7))
	w_gradient.set_color(1, Color(0.2, 0.5, 0.9))
	water_texture = _create_noise_texture(w_noise, w_gradient)
	
	var g_noise = FastNoiseLite.new()
	g_noise.seed = randi()
	g_noise.frequency = 0.05
	var g_gradient = Gradient.new()
	g_gradient.set_color(0, Color(0.1, 0.25, 0.1))
	g_gradient.set_color(1, Color(0.2, 0.35, 0.2))
	grass_texture = _create_noise_texture(g_noise, g_gradient)
	
	_create_town_ui()

func _create_noise_texture(noise: FastNoiseLite, gradient: Gradient) -> ImageTexture:
	var size = 512
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	for y in range(size):
		for x in range(size):
			var value = noise.get_noise_2d(x, y)
			# Normalize from [-1, 1] to [0, 1]
			var normalized = (value + 1.0) / 2.0
			var color = gradient.sample(normalized)
			image.set_pixel(x, y, color)
			
	return ImageTexture.create_from_image(image)

func _create_town_ui():
	town_ui = Control.new()
	town_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.visible = false
	ui_layer.add_child(town_ui)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_ui.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	var title = TextureRect.new()
	title.texture = load("res://assets/ai/ui/town_banner.svg")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2(600, 187)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(title)
	
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 30)
	vbox.add_child(grid)
	
	var create_town_btn = func(text: String, color: Color, icon_path: String):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(220, 180)
		
		var style = StyleBoxFlat.new()
		style.bg_color = color
		style.border_width_bottom = 6
		style.border_color = color.darkened(0.3)
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_right = 12
		style.corner_radius_bottom_left = 12
		
		btn.add_theme_stylebox_override("normal", style)
		
		var hover_style = style.duplicate()
		hover_style.bg_color = color.lightened(0.1)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style = style.duplicate()
		pressed_style.bg_color = color.darkened(0.1)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		
		var content = VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 10)
		btn.add_child(content)
		
		if icon_path != "":
			var icon = TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(80, 80)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(icon)
			
		var lbl = Label.new()
		lbl.text = text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		content.add_child(lbl)
		
		grid.add_child(btn)
		return btn

	create_town_btn.call("Quest Board", Color(0.55, 0.35, 0.15), "res://assets/ai/ui/quest_board.svg").pressed.connect(func(): emit_signal("open_quest_board"))
	create_town_btn.call("Spell Shop", Color(0.4, 0.2, 0.6), "res://assets/ai/ui/spell_shop.svg").pressed.connect(func(): emit_signal("open_shop"))
	create_town_btn.call("Forge", Color(0.7, 0.3, 0.1), "res://assets/ai/ui/dice_forge.svg").pressed.connect(func(): emit_signal("open_forge"))
	create_town_btn.call("Dice Shop", Color(0.8, 0.7, 0.1), "res://assets/ai/ui/dice_shop.svg").pressed.connect(func(): emit_signal("open_dice_shop"))
	create_town_btn.call("Inn", Color(0.2, 0.5, 0.2), "res://assets/ai/ui/inn.svg").pressed.connect(func(): emit_signal("open_inn"))
	
	var leave_btn = Button.new()
	leave_btn.text = "Leave Town"
	leave_btn.custom_minimum_size = Vector2(200, 60)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.add_theme_font_size_override("font_size", 24)
	leave_btn.pressed.connect(func(): town_ui.visible = false)
	vbox.add_child(leave_btn)

func _process(delta):
	# Animate water UVs
	if visible:
		var time = Time.get_ticks_msec() / 1000.0
		var offset = Vector2(time * 0.05, time * 0.02)
		for child in map_container.get_children():
			if child is TriangleButton:
				for sub in child.get_children():
					if sub is Polygon2D and sub.texture == water_texture:
						# Shift UVs
						var uvs = sub.uv
						for i in range(uvs.size()):
							uvs[i] += Vector2(delta * 0.1, delta * 0.05)
						sub.uv = uvs
	
	# Animate Turn Limit Warning
	if turns_left <= 5 and turn_limit_label:
		var intensity = (6.0 - float(turns_left)) * 0.5
		turn_limit_label.pivot_offset = turn_limit_label.size / 2.0
		turn_limit_label.rotation_degrees = randf_range(-1.0, 1.0) * intensity
		# Note: Scale and Color are set in start_turn()

func generate_new_map():
	grid_data.clear()
	current_node = null
	
	# 1. Initialize Grid
	for child in map_container.get_children():
		if child != player_icon:
			child.queue_free()
			
	turns_left = 21
	var height = triangle_size * sqrt(3) / 2.0
	var total_grid_width = (grid_width * triangle_size / 2.0) + (triangle_size / 2.0)
	var viewport_size = get_viewport_rect().size
	var min_width = max(total_grid_width + 100, viewport_size.x)
	map_container.custom_minimum_size = Vector2(min_width, grid_height * height + 100)
	var x_offset = (min_width - total_grid_width) / 2.0
	var y_offset = 50.0
	
	for row in range(grid_height):
		for col in range(grid_width):
			var points_up = (row + col) % 2 == 0
			var x_pos = x_offset + col * (triangle_size / 2.0) + (triangle_size / 2.0)
			var y_pos = 0.0
			if points_up:
				y_pos = y_offset + row * height + (height * 2.0 / 3.0)
			else:
				y_pos = y_offset + row * height + (height / 3.0)
			
			var node = {
				"row": row,
				"col": col,
				"type": "normal", # Default
				"pos": Vector2(x_pos, y_pos),
				"points_up": points_up,
				"cleared": false,
				"button": null
			}
			grid_data[Vector2(row, col)] = node

	# 2. Place Start (Bottom Center)
	var start_row = grid_height - 1
	var start_col = int(grid_width / 2.0)
	var start_node = grid_data[Vector2(start_row, start_col)]
	start_node.type = "start"
	current_node = start_node
	start_node.cleared = true

	# 3. Place Town (Middle rows, 3 wide)
	var town_row = randi_range(int(grid_height * 0.3), int(grid_height * 0.6))
	var town_col = randi_range(2, grid_width - 5)
	var town_nodes = []
	for i in range(3):
		var n = grid_data[Vector2(town_row, town_col + i)]
		n.type = "town"
		town_nodes.append(n)

	# 4. Place Goblin Camp (2 triangles, near water, no mountains)
	# We pick a spot first, then enforce terrain constraints later
	var valid_goblin_starts = _get_nodes_in_range(town_nodes, 4, 8)
	var goblin_nodes = _pick_random_cluster(2, ["start", "town"], valid_goblin_starts)
	for n in goblin_nodes: n.type = "goblin_camp"
	
	# 5. Place Dragon's Roost (2 triangles, near mountains)
	var valid_dragon_starts = _get_nodes_in_range(town_nodes, 4, 8)
	var dragon_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp"], valid_dragon_starts)
	for n in dragon_nodes: n.type = "dragon_roost"

	# 6. Place Crypt (2 triangles, no water in 2 tile radius)
	var crypt_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost"])
	for n in crypt_nodes: n.type = "crypt"

	# 7. Place Dwarven Forge (2 triangles, 5 mountains in 2 radius, 1 touching)
	var dwarven_forge_nodes = _pick_random_cluster(2, ["start", "town", "goblin_camp", "dragon_roost", "crypt"])
	for n in dwarven_forge_nodes: n.type = "dwarven_forge"

	# 8. Generate Terrain & Enforce Constraints
	var goblin_zone = _get_nodes_in_radius(goblin_nodes, 2)
	var dragon_zone = _get_nodes_in_radius(dragon_nodes, 2)
	var crypt_zone = _get_nodes_in_radius(crypt_nodes, 2)
	var dwarven_forge_zone = _get_nodes_in_radius(dwarven_forge_nodes, 2)
	
	# Fill constraints first
	# Goblin: Need 1 water (clump of 3)
	# Ensure we don't place water in the crypt zone
	var water_candidates = goblin_zone.filter(func(n): return n.type == "normal" and not n in crypt_zone)
	if not water_candidates.is_empty():
		_grow_clump(water_candidates.pick_random(), "water", 3, 4, crypt_zone)
	
	# Dragon: Need 4 mountains (clump of 4)
	var mountain_candidates = dragon_zone.filter(func(n): return n.type == "normal")
	if not mountain_candidates.is_empty():
		_grow_clump(mountain_candidates.pick_random(), "mountain", 4, 5, goblin_zone, dragon_zone)
		
	# Dwarven Forge: Need 1 touching mountain, 5 total in radius 2
	var forge_neighbors = []
	for fn in dwarven_forge_nodes:
		for n in get_neighbors(fn):
			if n.type == "normal" and not n in forge_neighbors:
				forge_neighbors.append(n)
	
	if not forge_neighbors.is_empty():
		_grow_clump(forge_neighbors.pick_random(), "mountain", 5, 7, goblin_zone, dwarven_forge_zone)

	# Random fill rest
	var keys = grid_data.keys()
	keys.shuffle()
	for pos in keys:
		var node = grid_data[pos]
		if node.type != "normal": continue
		
		# Goblin constraint: No mountains in radius 2
		if node in goblin_zone:
			if randf() < 0.05: _grow_clump(node, "water", 3, 5, crypt_zone)
			continue
			
		var rand = randf()
		if rand < 0.04: _grow_clump(node, "mountain", 3, 6, goblin_zone)
		elif rand < 0.08: _grow_clump(node, "water", 3, 6, crypt_zone)

	# 9. Ensure Connectivity
	_ensure_connectivity()

	draw_map()
	start_turn()

func draw_map():
	var height = triangle_size * sqrt(3) / 2.0
	var crypt_nodes_for_visuals = []
	var goblin_nodes_for_visuals = []
	var dragon_nodes_for_visuals = []
	var town_nodes_for_visuals = []
	var dwarven_forge_nodes_for_visuals = []
	
	var shadow_container = CanvasGroup.new()
	shadow_container.modulate = Color(1, 1, 1, 0.3)
	map_container.add_child(shadow_container)
	map_container.move_child(shadow_container, 0)
	
	# Full Path Line (Red)
	full_path_line = Line2D.new()
	full_path_line.width = 5
	full_path_line.default_color = Color.RED
	full_path_line.z_index = 49
	map_container.add_child(full_path_line)
	
	# Path Line
	path_line = Line2D.new()
	path_line.width = 5
	path_line.default_color = Color.WHITE
	path_line.z_index = 50
	map_container.add_child(path_line)
	
	# Distance Label
	distance_label = Label.new()
	distance_label.z_index = 100
	distance_label.add_theme_font_size_override("font_size", 24)
	distance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	distance_label.add_theme_constant_override("outline_size", 4)
	distance_label.visible = false
	map_container.add_child(distance_label)
	
	# Full Distance Label
	full_distance_label = Label.new()
	full_distance_label.z_index = 100
	full_distance_label.add_theme_font_size_override("font_size", 24)
	full_distance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	full_distance_label.add_theme_constant_override("outline_size", 4)
	full_distance_label.visible = false
	map_container.add_child(full_distance_label)
	
	for pos in grid_data:
		var node = grid_data[pos]
		var btn = TriangleButton.new()
		btn.triangle_size = triangle_size
		btn.points_up = node.points_up
		btn.size = Vector2(triangle_size, triangle_size * sqrt(3) / 2.0)
		btn.position = node.pos - btn.size / 2.0
		btn.flat = true
		btn.self_modulate = Color(1, 1, 1, 0) # Ensure button background is invisible
		var center_offset = btn.size / 2.0
		
		var vertices = PackedVector2Array()
		if node.points_up:
			vertices = PackedVector2Array([
				Vector2(0, -2.0 / 3.0 * height),
				Vector2(triangle_size / 2.0, 1.0 / 3.0 * height),
				Vector2(-triangle_size / 2.0, 1.0 / 3.0 * height)
			])
		else:
			vertices = PackedVector2Array([
				Vector2(0, 2.0 / 3.0 * height),
				Vector2(-triangle_size / 2.0, -1.0 / 3.0 * height),
				Vector2(triangle_size / 2.0, -1.0 / 3.0 * height)
			])
		
		# Create base polygon for all nodes
		var poly = Polygon2D.new()
		poly.polygon = vertices
		poly.position = center_offset
		
		# Calculate UVs based on world position for seamless tiling
		var uvs = PackedVector2Array()
		for v in vertices:
			uvs.append((node.pos + v) / 128.0)
		poly.uv = uvs
		
		btn.add_child(poly)
		node["bg"] = poly
		
		if node.type == "mountain":
			var shadow = Polygon2D.new()
			shadow.polygon = vertices
			shadow.color = Color.BLACK
			shadow.position = node.pos + Vector2(-10, 10)
			shadow_container.add_child(shadow)

		if node.type == "mountain":
			poly.color = Color.WHITE
			poly.texture = mountain_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Add shadow to make it look pointy
			var shadow = Polygon2D.new()
			var s_verts = PackedVector2Array()
			if node.points_up:
				s_verts.append(vertices[0]) # Top
				s_verts.append(vertices[2]) # Bottom Left
				s_verts.append(Vector2(0, 1.0 / 3.0 * height)) # Bottom Mid
			else:
				s_verts.append(vertices[0]) # Bottom
				s_verts.append(vertices[1]) # Top Left
				s_verts.append(Vector2(0, -1.0 / 3.0 * height)) # Top Mid
			shadow.polygon = s_verts
			shadow.color = Color(0, 0, 0, 0.3)
			shadow.position = center_offset
			btn.add_child(shadow)
		elif node.type == "water":
			poly.color = Color.WHITE
			poly.texture = water_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		elif node.type == "crypt":
			poly.color = Color(0.5, 0.5, 0.55, 1.0) # Gray fill
			crypt_nodes_for_visuals.append(node)
		elif node.type == "goblin_camp":
			poly.color = Color(0.6, 0.8, 0.6, 1.0) # Pale green
			goblin_nodes_for_visuals.append(node)
		elif node.type == "dragon_roost":
			poly.color = Color(0.95, 0.75, 0.3, 1.0) # Pale yellowish orange
			dragon_nodes_for_visuals.append(node)
		elif node.type == "town":
			poly.color = Color(0.4, 0.9, 0.4, 1.0) # Light Green
			town_nodes_for_visuals.append(node)
		elif node.type == "dwarven_forge":
			poly.color = Color(0.55, 0.27, 0.07, 1.0) # Bronze/SaddleBrown
			dwarven_forge_nodes_for_visuals.append(node)
		
		if node.type == "crypt" or node.type == "goblin_camp" or node.type == "dragon_roost" or node.type == "town" or node.type == "mountain" or node.type == "dwarven_forge":
				# Draw outlines only on edges NOT shared with another node of the same type
				var r = node.row
				var c = node.col
				var neighbors_check = []
				var edges_indices = []
				
				if node.points_up:
					# Edges: Right (0-1), Bottom (1-2), Left (2-0)
					neighbors_check = [Vector2(r, c+1), Vector2(r+1, c), Vector2(r, c-1)]
					edges_indices = [[0, 1], [1, 2], [2, 0]]
				else:
					# Edges: Left (0-1), Top (1-2), Right (2-0)
					neighbors_check = [Vector2(r, c-1), Vector2(r-1, c), Vector2(r, c+1)]
					edges_indices = [[0, 1], [1, 2], [2, 0]]
				
				for i in range(3):
					var n_pos = neighbors_check[i]
					# Draw edge if neighbor is NOT the same type (or doesn't exist)
					if not grid_data.has(n_pos) or grid_data[n_pos].type != node.type:
						var line = Line2D.new()
						line.points = PackedVector2Array([vertices[edges_indices[i][0]], vertices[edges_indices[i][1]]])
						line.width = 3.0
						if node.type == "crypt":
							line.default_color = Color(0.2, 0.2, 0.25, 1.0) # Darker grey outline
						elif node.type == "goblin_camp":
							line.default_color = Color(0.4, 0.25, 0.1, 1.0) # Brown outline
						elif node.type == "dragon_roost":
							line.default_color = Color.CRIMSON # Crimson red border
						elif node.type == "town":
							line.default_color = Color(0.1, 0.4, 0.1, 1.0) # Dark green border
						elif node.type == "mountain":
							line.default_color = Color(0.2, 0.2, 0.2, 1.0) # Dark grey border
						elif node.type == "dwarven_forge":
							line.default_color = Color(0.3, 0.1, 0.0, 1.0) # Dark Rust border
						line.position = center_offset
						btn.add_child(line)
		elif node.type == "start":
			poly.color = Color(1.0, 1.0, 1.0, 1.0)
			var lbl = Label.new()
			lbl.text = node.type.capitalize().replace("_", " ")
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 4)
			lbl.position = center_offset - Vector2(50, 15)
			lbl.size = Vector2(100, 30)
			lbl.z_index = 10
			btn.add_child(lbl)
		elif node.type == "normal":
			poly.color = Color.WHITE
			poly.texture = grass_texture
			poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Add faint outline to distinguish tiles
			var outline = Line2D.new()
			var outline_points = vertices.duplicate()
			outline_points.append(vertices[0])
			outline.points = outline_points
			outline.width = 1.0
			outline.default_color = Color(0.1, 0.2, 0.1, 0.3)
			outline.position = center_offset
			btn.add_child(outline)
		
		btn.pressed.connect(_on_node_pressed.bind(node))
		btn.mouse_entered.connect(_on_node_hover.bind(node))
		btn.mouse_exited.connect(_on_node_exit)
		node["button"] = btn
		map_container.add_child(btn)
		
	# Draw Crypt Icon and Title centered
	if not crypt_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in crypt_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= crypt_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/crypt_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(40, 40)
		icon.position = center_pos - Vector2(20, 20)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Crypt"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.size = Vector2(100, 30)
		lbl.position = center_pos - Vector2(50, -15) # Centered on icon
		lbl.z_index = 21
		map_container.add_child(lbl)
		
	# Draw Goblin Camp Icon and Title centered
	if not goblin_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in goblin_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= goblin_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/goblin_camp_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(40, 40)
		icon.position = center_pos - Vector2(20, 20)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Goblin Camp"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.size = Vector2(100, 30)
		lbl.position = center_pos - Vector2(50, -15) # Centered on icon
		lbl.z_index = 21
		map_container.add_child(lbl)
		
	# Draw Dragon Roost Icon and Title centered
	if not dragon_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in dragon_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= dragon_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/dragon_roost_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(40, 40)
		icon.position = center_pos - Vector2(20, 20)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Dragon Roost"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.size = Vector2(100, 30)
		lbl.position = center_pos - Vector2(50, -15) # Centered on icon
		lbl.z_index = 21
		map_container.add_child(lbl)
		
	# Draw Town Icon and Title centered
	if not town_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in town_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= town_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/town_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(40, 40)
		icon.position = center_pos - Vector2(20, 20)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Town"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.size = Vector2(100, 30)
		lbl.position = center_pos - Vector2(50, -15) # Centered on icon
		lbl.z_index = 21
		map_container.add_child(lbl)
		
	# Draw Dwarven Forge Icon and Title centered
	if not dwarven_forge_nodes_for_visuals.is_empty():
		var center_pos = Vector2.ZERO
		for n in dwarven_forge_nodes_for_visuals:
			center_pos += n.pos
		center_pos /= dwarven_forge_nodes_for_visuals.size()
		
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ai/ui/dwarven_forge_node.svg")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(40, 40)
		icon.position = center_pos - Vector2(20, 20)
		icon.z_index = 20
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon)
		
		var lbl = Label.new()
		lbl.text = "Dwarven Forge"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.size = Vector2(120, 30)
		lbl.position = center_pos - Vector2(60, -15) # Centered on icon
		lbl.z_index = 21
		map_container.add_child(lbl)
		
	update_visuals()

func update_visuals():
	if not current_node: return
	player_icon.position = current_node.pos - (player_icon.size / 2.0)
	player_icon.z_index = 100
	
	for pos in grid_data:
		var node = grid_data[pos]
		var btn = node["button"]
		
		# Impassible terrain
		if node.type == "mountain" or node.type == "water":
			btn.disabled = true
			continue
		
		if node == current_node:
			btn.disabled = true
		else:
			btn.disabled = false

func is_neighbor(node_a, node_b):
	var r1 = node_a.row
	var c1 = node_a.col
	var r2 = node_b.row
	var c2 = node_b.col
	
	if r1 == r2 and abs(c1 - c2) == 1:
		return true
		
	if node_a.points_up:
		if r2 == r1 + 1 and c2 == c1: return true
	else:
		if r2 == r1 - 1 and c2 == c1: return true
		
	return false

func get_neighbors(node):
	var neighbors = []
	var r = node.row
	var c = node.col
	
	var candidates = [
		Vector2(r, c - 1),
		Vector2(r, c + 1)
	]
	if node.points_up:
		candidates.append(Vector2(r + 1, c))
	else:
		candidates.append(Vector2(r - 1, c))
		
	for cand in candidates:
		if grid_data.has(cand):
			neighbors.append(grid_data[cand])
	return neighbors

func _pick_random_cluster(size: int, excluded_types: Array, valid_starts: Array = []) -> Array:
	var attempts = 0
	while attempts < 100:
		attempts += 1
		var start_node
		
		if valid_starts.is_empty():
			var start_pos = Vector2(randi() % grid_height, randi() % grid_width)
			if not grid_data.has(start_pos): continue
			start_node = grid_data[start_pos]
		else:
			start_node = valid_starts.pick_random()
		
		if start_node.type in excluded_types: continue
		
		var cluster = [start_node]
		var neighbors = get_neighbors(start_node)
		neighbors.shuffle()
		
		for n in neighbors:
			if cluster.size() >= size: break
			if n.type not in excluded_types:
				cluster.append(n)
		
		if cluster.size() == size:
			return cluster
	return []

func _get_nodes_in_radius(center_nodes: Array, radius: int) -> Array:
	var result = {}
	var queue = []
	for n in center_nodes:
		queue.append({"node": n, "dist": 0})
		result[n] = true
		
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		if current.dist >= radius: continue
		
		var neighbors = get_neighbors(current.node)
		for n in neighbors:
			if not result.has(n):
				result[n] = true
				queue.append({"node": n, "dist": current.dist + 1})
				
	return result.keys()

func _get_nodes_in_range(center_nodes: Array, min_dist: int, max_dist: int) -> Array:
	var nodes_in_max = _get_nodes_in_radius(center_nodes, max_dist)
	var nodes_in_min = _get_nodes_in_radius(center_nodes, min_dist - 1)
	
	var result = []
	for n in nodes_in_max:
		if not n in nodes_in_min:
			result.append(n)
	return result

func _grow_clump(start_node, type, min_size, max_size, forbidden_zone = [], allowed_zone = []):
	if start_node.type != "normal": return
	if not forbidden_zone.is_empty() and start_node in forbidden_zone: return
	if not allowed_zone.is_empty() and not start_node in allowed_zone: return
	
	var clump = [start_node]
	start_node.type = type
	
	var queue = [start_node]
	var target_size = randi_range(min_size, max_size)
	
	while clump.size() < target_size and not queue.is_empty():
		var curr = queue.pop_front()
		var neighbors = get_neighbors(curr)
		neighbors.shuffle()
		
		for n in neighbors:
			if clump.size() >= target_size: break
			if n.type == "normal":
				if not forbidden_zone.is_empty() and n in forbidden_zone: continue
				if not allowed_zone.is_empty() and not n in allowed_zone: continue
				
				n.type = type
				clump.append(n)
				queue.append(n)

func _ensure_connectivity():
	# 1. Find all walkable nodes
	var walkable_nodes = []
	var start_node = null
	for pos in grid_data:
		var n = grid_data[pos]
		if n.type != "mountain" and n.type != "water":
			walkable_nodes.append(n)
			if n.type == "start":
				start_node = n
	
	if not start_node: return
	
	# 2. Flood fill from start
	var visited = {start_node: true}
	var queue = [start_node]
	var head = 0
	
	while head < queue.size():
		var curr = queue[head]
		head += 1
		for n in get_neighbors(curr):
			if n.type != "mountain" and n.type != "water" and not visited.has(n):
				visited[n] = true
				queue.append(n)
	
	# 3. If disconnected, carve path to nearest unvisited walkable node
	var unvisited = []
	for n in walkable_nodes:
		if not visited.has(n):
			unvisited.append(n)
			
	while not unvisited.is_empty():
		# Find closest pair (visited_node, unvisited_node)
		# This is expensive O(N*M), but grid is small (360 nodes).
		# Optimization: Just pick one unvisited and path to Start ignoring terrain.
		var target = unvisited[0]
		var path = _find_path_ignoring_terrain(start_node, target)
		
		for n in path:
			if n.type == "mountain" or n.type == "water":
				n.type = "normal" # Carve path
			if not visited.has(n):
				visited[n] = true
				# Add neighbors to queue to continue flood fill from new path
				queue.append(n)
		
		# Resume flood fill to update visited set
		while head < queue.size():
			var curr = queue[head]
			head += 1
			for n in get_neighbors(curr):
				if n.type != "mountain" and n.type != "water" and not visited.has(n):
					visited[n] = true
					queue.append(n)
		
		# Re-evaluate unvisited
		unvisited = []
		for n in walkable_nodes:
			if not visited.has(n):
				unvisited.append(n)

func _find_path_ignoring_terrain(from_node, to_node):
	# BFS for shortest path
	var came_from = {}
	var queue = [from_node]
	came_from[from_node] = null
	
	while not queue.is_empty():
		var curr = queue.pop_front()
		if curr == to_node: break
		
		for n in get_neighbors(curr):
			if not came_from.has(n):
				came_from[n] = curr
				queue.append(n)
	
	# Reconstruct
	var path = []
	var curr = to_node
	while curr != null:
		path.append(curr)
		curr = came_from.get(curr)
	return path

func find_path(from_node, to_node):
	# BFS for pathfinding respecting terrain
	var queue = [from_node]
	var came_from = {from_node: null}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		if current == to_node:
			break
		
		for next in get_neighbors(current):
			if next.type == "mountain" or next.type == "water":
				continue
			
			if next.type != "normal" and next.type != "start" and next != to_node:
				continue

			if not came_from.has(next):
				came_from[next] = current
				queue.append(next)
	
	if not came_from.has(to_node):
		return []
		
	var path = []
	var current = to_node
	while current != null:
		path.append(current)
		current = came_from[current]
	path.reverse()
	return path

func start_turn():
	if turns_left <= 0:
		print("Game Over - Out of turns")
		# Handle game over logic here if needed
		return

	turns_left -= 1
	turn_limit_label.text = "Turns: %d" % turns_left
	
	if turns_left <= 5:
		var t = 1.0 - (float(turns_left) / 5.0)
		turn_limit_label.modulate = Color.WHITE.lerp(Color(1, 0, 0), t)
		turn_limit_label.scale = Vector2.ONE * (1.0 + t * 0.5)
	else:
		turn_limit_label.modulate = Color.WHITE
		turn_limit_label.scale = Vector2.ONE

	# Roll Animation
	var d1 = Die.new(4)
	var d2 = Die.new(4)
	d1.roll()
	d2.roll()
	
	pending_roll_result = d1.result_value + d2.result_value
	is_rolling = true
	
	# Create visual displays for the roll
	var roll_overlay = Control.new()
	current_roll_overlay = roll_overlay
	roll_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.z_index = 200 # Ensure it's on top
	add_child(roll_overlay)
	
	var center_cont = CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_CENTER)
	roll_overlay.add_child(center_cont)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	center_cont.add_child(hbox)
	
	var disp1 = DIE_DISPLAY_SCENE.instantiate()
	var disp2 = DIE_DISPLAY_SCENE.instantiate()
	hbox.add_child(disp1)
	hbox.add_child(disp2)
	
	disp1.set_die(d1)
	disp2.set_die(d2)
	
	# Animate dice appearing
	disp1.scale = Vector2.ZERO
	disp2.scale = Vector2.ZERO
	
	var tween = create_tween()
	current_tween = tween
	tween.tween_property(disp1, "scale", Vector2(1.5, 1.5), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(disp2, "scale", Vector2(1.5, 1.5), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	if not is_rolling: return
	
	var timer_tween = create_tween()
	current_tween = timer_tween
	timer_tween.tween_interval(0.5)
	await timer_tween.finished
	if not is_rolling: return
	
	moves_remaining = pending_roll_result
	moves_label.text = "%d" % moves_remaining
	
	# Fade out overlay
	var out_tween = create_tween()
	current_tween = out_tween
	out_tween.tween_property(roll_overlay, "modulate:a", 0.0, 0.3)
	await out_tween.finished
	if not is_rolling: return
	
	roll_overlay.queue_free()
	current_roll_overlay = null
	is_rolling = false

func _on_end_turn_pressed():
	start_turn()

func get_best_path_to(target_node):
	var source_nodes = [current_node]
	if current_node and current_node.type in ["town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge"]:
		source_nodes = []
		for pos in grid_data:
			var n = grid_data[pos]
			if n.type == current_node.type:
				source_nodes.append(n)

	var target_nodes = [target_node]
	if target_node.type in ["town", "goblin_camp", "dragon_roost", "crypt", "dwarven_forge"]:
		target_nodes = []
		for pos in grid_data:
			var n = grid_data[pos]
			if n.type == target_node.type:
				target_nodes.append(n)
	
	var best_path = []
	var min_dist = 999999
	
	for source in source_nodes:
		for target in target_nodes:
			if source == target:
				return [source]
				
			var path = find_path(source, target)
			if path.is_empty(): continue
			
			var dist = path.size() - 1
			if dist < min_dist:
				min_dist = dist
				best_path = path
			elif dist == min_dist:
				if source == current_node:
					best_path = path
			
	return best_path

func _on_node_hover(node):
	if is_moving: return
	if not current_node or node == current_node: return
	if node.type == "mountain" or node.type == "water": return
	
	var path = get_best_path_to(node)
	if path.is_empty(): return
	
	var distance = path.size() - 1
	var display_path = path
	var display_distance = distance
	
	if distance > moves_remaining:
		display_distance = moves_remaining
		display_path = path.slice(0, moves_remaining + 1)
	
	# Update Full Path Line
	full_path_line.clear_points()
	if not path.is_empty() and path[0] != current_node:
		full_path_line.add_point(current_node.pos)
	for p_node in path:
		full_path_line.add_point(p_node.pos)
	
	# Update Path Line
	path_line.clear_points()
	if not display_path.is_empty() and display_path[0] != current_node:
		path_line.add_point(current_node.pos)
	for p_node in display_path:
		path_line.add_point(p_node.pos)
	
	# Update Distance Label
	distance_label.text = str(display_distance)
	if not display_path.is_empty():
		distance_label.position = display_path.back().pos + Vector2(0, -50)
	distance_label.visible = true
	
	distance_label.modulate = Color.WHITE
	path_line.default_color = Color.WHITE
	
	if distance > moves_remaining:
		full_distance_label.text = str(distance)
		full_distance_label.position = node.pos + Vector2(0, -50)
		full_distance_label.modulate = Color.RED
		full_distance_label.visible = true
	else:
		full_distance_label.visible = false

func _on_node_exit():
	path_line.clear_points()
	full_path_line.clear_points()
	distance_label.visible = false
	full_distance_label.visible = false

func _on_node_pressed(node):
	if is_moving: return
	if node == current_node: return
	if moves_remaining <= 0: return
	
	var path = get_best_path_to(node)
	if path.is_empty(): return
	
	var distance = path.size() - 1
	
	if distance > moves_remaining:
		path = path.slice(0, moves_remaining + 1)
		distance = moves_remaining
	
	is_moving = true
	pending_movement_path = path
	final_moves_remaining = moves_remaining - distance
	
	path_line.clear_points()
	full_path_line.clear_points()
	distance_label.visible = false
	full_distance_label.visible = false
	
	var tween = create_tween()
	current_tween = tween
	
	if not path.is_empty() and path[0] != current_node:
		tween.tween_method(func(t): _animate_hop(t, current_node.pos, path[0].pos), 0.0, 1.0, 0.15)
		
	for i in range(1, path.size()):
		var start_pos = path[i-1].pos
		var end_pos = path[i].pos
		tween.tween_method(func(t): _animate_hop(t, start_pos, end_pos), 0.0, 1.0, 0.2)
		tween.tween_callback(func():
			moves_remaining -= 1
			if moves_remaining > 0:
				moves_label.text = "%d" % moves_remaining
			else:
				moves_label.text = ""
		)
	
	await tween.finished
	if not is_moving: return
	
	pending_movement_path = [] # Movement finished, prevent skip logic from re-running movement completion
	
	var destination_node = path.back()
	current_node = destination_node
	current_node.cleared = true
	update_visuals()
	
	# Only trigger an encounter (switch to main game view) if it's a special node.
	if current_node.type == "town":
		town_ui.visible = true
	elif current_node.type != "normal" and current_node.type != "start":
		emit_signal("node_selected", current_node)
	
	if moves_remaining == 0:
		var timer_tween = create_tween()
		current_tween = timer_tween
		timer_tween.tween_interval(0.5)
		await timer_tween.finished
		if not is_moving: return
		start_turn()
		
	is_moving = false

func get_node_by_indices(_layer, _index):
	return null

func _animate_hop(t: float, start_pos: Vector2, end_pos: Vector2):
	var current_pos = start_pos.lerp(end_pos, t)
	var hop_height = 30.0
	var height_offset = 4.0 * t * (1.0 - t) * hop_height
	player_icon.position = current_pos - Vector2(0, height_offset) - (player_icon.size / 2.0)

func _skip_roll_animation():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	
	moves_remaining = pending_roll_result
	moves_label.text = "%d" % moves_remaining
	
	if current_roll_overlay:
		current_roll_overlay.queue_free()
		current_roll_overlay = null
	
	is_rolling = false

func _skip_movement_animation():
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	
	if pending_movement_path.is_empty(): return
	
	moves_remaining = final_moves_remaining
	if moves_remaining > 0:
		moves_label.text = "%d" % moves_remaining
	else:
		moves_label.text = ""
	
	var destination_node = pending_movement_path.back()
	current_node = destination_node
	current_node.cleared = true
	
	player_icon.position = current_node.pos - (player_icon.size / 2.0)
	update_visuals()
	
	if current_node.type == "town":
		town_ui.visible = true
	elif current_node.type != "normal" and current_node.type != "start":
		emit_signal("node_selected", current_node)
	
	is_moving = false
	
	if moves_remaining == 0:
		start_turn()

func close_town_menu():
	if town_ui:
		town_ui.visible = false

func open_town_menu():
	if town_ui:
		town_ui.visible = true
