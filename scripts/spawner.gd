extends Node2D

@export var enemy_scene: PackedScene
@export var enemy_pool: Array[EnemyData]
@export var spawn_radius: float = 400.0

@onready var player = get_tree().get_first_node_in_group("player")

## Один громкий отчёт на старте: дыры в контенте видно сразу,
## а не на первом спавне через минуту забега.
func _ready() -> void:
	if enemy_scene == null:
		push_error("Spawner '%s': не задана enemy_scene." % name)
	if enemy_pool.is_empty():
		push_error("Spawner '%s': enemy_pool пуст." % name)
		return
	for i in enemy_pool.size():
		if enemy_pool[i] == null:
			push_error("Spawner '%s': пустой слот %d в enemy_pool." % [name, i])
func _on_timer_timeout() -> void:
	if enemy_scene == null:
		return
	if player == null:
		return
	if player.is_dead:
		return
	if enemy_pool.is_empty():
		push_error("Enemy Pool пуст в спавнере: " + name)
		return
	var data: EnemyData = enemy_pool.pick_random()
	if data == null:
		push_error("Пустой элемент в Enemy Pool спавнера: " + name)
		return
	var angle = randf() * TAU
	var offset = Vector2.RIGHT.rotated(angle) * spawn_radius
	var enemy = enemy_scene.instantiate()
	enemy.enemy_data = data
	enemy.global_position = player.global_position + offset
	add_child(enemy)
	enemy.died.connect(player.add_kill)
