extends Node

# This script acts as a central database for all possible die face effects in the game.
# It is intended to be used as an Autoload (Singleton) so it can be accessed globally.

# The main data structure. Key: int (die sides), Value: Array[DieFaceEffect]
var effects_by_die_size: Dictionary = {}

func _ready():
	_define_effects()

func _define_effects():
	# Helper lambda to consolidate instantiation and logic assignment
	var create = func(pName, pDesc, pTier, pColor, pLogic):
		var e = DieFaceEffect.new(pName, pDesc, pTier, Color.from_string(pColor, Color.WHITE))
		e.process_effect = pLogic
		return e

	# --- D4 Effects ---
	var d4_effects: Array[DieFaceEffect] = []
	d4_effects.append(create.call("Spikes", "If used to block, gain [color=yellow]{value}[/color] [b]Spikes[/b]. When attacked, deal damage equal to your Spikes charges to the attacker.", 1, "#bfdfe8", EffectLogic.spikes))
	d4_effects.append(create.call("Area of Effect", "If used to attack, deals [color=yellow]{value}[/color] damage to enemies adjacent to the target.", 2, "#10552a", EffectLogic.aoe))
	d4_effects.append(create.call("Draw", "When used, draw [color=yellow]1[/color] extra die from your bag.", 2, "#328bde", EffectLogic.draw))
	effects_by_die_size[4] = d4_effects

	# --- D6 Effects ---
	var d6_effects: Array[DieFaceEffect] = []
	d6_effects.append(create.call("Sword and Shield", "If used to attack, deal [color=yellow]{value}[/color] damage and gain [color=cyan]{value}[/color] Block.", 1, "#a8d8ea", EffectLogic.ss))
	d6_effects.append(create.call("Sword and Heal", "If used to attack, deal [color=yellow]{value}[/color] damage and heal for [color=green]{value}[/color] HP.", 2, "#5f93ac", EffectLogic.sh))
	d6_effects.append(create.call("Sword and Shield and Heal", "If used to attack, deal [color=yellow]{value}[/color] damage, gain [color=cyan]{value}[/color] Block, and heal for [color=green]{value}[/color] HP.", 2, "#395968ff", EffectLogic.ssh))
	effects_by_die_size[6] = d6_effects

	# --- D8 Effects ---
	var d8_effects: Array[DieFaceEffect] = []
	d8_effects.append(create.call("Bleed", "If used to attack, apply [color=yellow]{value}[/color] [b]Bleed[/b]. At the end of their turn, the target takes damage equal to their Bleed stacks.", 1, "#a12020", EffectLogic.bleed))
	d8_effects.append(create.call("Pierce", "If used to attack, [color=yellow]{value}[/color] piercing damage, ignoring Block.", 2, "#d77224", EffectLogic.pierce))
	d8_effects.append(create.call("Riposte", "If used to block, apply [color=yellow]{value}[/color] [b]Riposte[/b]. The next time you are attacked, negate the damage and deal damage back to the attacker equal to your Riposte charges.", 3, "#705656", EffectLogic.riposte))
	effects_by_die_size[8] = d8_effects

	# --- D10 Effects ---
	var d10_effects: Array[DieFaceEffect] = []
	d10_effects.append(create.call("Echoing Impact", "If used to attack, Deal [color=yellow]{value}[/color] damage and apply [color=yellow]{value / 2}[/color] [b]Echoing Impact[/b]. At the end of their next turn, the target takes damage equal to their Echoing Impact stacks.", 1, "#200d67", EffectLogic.echoing_impact))
	d10_effects.append(create.call("Splash Damage", "If used to attack, deal full damage to the target and [color=yellow]{value / 2}[/color] to adjacent enemies.", 2, "#fd3325", EffectLogic.splash_damage))
	d10_effects.append(create.call("Wormhole", "Right-click to flip this die to its opposite face.", 3, "#b846ff", EffectLogic.wormhole))
	effects_by_die_size[10] = d10_effects

	# --- D12 Effects ---
	var d12_effects: Array[DieFaceEffect] = []
	d12_effects.append(create.call("Daze", "If used to attack, apply [color=yellow]{value}[/color] [b]Daze[/b]. Reduces the damage dealt by the target on their next turn.", 1, "#ffe100ff", EffectLogic.daze))
	d12_effects.append(create.call("Shieldbreak", "If used to attack, removes all [color=light blue]Block[/color] from the target.", 2, "#59865eff", EffectLogic.shieldbreak))
	d12_effects.append(create.call("Cleave", "If used to attack, deal [color=yellow]{value}[/color] damage to all other enemies.", 3, "#ff007bff", EffectLogic.cleave))
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
				chosen_effect.description,
				chosen_effect.tier,
				chosen_effect.highlight_color
			)
			duplicated_effect.process_effect = chosen_effect.process_effect
			print("Returning random effect for D%d: %s" % [sides, chosen_effect.name])
			return duplicated_effect
	return null

func get_effect_by_name(name: String) -> DieFaceEffect:
	for sides in effects_by_die_size.keys():
		for effect in effects_by_die_size[sides]:
			if effect.name == name:
				return effect
	return null
