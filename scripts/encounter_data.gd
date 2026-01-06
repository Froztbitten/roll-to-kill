extends Resource
class_name EncounterData

enum EncounterType {
	NORMAL,
	RARE,
	BOSS
}

@export var encounter_type: EncounterType
@export var enemy_types: Array[EnemyData]
@export_range(1, 10) var min_count: int = 3
@export_range(1, 10) var max_count: int = 6
@export var node_type: String
@export var region: String
