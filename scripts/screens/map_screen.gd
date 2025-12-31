extends Control
class_name MapScreen

signal node_selected(node_data)

@onready var map_container = $ScrollContainer/MapContainer
@onready var scroll_container = $ScrollContainer
@onready var player_icon = $ScrollContainer/MapContainer/PlayerIcon

var map_layers = []
var current_node = null

const LAYER_SPACING = 150
const NODE_SPACING = 100
const MAP_START_X = 100
const MAP_START_Y = 300

func _ready():
	visible = false

func generate_new_map():
	map_layers.clear()
	current_node = null
	
	# Layer 0: Start
	var start_node_type = "start"
	if get_tree().root.has_meta("force_shop_encounter") and get_tree().root.get_meta("force_shop_encounter"):
		start_node_type = "shop"
	
	map_layers.append([{
		"layer": 0,
		"index": 0,
		"type": start_node_type,
		"next": [],
		"pos": Vector2(MAP_START_X, MAP_START_Y)
	}])
	current_node = map_layers[0][0]
	
	# Layers 1-9: Combat
	for i in range(1, 10):
		var layer_nodes = []
		# Randomly generate 2 to 4 paths/nodes per layer
		var node_count = randi_range(2, 4)
		
		# Guarantee a shop on layer 5
		var guaranteed_shop_index = -1
		if i == 5:
			guaranteed_shop_index = randi() % node_count
			
		for j in range(node_count):
			# Center the nodes vertically around MAP_START_Y
			var y_pos = MAP_START_Y + (j - (node_count - 1) / 2.0) * NODE_SPACING
			var node_type = "combat"
			# 15% chance for a rare encounter
			if i == 5 and j == guaranteed_shop_index:
				node_type = "shop"
			elif randf() < 0.15:
				node_type = "rare_combat"
			elif randf() < 0.15:
				node_type = "shop"
			elif randf() < 0.15:
				node_type = "campfire"

			layer_nodes.append({
				"layer": i,
				"index": j,
				"type": node_type,
				"next": [],
				"pos": Vector2(MAP_START_X + i * LAYER_SPACING, y_pos)
			})
		map_layers.append(layer_nodes)
		
	# Layer 10: Boss
	map_layers.append([{
		"layer": 10,
		"index": 0,
		"type": "boss",
		"next": [],
		"pos": Vector2(MAP_START_X + 10 * LAYER_SPACING, MAP_START_Y)
	}])
	
	# Generate Connections
	for i in range(map_layers.size() - 1):
		var current_layer_nodes = map_layers[i]
		var next_layer_nodes = map_layers[i+1]
		
		for node in current_layer_nodes:
			# Ensure at least one connection forward
			var target_index = randi() % next_layer_nodes.size()
			node.next.append(target_index)
			
			# Chance for extra connections
			if next_layer_nodes.size() > 1:
				if randf() > 0.6:
					var other = (target_index + 1) % next_layer_nodes.size()
					if not node.next.has(other):
						node.next.append(other)
		
		# Ensure every node in the next layer has at least one parent
		for j in range(next_layer_nodes.size()):
			var has_parent = false
			for parent in current_layer_nodes:
				if parent.next.has(j):
					has_parent = true
					break
			if not has_parent:
				# Force connection from a random parent in the previous layer
				var parent = current_layer_nodes.pick_random()
				parent.next.append(j)

	draw_map()

func draw_map():
	# Clear existing map elements (except player icon)
	for child in map_container.get_children():
		if child != player_icon:
			child.queue_free()
	
	# Draw Nodes and Lines
	for layer in map_layers:
		for node in layer:
			# Draw Lines first so they are behind buttons
			for next_idx in node.next:
				var next_node = map_layers[node.layer + 1][next_idx]
				var line = Line2D.new()
				line.add_point(node.pos)
				line.add_point(next_node.pos)
				line.width = 4
				line.default_color = Color(0.5, 0.5, 0.5, 0.5)
				map_container.add_child(line)

			var btn = Button.new()
			btn.position = node.pos - Vector2(20, 20)
			btn.size = Vector2(40, 40)
			btn.flat = true

			var icon = TextureRect.new()
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size = btn.size
			btn.add_child(icon)

			if node.type == "boss":
				icon.texture = load("res://assets/ai/ui/boss_encounter.svg")
			elif node.type == "rare_combat":
				icon.texture = load("res://assets/ai/ui/rare_encounter.svg")
			elif node.type == "shop":
				icon.texture = load("res://assets/ai/ui/shop_encounter.svg")
				icon.modulate = Color(1, 0.8, 0.2) # Gold color for shop
			elif node.type == "campfire":
				icon.texture = load("res://assets/ai/ui/campfire_encounter.svg") # Placeholder
				icon.modulate = Color(1, 0.4, 0.0) # Orange/Fire color
			else:
				icon.texture = load("res://assets/ai/ui/normal_encounter.svg")

			btn.pressed.connect(_on_node_pressed.bind(node))
			node["button"] = btn
			map_container.add_child(btn)
			
	update_visuals()

func update_visuals():
	player_icon.position = current_node.pos
	
	for layer in map_layers:
		for node in layer:
			var btn = node["button"]
			# Enable buttons only if they are in the next layer and connected to current node
			if node.layer == current_node.layer + 1 and current_node.next.has(node.index):
				btn.disabled = false
				btn.get_child(0).modulate = Color.WHITE # icon
			elif node == current_node:
				btn.disabled = true
				btn.get_child(0).modulate = Color.YELLOW # icon
			else:
				btn.disabled = true
				btn.get_child(0).modulate = Color(0.2, 0.2, 0.2) # icon

func _on_node_pressed(node):
	current_node = node
	update_visuals()
	emit_signal("node_selected", node)
