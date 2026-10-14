extends Node2D

@export var enemy_scene: PackedScene
@export var enemy_pool: Array[EnemyData]
## Сколько врагов живёт одновременно. На капе новые не появляются:
## цена кадра растёт с числом врагов (замер 10-13: ~150 врагов ≈ 10 мс без отрисовки).
@export var max_alive: int = 150
## На сколько px за краем экрана появляется враг.
@export var spawn_margin: float = 100.0
## Враг дальше стольких радиусов спавна убирается молча:
## иначе отставшие навсегда занимают места капа.
@export var despawn_radius_mult: float = 2.0


@onready var player = get_tree().get_first_node_in_group("player")

## Один громкий отчёт на старте: дыры в контенте видно сразу,
## а не на первом спавне через минуту забега.
func _ready() -> void:
	if enemy_scene == null:
		push_error("Spawner '%s': не задана enemy_scene." % name)
	if max_alive <= 0:
		push_error("Spawner '%s': max_alive = %d - враги не появятся." % [name, max_alive])
	if despawn_radius_mult <= 1.0:
		push_error("Spawner '%s': despawn_radius_mult = %.2f - враг исчезнет, едва появившись." % [name, despawn_radius_mult])
	if enemy_pool.is_empty():
		push_error("Spawner '%s': enemy_pool пуст." % name)
		return
	for i in enemy_pool.size():
		if enemy_pool[i] == null:
			push_error("Spawner '%s': пустой слот %d в enemy_pool." % [name, i])
func _on_timer_timeout() -> void:
	# На старте об этом уже кричали — здесь молча не спавним.
	if enemy_scene == null:
		return
	if player == null:
		return
	if player.is_dead:
		return
	var radius := _spawn_radius()
	_despawn_far(radius * despawn_radius_mult)
	if _alive_count() >= max_alive:
		return 
	if enemy_pool.is_empty():
		push_error("Enemy Pool пуст в спавнере: " + name)
		return
	var data: EnemyData = enemy_pool.pick_random()
	if data == null:
		push_error("Пустой элемент в Enemy Pool спавнера: " + name)
		return
	var angle = randf() * TAU
	var offset = Vector2.RIGHT.rotated(angle) * radius
	var enemy = enemy_scene.instantiate()
	enemy.enemy_data = data
	enemy.global_position = player.global_position + offset
	add_child(enemy)
	enemy.died.connect(player.add_kill)

## Кольцо спавна сразу за краем экрана: половина диагонали видимой области плюс запас.
## Считается на каждом спавне: окно могут растянуть посреди забега.
func _spawn_radius() -> float:
	var visible_size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		visible_size /= camera.zoom
	return visible_size.length() / 2.0 + spawn_margin

# Живые враги. Убитый или убранный в этом кадре остаётся в группе до конца кадра — его не считаем.
func _alive_count() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_dead and not enemy.is_queued_for_deletion():
			count += 1
	return count

## Отставших далеко убираем молча: без гема, без убийства и без сигнала died.
## Заметка: продумать работу для боссов/уникальных противник - возможно их не стоит удалять
func _despawn_far(limit: float) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(player.global_position) > limit:
			enemy.queue_free()
