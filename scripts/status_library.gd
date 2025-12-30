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
	statuses["charming"] = StatusEffect.new(
		"Charming",
		false,
		"Cannot be damaged by attacks for X turns.",
		load("res://assets/ai/status_icons/charm.svg")
	)
	statuses["lock_down"] = StatusEffect.new(
		"Lock-Down",
		true,
		"Cannot change die faces (e.g. flip) for X turns.",
		load("res://assets/ai/status_icons/lock_down.svg")
	)
	statuses["taunting"] = StatusEffect.new(
		"Taunting",
		false,
		"Opponents must target this character for X turns.",
		load("res://assets/ai/status_icons/taunt.svg")
	)
	statuses["raging"] = StatusEffect.new(
		"Raging",
		false,
		"Rolls 2x dice. Takes 50% of damage dealt as recoil.",
		load("res://assets/ai/status_icons/rage.svg")
	)
	statuses["crash_out"] = StatusEffect.new(
		"Crash Out",
		false,
		"Becomes enraged if Femme Fatale is defeated.",
		load("res://assets/ai/status_icons/crash_out.svg")
	)
	statuses["silence"] = StatusEffect.new(
		"Silence",
		true,
		"Cannot use abilities for X turns.",
		load("res://assets/ai/status_icons/silence.svg")
	)
	statuses["main_character_energy"] = StatusEffect.new(
		"Main Character Energy",
		false,
		"Prevents death once, restoring 50% HP. Consumed on use.",
		load("res://assets/ai/status_icons/main_character_energy.svg"),
		-1,
		1
	)

func get_status(id: String) -> StatusEffect:
	if statuses.has(id):
		return statuses[id]
	return null
