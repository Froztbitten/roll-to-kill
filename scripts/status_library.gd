extends Node

# Central library for all status effects (buffs/debuffs).
# Must be registered as an Autoload named "StatusLibrary".

var statuses: Dictionary = {}

func _ready():
	_define_statuses()

func _define_statuses():
	statuses["advantageous"] = StatusEffect.new(
		"Advantageous",
		false,
		"Rolls each die twice and takes the higher result.",
		load("res://assets/ai/status_icons/advantage.svg")
	)
	statuses["bleeding"] = StatusEffect.new(
		"Bleeding",
		true,
		"Take(s) X damage at the end of every turn or until healed.",
		load("res://assets/ai/status_icons/bleed.svg"),
		-1,
		0
	)
	statuses["spiky"] = StatusEffect.new(
		"Spiky",
		false,
		"Attacker takes X damage after resolving their action.",
		load("res://assets/ai/status_icons/spikes.svg"),
		-1,
		0
	)
	statuses["ri-posted up"] = StatusEffect.new(
		"Ri-posted up",
		false,
		"Parry the next attack, dealing X damage to the attacker instead.",
		load("res://assets/ai/status_icons/riposte.svg"),
		-1,
		0
	)
	statuses["dazed"] = StatusEffect.new(
		"Dazed",
		true,
		"",
		load("res://assets/ai/status_icons/daze.svg"),
		-1,
		0
	)
	statuses["echoing_impact"] = StatusEffect.new(
		"Echoing Impact",
		true,
		"Take(s) X damage at the end of next turn.",
		load("res://assets/ai/status_icons/echoing_impact.svg"),
		-1,
		0
	)
	statuses["shrunk"] = StatusEffect.new(
		"Shrunk",
		true,
		"Shrinks all dice 1 size smaller for X turns.",
		load("res://assets/ai/status_icons/shrink.svg")
	)

func get_status(id: String) -> StatusEffect:
	if statuses.has(id):
		return statuses[id]
	return null
