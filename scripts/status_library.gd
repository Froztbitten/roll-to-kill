extends Node

# Central library for all status effects (buffs/debuffs).
# Must be registered as an Autoload named "StatusLibrary".

var statuses: Dictionary = {}

func _ready():
	_define_statuses()

func _define_statuses():
	statuses["advantage"] = StatusEffect.new(
		"Advantage",
		false,
		"Rolls each die twice and takes the higher result.",
		load("res://assets/ai/status_icons/advantage.svg")
	)
	statuses["bleed"] = StatusEffect.new(
		"Bleed",
		true,
		"Take(s) X damage at the end of every turn or until healed.",
		load("res://assets/ai/status_icons/bleed.svg")
	)
	statuses["spikes"] = StatusEffect.new(
		"Spikes",
		false,
		"Attacker takes X damage after resolving their action.",
		load("res://assets/ai/status_icons/spikes.svg")
	)
	statuses["riposte"] = StatusEffect.new(
		"Riposte",
		false,
		"Parry the next attack, dealing X damage to the attacker instead.",
		load("res://assets/ai/status_icons/riposte.svg")
	)
	statuses["daze"] = StatusEffect.new(
		"Daze",
		true,
		"",
		load("res://assets/ai/status_icons/daze.svg")
	)
	statuses["echoing_impact"] = StatusEffect.new(
		"Echoing Impact",
		true,
		"Take(s) X damage at the end of next turn.",
		load("res://assets/ai/status_icons/echoing_impact.svg")
	)

func get_status(id: String) -> StatusEffect:
	if statuses.has(id):
		return statuses[id]
	return null
