extends Node

# This script acts as a central database for all possible die face effects in the game.
# It is intended to be used as an Autoload (Singleton) so it can be accessed globally.

# The main data structure. Key: int (die sides), Value: Array[DieFaceEffect]
var effects_by_die_size: Dictionary = {}

func _ready():
	_define_effects()

func _define_effects():
	# Helper lambda to consolidate instantiation and logic assignment
	var create = func(pName, pTier, pColor, pLogic):
		var e = DieFaceEffect.new(pName, pTier, Color.from_string(pColor, Color.WHITE))
		e.process_effect = pLogic
		return e

	# --- D4 Effects ---
	var d4_effects: Array[DieFaceEffect] = []
	d4_effects.append(create.call("Spikes", 1, "#bfdfe8", EffectLogic.spikes))
	d4_effects.append(create.call("Area of Effect", 2, "#10552a", EffectLogic.aoe))
	d4_effects.append(create.call("Draw", 2, "#328bde", EffectLogic.draw))
	effects_by_die_size[4] = d4_effects

	# --- D6 Effects ---
	var d6_effects: Array[DieFaceEffect] = []
	d6_effects.append(create.call("Sword and Shield", 1, "#a8d8ea", EffectLogic.ss))
	d6_effects.append(create.call("Sword and Heal", 2, "#5f93ac", EffectLogic.sh))
	d6_effects.append(create.call("Sword and Shield and Heal", 2, "#395968ff", EffectLogic.ssh))
	effects_by_die_size[6] = d6_effects

	# --- D8 Effects ---
	var d8_effects: Array[DieFaceEffect] = []
	d8_effects.append(create.call("Bleed", 1, "#a12020", EffectLogic.bleed))
	d8_effects.append(create.call("Pierce", 2, "#d77224", EffectLogic.pierce))
	d8_effects.append(create.call("Riposte", 3, "#705656", EffectLogic.riposte))
	effects_by_die_size[8] = d8_effects

	# --- D10 Effects ---
	var d10_effects: Array[DieFaceEffect] = []
	d10_effects.append(create.call("Echoing Impact", 1, "#200d67", EffectLogic.echoing_impact))
	d10_effects.append(create.call("Splash Damage", 2, "#fd3325", EffectLogic.splash_damage))
	d10_effects.append(create.call("Wormhole", 3, "#b846ff", EffectLogic.wormhole))
	effects_by_die_size[10] = d10_effects

	# --- D12 Effects ---
	var d12_effects: Array[DieFaceEffect] = []
	d12_effects.append(create.call("Daze", 1, "#ffe100ff", EffectLogic.daze))
	d12_effects.append(create.call("Shieldbreak", 2, "#59865eff", EffectLogic.shieldbreak))
	d12_effects.append(create.call("Cleave", 3, "#ff007bff", EffectLogic.cleave))
	effects_by_die_size[12] = d12_effects

func get_random_effect_for_die(sides: int, tier_limit: int = 1) -> DieFaceEffect:
	if effects_by_die_size.has(sides):
		var possible_effects = effects_by_die_size[sides].filter(func(e): return e.tier <= tier_limit)
		if not possible_effects.is_empty():
			var chosen_effect = possible_effects.pick_random()
			# Manually duplicate the effect to ensure all script variables are copied.
			# Resource.duplicate() does not reliably copy non-exported variables.
			var duplicated_effect = DieFaceEffect.new(
				chosen_effect.name,
				chosen_effect.tier,
				chosen_effect.highlight_color
			)
			duplicated_effect.process_effect = chosen_effect.process_effect
			print("Returning random effect for D%d: %s" % [sides, chosen_effect.name])
			return duplicated_effect
	return null
