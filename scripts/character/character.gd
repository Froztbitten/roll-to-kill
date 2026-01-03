extends CharacterBody2D
class_name Character

signal died(character)
signal statuses_changed(statuses)

@export var hp: int = 100
@export var max_hp: int = 100
@export var block: int = 0

const STATUS_CHARMING = "Charming"
const STATUS_SPIKY = "Spiky"
const STATUS_RIPOSTE = "Ri-posted up"
const STATUS_MAIN_CHARACTER = "Main Character Energy"
const STATUS_ECHOING_IMPACT = "Echoing Impact"
const STATUS_BLEEDING = "Bleeding"
const STATUS_BURNING = "Burning"
const STATUS_GLANCE_BLOWS = "Glance Blows"
const STATUS_SHRUNK = "Shrunk"

var current_scale_factor: float = 1.0
var statuses: Dictionary = {} # {StatusEffect: duration}
var _new_statuses_this_turn: Array[StatusEffect] = []
var _is_dead := false
var _resting_position: Vector2
var _resting_rotation: float
var _recoil_tween: Tween
var _damage_sound: AudioStream
var audio_player: AudioStreamPlayer
var _death_sound: AudioStream
var _initial_collision_pos: Vector2
var _initial_collision_scale: Vector2 = Vector2.ONE

@onready var health_bar = $Visuals/InfoContainer/HealthBar
@onready var name_label: Label = $Visuals/InfoContainer.get_node_or_null("NameLabel")

func _ready():
	_resting_position = position
	_resting_rotation = rotation
	
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		_initial_collision_pos = collision_shape.position
		_initial_collision_scale = collision_shape.scale
	
	update_health_display()
	
	# Load the sound and create an audio player for damage effects.
	_damage_sound = load("res://assets/ai/sounds/Hit_hurt 7.wav")
	_death_sound = load("res://assets/ai/sounds/death2.wav")
	audio_player = AudioStreamPlayer.new()
	# This node should continue processing when the game is paused for UI screens.
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_player)

func take_damage(damage: int, play_recoil: bool = true, attacker: Character = null, is_attack_action: bool = false):
	if damage <= 0:
		return
	
	# Check if self has Charming buff (cannot be damaged)
	if has_status(STATUS_CHARMING) and attacker != self:
		print("%s is Charming and cannot be damaged!" % name)
		return
	var old_block = block
	var damage_to_take = damage
	if block > 0:
		var blocked_damage = min(damage_to_take, block)
		damage_to_take -= blocked_damage
		block -= blocked_damage
		print("%s blocked %d damage." % [name, blocked_damage])
	
	if has_status(STATUS_GLANCE_BLOWS):
		damage_to_take = ceili(damage_to_take / 2.0)
		print("%s's Glance Blows reduced damage to %d." % [name, damage_to_take])
	
	await _apply_damage(damage_to_take, "damage", old_block, play_recoil, attacker, is_attack_action)

func take_piercing_damage(damage: int, play_recoil: bool = true, attacker: Character = null, is_attack_action: bool = false):
	# This damage type ignores block.
	if damage <= 0:
		return
	
	# Check if self has Charming buff (cannot be damaged)
	if has_status(STATUS_CHARMING) and attacker != self:
		print("%s is Charming and cannot be damaged!" % name)
		return
	await _apply_damage(damage, "piercing damage", block, play_recoil, attacker, is_attack_action)

func _apply_damage(amount: int, type: String, old_block_value: int, play_recoil: bool = true, attacker: Character = null, is_attack_action: bool = false) -> void:
	if amount > 0:
		# Play the damage sound if one is loaded.
		if audio_player and _damage_sound:
			audio_player.stream = _damage_sound
			audio_player.play()
		if play_recoil:
			_recoil(amount)

	var old_hp = hp
	hp -= amount
	if hp < 0:
		hp = 0

	var should_die = hp <= 0

	if health_bar.has_method("update_with_animation"):
		health_bar.update_with_animation(old_hp, hp, old_block_value, block, max_hp)
		if should_die:
			await health_bar.current_tween.finished
			await die()
	else:
		update_health_display()
		if should_die:
			await die()
	print("%s took %d %s, has %d HP left." % [name, amount, type, hp])

	# --- Spikes Logic ---
	# If this character was attacked and has Spikes, deal damage back to the attacker.
	if attacker and not attacker._is_dead and has_status(STATUS_SPIKY) and is_attack_action:
		var spikes_status = StatusLibrary.get_status(STATUS_SPIKY.to_lower())
		if statuses.has(spikes_status):
			var spike_charges = statuses[spikes_status]
			if spike_charges > 0 and attacker != self:
				print("%s's spikes damage %s for %d" % [name, attacker.name, spike_charges])
				await attacker.take_damage(spike_charges, true, self, false) # Spikes is reactive, not an attack action

	# --- Riposte Logic ---
	# If this character was attacked and has Riposte, trigger the effect. This only
	# triggers on direct attack actions, not on reactive or status damage.
	if attacker and not attacker._is_dead and has_status(STATUS_RIPOSTE) and is_attack_action:
		var riposte_status = StatusLibrary.get_status(STATUS_RIPOSTE.to_lower())
		if statuses.has(riposte_status):
			var riposte_charges = statuses[riposte_status]
			if riposte_charges > 0:
				await EffectLogic.trigger_riposte(riposte_charges, self, attacker)

