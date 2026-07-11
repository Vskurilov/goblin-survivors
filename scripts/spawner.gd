extends Node2D

@export var enemy_scene: PackedScene
@export var enemy_pool: Array[EnemyData]
@export var spawn_radius: float = 400.0

@onready var player = get_tree().get_first_node_in_group("player")

func _on_timer_timeout() -> void:
	if player == null:
		return
	if player.is_dead:
		return
	if enemy_pool.is_empty():
		push_warning("Enemy Pool пуст в спавнере: " + name)
		return
	var angle = randf() * TAU
	var offset = Vector2.RIGHT.rotated(angle) * spawn_radius
	var enemy = enemy_scene.instantiate()
	enemy.enemy_data = enemy_pool.pick_random()
	enemy.global_position = player.global_position + offset
	add_child(enemy)
	enemy.died.connect(player.add_kill)
