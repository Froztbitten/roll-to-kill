extends Node

var MEASUREMENT_ID = ""
var API_SECRET = ""
var ga_node = null

func _ready():
	_load_secrets()
	
	# Check for the GoogleAnalytics Autoload
	if has_node("/root/GoogleAnalytics"):
		ga_node = get_node("/root/GoogleAnalytics")
		print("GameAnalyticsManager: Found GoogleAnalytics autoload.")
		
		# Configure if the plugin supports runtime property assignment
		if MEASUREMENT_ID != "" and API_SECRET != "":
			if "measurement_id" in ga_node: ga_node.measurement_id = MEASUREMENT_ID
			if "api_secret" in ga_node: ga_node.api_secret = API_SECRET
	else:
		push_warning("GameAnalyticsManager: '/root/GoogleAnalytics' not found. Please ensure the GA4 plugin is enabled and added as an Autoload named 'GoogleAnalytics'.")

func start_round(round_num: int):
	_send_event("level_start", { "level_name": "round_%d" % round_num })

func complete_round(round_num: int):
	_send_event("level_end", { "level_name": "round_%d" % round_num, "success": 1 })

func fail_round(round_num: int):
	_send_event("level_end", { "level_name": "round_%d" % round_num, "success": 0 })

func track_gold_source(amount: int, source_type: String, source_id: String):
	_send_event("earn_virtual_currency", {
		"virtual_currency_name": "gold",
		"value": amount,
		"source": "%s_%s" % [source_type, source_id]
	})

func track_gold_sink(amount: int, item_type: String, item_id: String):
	_send_event("spend_virtual_currency", {
		"virtual_currency_name": "gold",
		"value": amount,
		"item_name": "%s_%s" % [item_type, item_id]
	})

func _send_event(event_name: String, params: Dictionary = {}):
	if ga_node:
		if ga_node.has_method("send_event"):
			ga_node.send_event(event_name, params)
		elif ga_node.has_method("event"):
			ga_node.event(event_name, params)

func _load_secrets():
	if FileAccess.file_exists("res://scripts/secrets.gd"):
		var secrets_script = load("res://scripts/secrets.gd")
		if secrets_script:
			var secrets = secrets_script.new()
			if "GA4_MEASUREMENT_ID" in secrets: MEASUREMENT_ID = secrets.GA4_MEASUREMENT_ID
			if "GA4_API_SECRET" in secrets: API_SECRET = secrets.GA4_API_SECRET
		else:
			push_error("GameAnalyticsManager: Failed to load 'res://scripts/secrets.gd'. Check for syntax errors.")
	else:
		push_warning("GameAnalyticsManager: 'res://scripts/secrets.gd' file not found.")
