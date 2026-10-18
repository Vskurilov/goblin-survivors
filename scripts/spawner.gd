extends Node2D

@export var enemy_scene: PackedScene
## Повтор врага в пуле — его вес: какую долю угрозы на экране он держит.
@export var enemy_pool: Array[EnemyData]
## Сколько врагов живёт одновременно. На капе новые не появляются:
## цена кадра растёт с числом врагов (замер 10-13: ~150 врагов ≈ 10 мс без отрисовки).
@export var max_alive: int = 150
## На сколько px за краем экрана появляется враг.
@export var spawn_margin: float = 100.0
## Враг дальше стольких радиусов спавна убирается молча:
## иначе отставшие навсегда занимают места капа.
@export var despawn_radius_mult: float = 2.0
## Угроза на экране в начале забега: сумма threat_cost живых врагов.
@export var threat_start: float = 10.0
## На сколько угроза на экране растёт за минуту забега.
@export var threat_per_minute: float = 15.0
## На сколько этот прирост сам растёт каждую минуту: 0 — ровный рост, больше — дальше больше.
@export_range(0.0, 10.0, 0.1, "or_greater") var threat_acceleration: float = 1.0

## Больше стольких за тик не выпускаем: после волны убийств
## добор иначе вышел бы толпой в один кадр.
const MAX_SPAWNS_PER_TICK := 5

@onready var player = get_tree().get_first_node_in_group("player")
## Живых врагов спавнер берёт из реестра орды, а не обходом группы.
@onready var _horde: Horde = get_tree().get_first_node_in_group(&"horde")

## Один громкий отчёт на старте: дыры в контенте видно сразу,
## а не на первом спавне через минуту забега.
func _ready() -> void:
	if enemy_scene == null:
		push_error("Spawner '%s': не задана enemy_scene." % name)
	if max_alive <= 0:
		push_error("Spawner '%s': max_alive = %d - враги не появятся." % [name, max_alive])
	if despawn_radius_mult <= 1.0:
		push_error("Spawner '%s': despawn_radius_mult = %.2f - враг исчезнет, едва появившись." % [name, despawn_radius_mult])
	if threat_start <= 0.0 and threat_per_minute <= 0.0 and threat_acceleration <= 0.0:
		push_error("Spawner '%s': угроза не задана и не растёт - враги не появлятся. " % name)
	if enemy_pool.is_empty():
		push_error("Spawner '%s': enemy_pool пуст." % name)
		return
	for i in enemy_pool.size():
		var data := enemy_pool[i]
		if data == null:
			push_error("Spawner '%s': пустой слот %d в enemy_pool." % [name, i])
		elif data.threat_cost <= 0:
			push_error("Spawner '%s': у %s не задана threat_cost - этот враг не появится." % [name, data.resource_path])
			
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
	var alive := _alive_count()
	if alive >= max_alive:
		return
	var seconds: float = player.survival_time
	var for_sale := _for_sale(seconds)
	if for_sale.is_empty():
		return
	# Держим угрозу живых на цели: убитых и убранных докупаем.
	var target := _target_thret(seconds)
	var by_type := _alive_threat_by_type()
	var threat := 0.0
	for cost in by_type.values():
		threat += cost
	for i in MAX_SPAWNS_PER_TICK:
		if threat >= target or alive >= max_alive:
			return
		var data := _pick(for_sale, by_type, target)
		if data == null:
			return
		_spawn(data, radius)
		alive += 1
		threat += data.threat_cost
		by_type[data] = by_type.get(data, 0.0) + data.threat_cost
	
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
	for enemy in _horde.enemies:
		if not enemy.is_dead and not enemy.is_queued_for_deletion():
			count += 1
	return count

## Отставших далеко убираем молча: без гема, без убийства и без сигнала died.
## Заметка: продумать работу для боссов/уникальных противник - возможно их не стоит удалять
func _despawn_far(limit: float) -> void:
	for enemy in _horde.enemies:
		if enemy.global_position.distance_to(player.global_position) > limit:
			enemy.queue_free()

func _alive_threat_by_type() -> Dictionary[EnemyData, float]:
	var by_type: Dictionary[EnemyData, float] = {}
	for enemy in _horde.enemies:
		if not enemy.is_dead and not enemy.is_queued_for_deletion():
			by_type[enemy.enemy_data] = by_type.get(enemy.enemy_data, 0.0) + enemy.enemy_data.threat_cost
	return by_type

## Цель угрозы к этой секунде забега. Прирост за минуту равен
## threat_per_minute + threat_acceleration * минуты, поэтому в формуле деление на 2.
func _target_thret(seconds: float) -> float:
	var minutes := seconds / 60.0
	return threat_start + threat_per_minute * minutes + threat_acceleration * minutes * minutes / 2.0

## Враги, которых можно выпускать сейчас: цена задана и время пришло.
## Повторы остаются в списке — это вес.
func _for_sale(seconds: float) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	for data in enemy_pool:
		if data != null and data.threat_cost > 0 and data.unlock_time <= seconds:
			result.append(data)
	return result

## Случайный враг из тех, кто ещё не занял свою долю цели (доля — его вес среди доступных).
## Без долей дешёвые умирают, на их место приходят танки и копятся
## (замер 10-14: 32 танка из 45 живых).
func _pick(for_sale: Array[EnemyData], by_type: Dictionary[EnemyData, float], target: float) -> EnemyData:
	var candidates: Array[EnemyData] = []
	for data in for_sale:
		var share := float(for_sale.count(data)) / for_sale.size()
		if by_type.get(data, 0.0) < target * share:
			candidates.append(data)
	if candidates.is_empty():
		return null
	return candidates.pick_random()

func _spawn(data: EnemyData, radius: float) -> void:
	var angle = randf() * TAU
	var offset = Vector2.RIGHT.rotated(angle) * radius
	var enemy = enemy_scene.instantiate()
	enemy.enemy_data = data
	enemy.global_position = player.global_position + offset
	add_child(enemy)
	enemy.died.connect(player.add_kill)
