extends Control

signal game_finished(successful_hits)

@onready var track_container = $Panel/VBoxContainer/TrackContainer
@onready var track_line = $Panel/VBoxContainer/TrackContainer/TrackLine
@onready var hit_zone = $Panel/VBoxContainer/TrackContainer/HitZone
@onready var result_label = $Panel/VBoxContainer/ResultLabel

const BEAT_NODE = preload("res://scenes/ui/rhythm_beat.tscn")
const BEAT_SPEED = 500.0 # pixels per second

var beats_to_hit = 6
var successful_hits = 0
var active_beats = []
var game_started = false

func start_game():
	visible = true
	# If the track width is not yet calculated, wait for it to resize.
	# This ensures the travel time and game duration are calculated correctly.
	if track_line.size.x == 0:
		await track_line.resized
	game_started = true
	successful_hits = 0
	result_label.text = ""
	
	# Clear any old beats
	for beat in active_beats:
		if is_instance_valid(beat):
			beat.queue_free()
	active_beats.clear()
	
	# Generate 3 beats at random intervals
	var total_delay = 0.0
	for i in range(beats_to_hit):
		var beat_delay = randf_range(0.2, 0.8) # Random time between beats
		total_delay += beat_delay
		_spawn_beat(total_delay)
	
	# End the game after the last beat has passed
	var track_width = track_line.size.x
	var travel_time = track_width / BEAT_SPEED
	get_tree().create_timer(total_delay + travel_time + 0.5).timeout.connect(_end_game)

func _spawn_beat(delay: float):
	await get_tree().create_timer(delay).timeout
	if not game_started: return # Game might have been cancelled

	var beat = BEAT_NODE.instantiate()
	track_container.add_child(beat)
	
	var start_pos_x = track_line.position.x + track_line.size.x
	beat.position = Vector2(start_pos_x, track_line.position.y + (track_line.size.y / 2.0) - (beat.size.y / 2.0))
	active_beats.append(beat)
	
	var tween = create_tween()
	var travel_time = track_line.size.x / BEAT_SPEED
	tween.tween_property(beat, "position:x", track_line.position.x, travel_time).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func(): 
		if is_instance_valid(beat):
			beat.queue_free()
			active_beats.erase(beat)
	)

func _on_hit_button_pressed():
	if not game_started: return

	var hit_zone_rect = hit_zone.get_global_rect()
	var hit_success = false
	var beat_to_remove = null

	for beat in active_beats:
		if is_instance_valid(beat):
			var beat_rect = beat.get_global_rect()
			if hit_zone_rect.intersects(beat_rect):
				hit_success = true
				beat_to_remove = beat
				break
	
	if hit_success:
		successful_hits += 1
		result_label.text = "Hit! +%.0f%% Damage" % (successful_hits * (100.0 / 3.0))
		if beat_to_remove:
			beat_to_remove.queue_free()
			active_beats.erase(beat_to_remove)
	else:
		result_label.text = "Miss!"

func _end_game():
	if not game_started: return
	game_started = false
	emit_signal("game_finished", successful_hits)
	queue_free()

func cancel_game():
	game_started = false
	queue_free()