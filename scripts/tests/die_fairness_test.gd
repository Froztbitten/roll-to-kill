extends Node2D

const DIE_RENDERER_SCENE = preload("res://scenes/ui/die_3d_renderer.tscn")

@export var total_rolls: int = 1000
@export var die_sides: int = 6 # Ignored
@export var time_scale: float = 1.0 # Speed up physics for faster testing

var die_renderers: Dictionary = {}
var results: Dictionary = {} # sides -> {value -> count}
var roll_count: int = 0
var start_time: int
var die_types_to_test = [4, 6, 8, 10, 12, 20]
var dice_finished_in_batch: int = 0

func _ready():
	randomize()
	Engine.time_scale = time_scale
	
	print("--- Starting Simultaneous Die Fairness Test ---")
	print("Rolling 1 of each: %s" % str(die_types_to_test))
	print("Total Batches: %d, Time Scale: %.1f" % [total_rolls, time_scale])
	
	var grid_cols = 3
	var spacing = Vector2(350, 350)
	
	for i in range(die_types_to_test.size()):
		var sides = die_types_to_test[i]
		var renderer = DIE_RENDERER_SCENE.instantiate()
		add_child(renderer)
		
		var col = i % grid_cols
		var row = i / grid_cols
		renderer.position = Vector2(50 + col * spacing.x, 50 + row * spacing.y)
		renderer.custom_minimum_size = Vector2(300, 300)
		renderer.size = Vector2(300, 300)
		
		renderer.configure(sides)
		renderer.roll_finished.connect(_on_roll_finished.bind(sides))
		
		die_renderers[sides] = renderer
		
		results[sides] = {}
		for f in range(1, sides + 1):
			results[sides][f] = 0

	start_time = Time.get_ticks_msec()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_roll_batch()

func _roll_batch():
	if roll_count >= total_rolls:
		_finish_test()
		return
		
	roll_count += 1
	dice_finished_in_batch = 0
	
	for sides in die_renderers:
		die_renderers[sides].roll(0)

func _on_roll_finished(value: int, sides: int):
	if results[sides].has(value):
		results[sides][value] += 1
	else:
		results[sides][value] = 1
		
	dice_finished_in_batch += 1
	
	if dice_finished_in_batch >= die_types_to_test.size():
		if roll_count % 50 == 0:
			print("Batch %d/%d complete..." % [roll_count, total_rolls])
		_roll_batch()

func _finish_test():
	var duration = (Time.get_ticks_msec() - start_time) / 1000.0
	print("\n=== ALL TESTS COMPLETE in %.2fs ===" % duration)
	
	for sides in die_types_to_test:
		print("\n--- D%d Results ---" % sides)
		var side_results = results[sides]
		var expected_freq = 1.0 / float(sides)
		var max_deviation = 0.0
		
		for i in range(1, sides + 1):
			var count = side_results.get(i, 0)
			var freq = float(count) / float(total_rolls)
			var deviation = abs(freq - expected_freq)
			if deviation > max_deviation:
				max_deviation = deviation
			
			print("Face %d: %d (%.2f%%) [Dev: %.2f%%]" % [i, count, freq * 100.0, (freq - expected_freq) * 100.0])
		
		print("\nMax Deviation: %.2f%%" % (max_deviation * 100.0))
		
		# Chi-Squared Goodness of Fit Test
		var chi_sq = 0.0
		var expected_count = float(total_rolls) / float(sides)
		for i in range(1, sides + 1):
			var count = side_results.get(i, 0)
			chi_sq += pow(count - expected_count, 2) / expected_count
			
		print("Chi-Squared Statistic: %.4f" % chi_sq)
		print("Degrees of Freedom: %d" % (sides - 1))
		
		# Critical values for p=0.05
		var critical_values = {
			3: 7.815, # D4 (df=3)
			5: 11.070, # D6 (df=5)
			7: 14.067, # D8 (df=7)
			9: 16.919, # D10 (df=9)
			11: 19.675, # D12 (df=11)
			19: 30.144 # D20 (df=19)
		}
		var crit = critical_values.get(sides - 1, 0.0)
		if crit > 0:
			if chi_sq < crit:
				print("Result: PASS (Consistent with fair die, p > 0.05)")
			else:
				print("Result: FAIL (Statistically significant deviation, p < 0.05)")
				
	Engine.time_scale = 1.0
