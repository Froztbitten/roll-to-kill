extends Resource
class_name Encounter

@export var enemy_scene: PackedScene
@export_range(1, 10) var min_count: int = 3
@export_range(1, 10) var max_count: int = 6