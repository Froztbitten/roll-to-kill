extends Character
class_name Enemy

var next_damage: int = 0
@onready var intent_display = $EnemyIntentDisplay

func declare_intent():
	next_damage = randi() % 8 + 1
	intent_display.update_display(next_damage)
	intent_display.visible = true

func clear_intent():
	next_damage = 0
	intent_display.visible = false
