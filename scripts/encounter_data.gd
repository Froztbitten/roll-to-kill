extends Resource
class_name EncounterData

enum EncounterType {
	NORMAL,
	RARE,
	BOSS
}

@export var encounter_type: EncounterType
@export var enemies: Array[Dictionary] = [] # Array of { "data": EnemyData, "min": float, "max": float }
@export var node_type: String
@export var region: String
