extends Enemy
class_name Goblin


func _ready():
	# Call the parent's _ready function first to ensure nodes are ready.
	super._ready()
	
	# --- Set randomized health for the Goblin (4d4) ---
	var total_hp = 0
	for i in range(4):
		total_hp += randi() % 4 + 1
	
	# Assign the rolled HP to the character's health properties
	self.max_hp = total_hp
	self.hp = total_hp
	
	# Update the health bar display with the new randomized values
	update_health_display()


func declare_intent():
	# --- Goblins attack with a 1d4 die ---
	next_damage = randi() % 4 + 1
	intent_display.update_display(next_damage, 4)
	intent_display.visible = true