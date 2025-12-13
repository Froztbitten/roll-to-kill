extends Node
class_name EffectLogic

# Standard signature: (value: int, source: Character, target: Character, context: Dictionary)

# D4 Effects
static func aoe(value: int, _source: Character, _target: Character, context: Dictionary):
	# Do not trigger AoE damage if the player is targeting themselves (e.g., for block).
	if _target is Player:
		return
	var enemies: Array[Enemy] = context.get("all_enemies", [])
	# The main target is already damaged by the initial attack.
	# This effect should only damage the *other* enemies.
	for enemy in enemies:
		if enemy != _target:
			enemy.take_damage(value)

static func draw(_value: int, source: Character, _target: Character, _context: Dictionary):
	if source.has_method("draw_dice"):
		source.draw_dice(1)

static func spikes(_value: int, _source: Character, target: Character, _context: Dictionary):
	target.apply_charges_status("spikes", 1) # This correctly applies the buff

# D6 Effects
static func ss(value: int, source: Character, _target: Character, _context: Dictionary):
	source.add_block(value)

static func sh(value: int, source: Character, _target: Character, _context: Dictionary):
	source.heal(value)

static func ssh(value: int, source: Character, _target: Character, _context: Dictionary):
	source.heal(value)
	source.add_block(value)

# D8 Effects
static func bleed(value: int, _source: Character, target: Character, _context: Dictionary):
	target.apply_duration_status("bleed", value)

static func pierce(value: int, _source: Character, target: Character, _context: Dictionary):
	target.take_piercing_damage(value)

static func riposte(value: int, _source: Character, target: Character, _context: Dictionary):
	# Riposte is a self-buff for the player. It should not be applied to enemies.
	if not target is Player:
		return
	target.apply_charges_status("riposte", value)

static func trigger_riposte(value: int, defender: Character, attacker: Character) -> void:
	# The defender removes the status and deals damage back to the attacker.
	print("%s's riposte triggers, dealing %d damage to %s" % [defender.name, value, attacker.name])
	defender.remove_status("riposte")
	await attacker.take_damage(value, true, defender)

# D10 Effects
static func echoing_impact(value: int, _source: Character, target: Character, _context: Dictionary):
	# This is a debuff, so it should not apply to the player.
	if target is Player:
		return
	target.apply_charges_status("echoing_impact", ceil(value / 2.0))

static func trigger_echoing_impact(target: Character):
	var status_effect = StatusLibrary.get_status("echoing_impact")
	if target.statuses.has(status_effect):
		var charges = target.statuses[status_effect]
		await target.take_damage(charges)
		# The removal is now handled by the caller (tick_down_statuses)

static func splash_damage(value: int, _source: Character, target: Character, context: Dictionary):
	# We expect an Array[Enemy], but to use find() with a Character type, we can't
	# use find() directly as it requires the exact same type. Instead, we iterate
	# manually to find the index.
	var enemies: Array[Enemy] = context.get("all_enemies", [])
	var idx = -1
	for i in range(enemies.size()):
		if enemies[i] == target:
			idx = i
			break
	if idx != -1:
		if idx > 0:
			enemies[idx - 1].take_damage(ceil(value / 2.0))
		if idx < enemies.size() - 1:
			enemies[idx + 1].take_damage(ceil(value / 2.0))

static func wormhole(_value: int, _source: Character, _target: Character, context: Dictionary):
	var die = context.get("die")
	if die:
		die.flip_die()

# D12 Effects
static func daze(value: int, _source: Character, target: Character, _context: Dictionary):
	target.apply_duration_status("daze", value)

static func shieldbreak(_value: int, _source: Character, target: Character, _context: Dictionary):
	target.block = 0

static func cleave(value: int, _source: Character, _target: Character, context: Dictionary):
	# Do not trigger Cleave damage if the player is targeting themselves (e.g., for block).
	if _target is Player:
		return
	var enemies: Array[Enemy] = context.get("all_enemies", [])
	# The main target is already damaged by the initial attack.
	# This effect should only damage the *other* enemies.
	for enemy in enemies:
		if enemy != _target:
			enemy.take_damage(value)