func heal(amount: int):
	var burn_effect = StatusLibrary.get_status("burning")
	if statuses.has(burn_effect):
		var burn_charges = statuses[burn_effect]
		var amount_to_remove = min(burn_charges, amount)
		
		statuses[burn_effect] -= amount_to_remove
		amount -= amount_to_remove
		print("%s used %d healing to remove Burning charges. Remaining Burning: %d" % [name, amount_to_remove, statuses[burn_effect]])
		
		if statuses[burn_effect] <= 0:
			remove_status("burning")
		else:
			statuses_changed.emit(statuses)
	
	if amount <= 0: return

	var old_hp = hp
	var old_block = block
	hp = min(hp + amount, max_hp)
	if health_bar.has_method("update_with_animation"):
		health_bar.update_with_animation(old_hp, hp, old_block, block, max_hp)
	else:
		update_health_display()
	print("%s healed for %d, has %d HP left." % [name, amount, hp])

func add_block(amount: int):
	var old_block = block
	block += amount
	if health_bar.has_method("update_with_animation"):
		health_bar.update_with_animation(hp, hp, old_block, block, max_hp)
	else:
		update_health_display()

func apply_duration_status(status_id: String, duration: int = 1, _source: Character = null):
	if _is_dead: return

	var effect: StatusEffect = StatusLibrary.get_status(status_id)
	if effect:
		statuses[effect] = duration
		_new_statuses_this_turn.append(effect)
		print("%s gained status '%s' for %d rounds." % [name, effect.status_name, duration])
		statuses_changed.emit(statuses)
	else:
		push_warning("Attempted to apply unknown status with id: '%s'" % status_id)

func apply_charges_status(status_id: String, charges: int = 1, _source: Character = null):
	if _is_dead: return

	var effect: StatusEffect = StatusLibrary.get_status(status_id)
	if effect:
		if statuses.has(effect):
			statuses[effect] += charges
		else:
			statuses[effect] = charges
			
		_new_statuses_this_turn.append(effect)
		var total_charges = statuses[effect]
		print("%s gained %d charges of '%s' status. Total: %d" % [name, charges, effect.status_name, total_charges])
		statuses_changed.emit(statuses)
	else:
		push_warning("Attempted to apply unknown status with id: '%s'" % status_id)

func apply_effect(effect: StatusEffect, value: int, _source: Character = null):
	if _is_dead: return

	if statuses.has(effect):
		if effect.charges != -1:
			statuses[effect] += value
			print("%s gained %d charges of '%s'. Total: %d" % [name, value, effect.status_name, statuses[effect]])
		else:
			statuses[effect] = value
			print("%s gained status '%s' for %d rounds." % [name, effect.status_name, value])
	else:
		statuses[effect] = value
		if effect.charges != -1:
			print("%s gained %d charges of '%s'." % [name, value, effect.status_name])
		else:
			print("%s gained status '%s' for %d rounds." % [name, effect.status_name, value])

	_new_statuses_this_turn.append(effect)
	statuses_changed.emit(statuses)

func remove_status(status_id: String):
	var effect: StatusEffect = StatusLibrary.get_status(status_id)
	if effect:
		print("%s lost status '%s'." % [name, effect.status_name])
		statuses.erase(effect)
		statuses_changed.emit(statuses)

func has_status(status_name: String) -> bool:
	# Check if any of the active status effects match the given name.
	for effect in statuses:
		if effect.status_name == status_name:
			return true
	return false

func trigger_start_of_turn_statuses():
	if statuses.is_empty():
		return
	
	var statuses_to_process = statuses.keys()
	for status in statuses_to_process:
		if status.status_name == STATUS_BLEEDING or status.status_name == STATUS_BURNING:
			await take_damage(statuses[status], true, null, false)
			if _is_dead:
				return

