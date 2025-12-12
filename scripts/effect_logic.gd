extends Node
class_name EffectLogic

# Standard signature: (value: int, source: Character, target: Character, context: Dictionary)

# D4 Effects
static func aoe(value: int, _source: Character, _target: Character, context: Dictionary):
	var targets = context.get("all_enemies", [])
	for t in targets:
		t.take_damage(value)

static func draw(_value: int, source: Character, _target: Character, _context: Dictionary):
	if source.has_method("draw_dice"):
		source.draw_dice(1)

static func spikes(value: int, _source: Character, target: Character, _context: Dictionary):
	target.apply_charges_status("spikes", value)

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
	target.apply_charges_status("riposte", value)

static func trigger_riposte(value: int, defender: Character, attacker: Character):
	defender.remove_status("riposte")
	attacker.take_damage(value)

# D10 Effects
static func echoing_impact(value: int, _source: Character, target: Character, _context: Dictionary):
	target.apply_charges_status("echoing_impact", ceil(value / 2.0))

static func trigger_echoing_impact(target: Character):
	target.take_damage(target.statuses["echoing_impact"].charges)
	target.remove_status("echoing_impact")

static func splash_damage(value: int, _source: Character, target: Character, context: Dictionary):
	var all_enemies: Array = context.get("all_enemies", [])
	var idx = all_enemies.find(target)
	if idx != -1:
		if idx > 0:
			all_enemies[idx - 1].take_damage(ceil(value / 2.0))
		if idx < all_enemies.size() - 1:
			all_enemies[idx + 1].take_damage(ceil(value / 2.0))

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
	var targets = context.get("all_enemies", [])
	for t in targets:
		t.take_damage(value)