func tick_down_statuses():
	if statuses.is_empty():
		return
	
	var keys_to_remove = []
	var statuses_to_process = statuses.keys()
	var changed = false
	
	for status in statuses_to_process:
		# Skip processing for statuses that were just applied this turn.
		if _new_statuses_this_turn.has(status):
			continue

		# --- Triggerable Effects ---
		if status.status_name == STATUS_ECHOING_IMPACT:
			await EffectLogic.trigger_echoing_impact(self)
			if _is_dead:
				_new_statuses_this_turn.clear()
				return
			keys_to_remove.append(status)
			changed = true
			continue

		# Skip ticking down for charge-based effects. Since Spikes is a permanent
		# charge buff, we add an explicit check to ensure it never decays. Debuffs
		# like Bleed and Burn are also charge-based and should not decay over time.
		if status.charges != -1 or status.status_name == STATUS_SPIKY or status.status_name == STATUS_BLEEDING or status.status_name == STATUS_BURNING:
			continue
		
		statuses[status] -= 1
		changed = true
		if statuses[status] <= 0:
			keys_to_remove.append(status)
			print("%s lost status '%s'." % [name, status.status_name])
			
	_new_statuses_this_turn.clear()
	
	for key in keys_to_remove:
		statuses.erase(key)
	if changed:
		statuses_changed.emit(statuses)

func update_resting_state():
	_resting_position = position
	_resting_rotation = rotation

func _recoil(damage_amount: int) -> void:
	if damage_amount <= 0:
		return

	# Calculate intensity from 0.0 to 1.0, mapping damage from 1 to 20.
	var intensity = clamp(float(damage_amount), 1.0, 20.0) / 20.0

	# Define the maximum recoil effect.
	var max_recoil_distance = 25.0
	var max_recoil_angle_deg = 10.0

	# Calculate the actual recoil based on damage intensity.
	var recoil_distance = max_recoil_distance * intensity
	var recoil_angle_rad = deg_to_rad(max_recoil_angle_deg * intensity)

	# Determine direction based on screen position (left half = player, right half = enemy).
	var direction_multiplier = 1.0 # Recoil to the right for enemies
	if global_position.x < get_viewport_rect().size.x / 2:
		direction_multiplier = -1.0 # Recoil to the left for player

	# If a recoil is already in progress, stop it.
	# This prevents tweens from fighting over the properties.
	if _recoil_tween and _recoil_tween.is_running():
		_recoil_tween.kill()

	# The recoil moves the character back and slightly up.
	var recoil_position = _resting_position + Vector2(recoil_distance * direction_multiplier, -recoil_distance * 0.5)
	# The character leans away from the impact.
	var recoil_rotation = _resting_rotation - (recoil_angle_rad * direction_multiplier)

	_recoil_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_recoil_tween.parallel().tween_property(self, "position", recoil_position, 0.08)
	_recoil_tween.parallel().tween_property(self, "rotation", recoil_rotation, 0.08)
	_recoil_tween.parallel().tween_property(self, "position", _resting_position, 0.25).set_delay(0.08)
	_recoil_tween.parallel().tween_property(self, "rotation", _resting_rotation, 0.25).set_delay(0.08)

func die() -> void:
	if has_status(STATUS_MAIN_CHARACTER):
		var old_hp = hp
		var old_block = block
		statuses.clear()
		statuses_changed.emit(statuses)
		block = 0
		hp = int(max_hp / 2.0)
		if health_bar.has_method("update_with_animation"):
			health_bar.update_with_animation(old_hp, hp, old_block, block, max_hp)
		else:
			update_health_display()
		print("%s's Main Character Energy activates!" % name)
		# A visual/sound effect could be added here in the future.
		return

	if _is_dead: return
	_is_dead = true
	
	# Clear statuses so icons disappear immediately upon death.
	statuses.clear()
	_new_statuses_this_turn.clear()
	statuses_changed.emit(statuses)
	
	# Play death sound for enemies
	if self is Enemy and audio_player and _death_sound:
		audio_player.stream = _death_sound
		audio_player.play()
	
	hp = 0
	emit_signal("died", self)

	# This tween should continue processing when the game is paused for UI screens,
	# so the death animation can complete in the background.
	var tween = create_tween().set_parallel().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(self, "scale", scale * 0.5, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tween.finished

	hide()
	get_node("CollisionShape2D").set_deferred("disabled", true)
	modulate.a = 1.0
	scale = Vector2.ONE

func update_health_display(intended_damage: int = 0, intended_block: int = 0):
	if health_bar:
		health_bar.update_display(hp, max_hp, block + intended_block, intended_damage)

func update_scale(factor: float):
	current_scale_factor = factor
	var visuals = get_node_or_null("Visuals")
	if visuals:
		visuals.scale = Vector2.ONE * factor
	
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape:
		collision_shape.scale = _initial_collision_scale * factor
		collision_shape.position = _initial_collision_pos * factor
