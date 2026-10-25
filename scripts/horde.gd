extends Node
class_name Horde

## Рядовые враги — строки в массивах этого узла, а не узлы (срез С4 плана орды).
## Каждый шаг физики, раньше игрока, снарядов и зон, Horde ведёт всю толпу: копия позиций,
## сетка, толчок от соседей, касание игрока (срезы С1 и С2), тики эффектов (EffectTable,
## срез С3) и ход каждой строки в порядке появления, как раньше шли узлы врагов.
## По той же сетке зоны и снаряды узнают, кого задели (query_hits; снаряды Shots — все
## разом, ядром на C++, по целям из lend_targets), а оружие выбирает цели (pick).
## Цель удара — номер: строка врага (0 и больше) или PLAYER. Урон, эффекты
## и вспышки идут через Horde (hurt, apply_effect, flash) — и врагам, и игроку.
## Рисует врагов MultiMesh, по одному на тип (EnemyData).
## Номер строки действителен до конца кадра, в котором врага убрали; потом его получает
## следующий враг. Кто держит номер дольше (снаряд — номер стрелка), сверяет generation().

## Убит враг: раньше гема и уборки, как раньше сигнал Enemy.died.
signal died(target: int)

## Номер игрока как цели удара и эффекта.
const PLAYER: int = -1
## Нет цели.
const NOBODY: int = -2
## Кого бьют враги: группа цели их ударов, как раньше Enemy.get_target_group().
const FOES: StringName = &"player"

## Клетка сетки. Не меньше наибольшей суммы радиусов тел пары (орк + орк = 100):
## иначе перекрытый сосед окажется через клетку и не найдётся.
const CELL: float = 100.0
const INV_CELL: float = 1.0 / CELL
## Сетка накрывает толпу, но не больше MAX_CELLS клеток по стороне:
## кто дальше, ложится в крайнюю клетку. Толкаются они верно, только дороже.
const MAX_CELLS: int = 64

## Враги рисуются над фоном (у него -200), но под игроком, снарядами и гемами (у них 0).
## Внутри — слоями по типу, см. EnemyData.draw_order.
const DRAW_Z: int = -100
## Вспышка удара по врагу: те же числа, что у Actor (hit_flash_duration, hit_flash_color).
const HIT_FLASH_DURATION: float = 0.12
const HIT_FLASH_COLOR := Color(1, 0.3, 0.3)
## Картинка типа без своей текстуры: голова гоблина, как в прежней сцене врага.
const DEFAULT_TEXTURE: Texture2D = preload("res://media/goblin-head-svgrepo-com.svg")
const TINT_SHADER: Shader = preload("res://resources/shader/black_shader.gdshader")
# Чисел на экземпляр MultiMesh: базис и позиция (8), цвет (4).
const STRIDE: int = 12

## Предел расталкивания каждого врага не ниже его скорости, умноженной на это число.
## Иначе враг идёт к игроку быстрее, чем соседи успевают его отталкивать, продавливает
## толпу и сбивается в точку с другими. 1.0 — на грани, толпа медленно оседает к игроку;
## 1.1 — плотность как до новых скоростей гоблина и ловкача; больше — толпа реже.
## max_separation_speed в поведении может поднять предел выше, но не опустить.
## Скорость берётся из EnemyData.speed, а не текущая: рывок громилы (700) по-прежнему
## проламывает толпу. Читается при появлении врага.
@export_range(1.0, 3.0, 0.05) var push_to_speed: float = 1.1
## Копию позиций, сетку, расталкивание и касания считает ядро на C++ (native/, библиотека
## bin/horde_core.gdextension) — те же формулы, что функции ниже, толпа та же до бита.
## Выключено или библиотека не загружена — считают сами эти функции на GDScript.
@export var native_core: bool = true

## Сколько врагов касаются игрока в этом шаге.
var touching_player: int = 0
## Сколько раз враг перекрыт соседом в этом шаге (пара считается дважды) — мера плотности толпы.
var overlaps: int = 0
## Сколько здоровья враги потеряли за всё время, без перебора на смерти. Для замеров.
var damage_dealt: float = 0.0
## Сколько врагов убито за всё время. По нему Shots видит, что посреди шага кто-то умер.
var deaths: int = 0

# ---------------------------------------------------------------- строки
# Колонки: номер строки — индекс во всех сразу. Числа врага копируются при появлении,
# чтобы цикл не ходил через ресурсы. В циклах ниже у массивов локальные имена — так
# быстрее. Упакованный массив в Godot 4 общий: запись через локальное имя меняет само поле.

## Позиция врага сейчас. Пишет ход строки, читают поведения.
var pos := PackedVector2Array()
## Скорость врага (EnemyData.speed) и множитель от эффектов: из нескольких замедлений
## действует сильнейшее, пишет EffectTable. Собственный ход поведение умножает на него.
var speed := PackedFloat64Array()
var speed_mult := PackedFloat64Array()
## Память поведения. Какие колонки и как читает каждое поведение — в его скрипте.
## float64, как были числа в словаре behavior_state: иначе путь врага разойдётся с прежним.
var state := PackedInt32Array()
var timer := PackedFloat64Array()
var angle := PackedFloat64Array()
var aim := PackedVector2Array()

var _data: Array[EnemyData] = []
var _behavior: Array[EnemyBehaviorData] = []
# Номер типа для отрисовки и номер экземпляра в его MultiMesh.
var _kind := PackedInt32Array()
var _inst := PackedInt32Array()
# Растёт, когда строка уходит: так держатель номера видит, что враг уже другой.
var _gen := PackedInt32Array()
var _dead := PackedByteArray()
# Убран из игры (убит или отстал), в конце кадра уйдёт из реестра.
var _removed := PackedByteArray()
var _health := PackedFloat64Array()
# Снимок позиций на начало шага: по нему толчок, касания и удары, как раньше по телам физики.
var _snap := PackedVector2Array()
var _sep_vel := PackedVector2Array()
var _radius := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _response := PackedFloat32Array()
var _max_push := PackedFloat32Array()
var _contact_r2 := PackedFloat32Array()
var _contact_damage := PackedFloat32Array()
# Радиус тела для попаданий (EnemyData.get_hit_radius) и наибольший из них:
# на столько запрос попадания расширяет поиск по сетке.
var _hit_radius := PackedFloat32Array()
var _max_hit_radius: float = 0.0
# Оттенок, как был у Actor: вспышка удара, эффект последнего стака, показанный цвет.
# Оттенок ждёт хода строки, пока поднят _tint_pending.
var _flash_left := PackedFloat64Array()
var _flash_color := PackedColorArray()
var _stack_effect: Array[StatusEffectData] = []
var _shown_tint := PackedColorArray()
var _tint_pending := PackedByteArray()
var _free_rows := PackedInt32Array()

# Реестр — номера строк в том порядке, в каком их держал прежний список врагов: новые
# в конец, на место ушедшего встаёт последний. В этом порядке сетка, удары и выбор целей.
var _reg := PackedInt32Array()
# Место строки в реестре, -1 — её там нет.
var _reg_at := PackedInt32Array()
# Строки реестра в порядке появления: так враги ходят и рисуются, как раньше шли узлы.
var _order := PackedInt32Array()
var _alive: int = 0

# Сетка — сортировка подсчётом: в клетке c лежат _sorted[_cell_start[c] .. + _cell_count[c]].
# _cell_of — по месту в реестре, в _sorted — номера строк.
var _cell_of := PackedInt32Array()
var _sorted := PackedInt32Array()
var _cell_count := PackedInt32Array()
var _cell_start := PackedInt32Array()
var _cell_fill := PackedInt32Array()
var _origin := Vector2.ZERO
var _grid_w: int = 0
var _grid_h: int = 0
# Сетка разложена по нынешнему реестру. Уход врага переставляет реестр,
# и до следующего шага первый запрос раскладывает сетку заново (_ensure_grid).
var _grid_ok: bool = false
# Ядро на C++ (класс HordeCore из библиотеки) или null — тогда толпу считает GDScript.
# Тип Object, а не HordeCore: без библиотеки этого класса нет, и скрипт не собрался бы.
var _core: Object

var _player: Player
# Позиция игрока в начале шага: по ней удары врагов попадают в игрока.
var _player_pos := Vector2.ZERO
var _effects: EffectTable
var _gems: Gems

# Убраны в этом кадре, по порядку уборки: из реестра уйдут в конце кадра.
var _leaving := PackedInt32Array()
var _end_queued: bool = false

# Отрисовка: тип — свой MultiMesh. В _drawn у типа номера строк по экземплярам,
# в порядке появления: раньше спрайты одного типа так и ложились друг на друга.
var _kind_ids: Dictionary = {}
var _views: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
var _drawn: Array[PackedInt32Array] = []
# Тип переписывается в буфер целиком: появился или ушёл его враг.
var _redraw := PackedByteArray()
# Строки, у которых сменился показанный оттенок.
var _recolor := PackedInt32Array()
var _moved: bool = false
var _material: ShaderMaterial


func _enter_tree() -> void:
	add_to_group(&"horde")


func _ready() -> void:
	# Раньше игрока, снарядов и зон (у них 0): толпа ходит, пока игрок стоит там, где
	# закончил прошлый шаг, как раньше узлы врагов перед ним.
	process_physics_priority = -1
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player != null:
		_player_pos = _player.global_position
	_effects = get_tree().get_first_node_in_group(&"effect_table") as EffectTable
	_gems = get_tree().get_first_node_in_group(&"gems") as Gems
	var cells := MAX_CELLS * MAX_CELLS
	_cell_count.resize(cells)
	_cell_start.resize(cells)
	_cell_fill.resize(cells)
	# Материал у всех типов общий, как был у спрайтов врагов.
	_material = ShaderMaterial.new()
	_material.shader = TINT_SHADER
	use_native_core(native_core)


## Новый враг типа data в точке at. Ответ — номер его строки, NOBODY — не появился.
## В сетку он попадает при её следующей раскладке: до неё удары его не видят,
## как раньше физика не видела новое тело до своего шага.
func spawn(data: EnemyData, at: Vector2) -> int:
	if data == null:
		push_warning("Horde.spawn: EnemyData не задан.")
		return NOBODY
	var behavior := data.behavior
	if behavior == null:
		push_warning("EnemyDataBehavior не задан для: " + data.enemy_name)
		return NOBODY
	if _free_rows.is_empty():
		_grow()
	var last := _free_rows.size() - 1
	var t := _free_rows[last]
	_free_rows.resize(last)
	_data[t] = data
	_behavior[t] = behavior
	_dead[t] = 0
	_removed[t] = 0
	_health[t] = data.health
	pos[t] = at
	_snap[t] = at
	_sep_vel[t] = Vector2.ZERO
	speed[t] = data.speed
	speed_mult[t] = 1.0
	state[t] = 0
	timer[t] = 0.0
	angle[t] = 0.0
	aim[t] = Vector2.ZERO
	_radius[t] = data.body_radius
	_mass[t] = data.mass
	_response[t] = behavior.separation_response
	_max_push[t] = maxf(behavior.max_separation_speed, data.speed * push_to_speed)
	var hit_r := data.get_hit_radius()
	_hit_radius[t] = hit_r
	_max_hit_radius = maxf(_max_hit_radius, hit_r)
	var touch: float = hit_r + (_player.hurt_radius if _player != null else 0.0)
	_contact_r2[t] = touch * touch
	_contact_damage[t] = data.contact_damage
	_flash_left[t] = 0.0
	_flash_color[t] = Color.WHITE
	_stack_effect[t] = null
	_shown_tint[t] = Color.WHITE
	_tint_pending[t] = 0
	_reg_at[t] = _reg.size()
	_reg.append(t)
	_order.append(t)
	_alive += 1
	var kind := _kind_of(data)
	_kind[t] = kind
	var drawn := _drawn[kind]
	_inst[t] = drawn.size()
	drawn.append(t)
	_redraw[kind] = 1
	_queue_frame_end()
	return t


## Убирает врага из игры: убит или отстал. До конца кадра строка остаётся в реестре,
## как раньше узел до queue_free: удары этого кадра мёртвого пропускают, а сетка кадра
## не ломается. В конце кадра уходит из реестра в том же порядке, что и раньше.
func remove(target: int) -> void:
	if target < 0 or _removed[target]:
		return
	_removed[target] = 1
	if not _dead[target]:
		_alive -= 1
	_leaving.append(target)
	_queue_frame_end()


## ЕДИНСТВЕННЫЙ путь урона по номеру цели: прямое попадание, тик зоны, тик эффекта,
## реакция. Игроку — его take_damage. Врагу — как было у Actor.take_damage: убитый ударов
## не принимает, вспышка, здоровье не ниже нуля, на нуле — смерть: сигнал died, гем,
## уборка. effect — эффект, чей тик нанёс урон: вспышка его цветом. Прямой удар — null.
func hurt(target: int, amount: float, effect: StatusEffectData = null) -> void:
	if target == PLAYER:
		_player.take_damage(amount, effect)
		return
	if _dead[target]:
		return
	flash(target, effect.tint_color if effect != null else HIT_FLASH_COLOR)
	var before := _health[target]
	var left := maxf(before - amount, 0.0)
	_health[target] = left
	damage_dealt += before - left
	if left > 0.0:
		return
	# Смерть — событие: флаг поднят до сигнала, подписчик видит уже мёртвого.
	_dead[target] = 1
	deaths += 1
	if not _removed[target]:
		_alive -= 1
	died.emit(target)
	var data := _data[target]
	if data.gem_scene != null and _gems != null:
		_gems.drop(data.gem_scene, data.xp_reward, pos[target])
	remove(target)


## Единственная точка наложения эффекта. Стаки, тики и реакции ведёт EffectTable.
## На убитого не ложатся ни стаки, ни реакции: он только ждёт уборки.
## carrier — заряд снаряда (Shots.Charge) или зона: скорость атаки и крит в момент удара.
func apply_effect(target: int, effect: StatusEffectData, carrier: Object = null) -> void:
	if is_dead(target):
		return
	if _effects == null:
		push_warning("В сцене нет узла EffectTable: эффект %s не наложен." % effect.resource_path)
		return
	_effects.apply(target, effect, carrier)


## Вспышка удара цветом color. Врагу оттенок ляжет в его следующем ходе.
func flash(target: int, color: Color) -> void:
	if target == PLAYER:
		_player.flash_hit(color)
		return
	_flash_left[target] = HIT_FLASH_DURATION
	_flash_color[target] = color
	_tint_pending[target] = 1


## Последний наложенный стак цели сменился. Зовёт EffectTable, null — стаков не осталось.
func show_stack_tint(target: int, effect: StatusEffectData) -> void:
	if target == PLAYER:
		_player.show_stack_tint(effect)
		return
	if effect != _stack_effect[target]:
		_stack_effect[target] = effect
		_tint_pending[target] = 1


func get_speed_mult(target: int) -> float:
	if target == PLAYER:
		return _player.status_speed_mult
	return speed_mult[target]


func set_speed_mult(target: int, mult: float) -> void:
	if target == PLAYER:
		_player.status_speed_mult = mult
	else:
		speed_mult[target] = mult


func is_dead(target: int) -> bool:
	if target == PLAYER:
		return _player.is_dead
	return _dead[target] != 0


## Жив ли игрок как цель: удары врагов ищут его, только пока он жив.
func is_player_alive() -> bool:
	return is_instance_valid(_player) and not _player.is_dead


## Счётчик строки: растёт, когда строка уходит. Номер и счётчик вместе — один и тот же враг.
func generation(target: int) -> int:
	return _gen[target]


## Тот ли это враг, что был при generation: строка ещё не ушла и не досталась другому.
func is_same(target: int, gen: int) -> bool:
	return target >= 0 and _gen[target] == gen


func data_of(target: int) -> EnemyData:
	return _data[target]


func health(target: int) -> float:
	return _health[target]


func set_health(target: int, value: float) -> void:
	_health[target] = value


## Живые враги: не убиты и не убраны.
func alive_count() -> int:
	return _alive


## Живые враги в порядке появления.
func alive_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for t in _order:
		if not _dead[t] and not _removed[t]:
			rows.append(t)
	return rows


## Строк в реестре: живые и убранные в этом кадре.
func registry_size() -> int:
	return _reg.size()


## Отставших дальше limit от center убирает молча: без гема, без убийства и без сигнала.
## По порядку реестра, как раньше спавнер обходил список врагов.
func despawn_far(center: Vector2, limit: float) -> void:
	var reg := _reg
	var p_arr := pos
	for i in reg.size():
		var t: int = reg[i]
		if p_arr[t].distance_to(center) > limit:
			remove(t)


## Включает ядро на C++ (on) или отдаёт толпу GDScript. Ядро хранит только итог последнего
## вызова, поэтому переключать можно между любыми шагами: так стресс-сцена и пробы
## сравнивают оба пути. Нет библиотеки — предупреждение, и толпу считает GDScript.
func use_native_core(on: bool) -> void:
	native_core = on
	_core = null
	if not on:
		return
	if not ClassDB.class_exists(&"HordeCore"):
		push_warning("Ядро толпы на C++ не загружено (bin/horde_core.gdextension): толпу считает GDScript.")
		return
	_core = ClassDB.instantiate(&"HordeCore")
	_core.call(&"configure", INV_CELL, MAX_CELLS)


## Считает ли толпу ядро на C++.
func uses_native_core() -> bool:
	return _core != null


func _physics_process(delta: float) -> void:
	touching_player = 0
	overlaps = 0
	_grid_ok = false
	if is_instance_valid(_player) and not _player.is_dead:
		_player_pos = _player.global_position
		var count := _reg.size()
		if count > 0:
			if _core != null:
				_core_step(delta)
			else:
				_read_positions(count)
				_build_grid(count)
				_grid_ok = true
				_push_apart(count)
				_touch_player(count, delta)
	# Тики эффектов — до хода врагов, как раньше: убитый тиком в этом шаге не ходит.
	if _effects != null:
		_effects.step(delta)
	_act(delta)


## Ход строк в порядке появления, как раньше шли узлы врагов: оттенок, потом — если
## игрок жив — свой ход по поведению плюс толчок соседей и атака.
func _act(delta: float) -> void:
	var order := _order
	# Враг, появившийся в этом цикле, ходит со следующего шага, как раньше новый узел.
	var count := order.size()
	if count == 0:
		return
	var player_alive := is_instance_valid(_player) and not _player.is_dead
	# Игрок в этом цикле не двигается: его позиция одна на всех.
	var player_pos := _player.global_position if player_alive else Vector2.ZERO
	var dead := _dead
	var removed := _removed
	var pending := _tint_pending
	var p_arr := pos
	var sep := _sep_vel
	var behaviors := _behavior
	for k in count:
		var t: int = order[k]
		# Убитый или убранный ждёт конца кадра: ход и атака ему уже не положены.
		# Тики эффектов прошли раньше: убитый тиком сюда уже мёртвым.
		if dead[t] or removed[t]:
			continue
		if pending[t]:
			_update_tint(t, delta)
		if not player_alive:
			continue
		var behavior := behaviors[t]
		var velocity: Vector2 = behavior.get_velocity(self, t, player_pos, delta) + sep[t]
		p_arr[t] += velocity * delta
		behavior.try_attack(self, t, player_pos, delta)
	if player_alive:
		_moved = true
		_queue_frame_end()
	elif not _recolor.is_empty():
		_queue_frame_end()


## Оттенок строки в её ходе, как Actor._update_tint: вспышка удара, пока от неё что-то
## осталось в начале шага, иначе цвет последнего наложенного стака, иначе без оттенка.
## Зовётся только после события (удар, смена стаков) и до конца вспышки.
func _update_tint(t: int, delta: float) -> void:
	var tint := Color.WHITE
	if _flash_left[t] > 0.0:
		# Флаг не снимаем: в следующем шаге вспышку надо погасить.
		_flash_left[t] -= delta
		tint = Actor.make_tint(_flash_color[t], 1.0)
	else:
		_tint_pending[t] = 0
		var effect := _stack_effect[t]
		if effect != null:
			tint = Actor.make_tint(effect.tint_color, 0.6)
	if tint != _shown_tint[t]:
		_shown_tint[t] = tint
		_recolor.append(t)


## Кого задевает удар фигурой shape с центром at: живых врагов (hit_enemies) и игрока
## (hit_player), кроме строки exclude. Позиции — снимок начала шага: по тем же позициям
## физика раньше сообщала о касаниях. limit > 0 — не больше limit ближайших к центру удара.
## Ответ — номера целей, игрок — PLAYER.
func query_hits(shape: HitShape, at: Vector2, hit_enemies: bool, hit_player: bool, exclude: int, limit: int) -> PackedInt32Array:
	var targets := PackedInt32Array()
	var dist2 := PackedFloat64Array()
	if hit_enemies and _ensure_grid():
		var bound := shape.bound
		# У круга расстояние и есть точная проверка, collide() не нужен.
		var exact := shape.circle_radius >= 0.0
		var reach := bound + _max_hit_radius
		var w := _grid_w
		var h := _grid_h
		var x0 := clampi(int((at.x - reach - _origin.x) * INV_CELL), 0, w - 1)
		var x1 := clampi(int((at.x + reach - _origin.x) * INV_CELL), 0, w - 1)
		var y0 := clampi(int((at.y - reach - _origin.y) * INV_CELL), 0, h - 1)
		var y1 := clampi(int((at.y + reach - _origin.y) * INV_CELL), 0, h - 1)
		var snap := _snap
		var hit_radius := _hit_radius
		var dead := _dead
		var cnt := _cell_count
		var start := _cell_start
		var sorted := _sorted
		for gy in range(y0, y1 + 1):
			var row := gy * w
			for gx in range(x0, x1 + 1):
				var s: int = start[row + gx]
				for k in range(s, s + cnt[row + gx]):
					var j: int = sorted[k]
					var p: Vector2 = snap[j]
					var r: float = hit_radius[j]
					var d2 := at.distance_squared_to(p)
					var lim := bound + r
					if d2 >= lim * lim:
						continue
					# Убитый в этом шаге ждёт уборки, но уже не цель.
					if dead[j] or j == exclude:
						continue
					if not exact and not shape.touches(at, p, r):
						continue
					targets.append(j)
					dist2.append(d2)
	if hit_player and is_instance_valid(_player) and not _player.is_dead:
		var r := _player.hit_radius
		if shape.touches(at, _player_pos, r):
			targets.append(PLAYER)
			dist2.append(at.distance_squared_to(_player_pos))
	if limit > 0 and targets.size() > limit:
		_keep_nearest(targets, dist2, limit)
	return targets


## Цели для ядра снарядов (ShotsCore, срез С5): всё, по чему ищет query_hits, — снимок
## позиций, радиусы, убитые, generation, сетка, игрок и круг для collide(). Сетку
## раскладывает только поиск того, кто бьёт врагов (need_grid), как в query_hits.
## Ядро держит их до конца своего поиска и отпускает.
func lend_targets(core: Object, need_grid: bool) -> void:
	var grid := need_grid and _ensure_grid()
	var alive := is_player_alive()
	core.call(&"set_targets", _snap, _hit_radius, _dead, _gen, _cell_count, _cell_start, _sorted,
			_origin, _grid_w, _grid_h, INV_CELL, _max_hit_radius, grid, alive, _player_pos,
			_player.hit_radius if alive else 0.0, HitShape._unit_circle)


## Цели оружия — позиции count живых врагов: ближайших к origin (NEAREST), самых дальних
## (FARTHEST) или случайных (RANDOM). Позиции нынешние, как раньше у оружия: оно стреляет
## вне шага физики, когда враги уже сдвинулись со снимка, и целится по нынешним позициям.
func pick(origin: Vector2, mode: WeaponData.TargetMode, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if count <= 0 or _reg.is_empty():
		return result
	if mode == WeaponData.TargetMode.RANDOM:
		return _pick_random(count)
	# Очко — квадрат расстояния, у FARTHEST со знаком минус. Лучшие лежат по возрастанию очка.
	var sign_mult := -1.0 if mode == WeaponData.TargetMode.FARTHEST else 1.0
	var scores := PackedFloat64Array()
	var p_arr := pos
	for t in _reg:
		if _dead[t]:
			continue
		var p: Vector2 = p_arr[t]
		var score := origin.distance_squared_to(p) * sign_mult
		var filled := result.size()
		if filled == count and score >= scores[filled - 1]:
			continue
		var place := filled
		while place > 0 and scores[place - 1] > score:
			place -= 1
		result.insert(place, p)
		scores.insert(place, score)
		if filled == count:
			result.resize(count)
			scores.resize(count)
	return result


## Случайные живые без повторов, как раньше: перемешать всех живых и взять первых.
func _pick_random(count: int) -> PackedVector2Array:
	var alive := []
	for t in _reg:
		if not _dead[t]:
			alive.append(t)
	alive.shuffle()
	if alive.size() > count:
		alive.resize(count)
	var result := PackedVector2Array()
	for t: int in alive:
		result.append(pos[t])
	return result


## Оставляет limit ближайших, ближний первым: частичная сортировка выбором, целей немного.
static func _keep_nearest(targets: PackedInt32Array, dist2: PackedFloat64Array, limit: int) -> void:
	for a in limit:
		var best := a
		for b in range(a + 1, targets.size()):
			if dist2[b] < dist2[best]:
				best = b
		if best != a:
			var target := targets[a]
			targets[a] = targets[best]
			targets[best] = target
			var d := dist2[a]
			dist2[a] = dist2[best]
			dist2[best] = d
	targets.resize(limit)


## Сетка для запроса. Уход врага переставил реестр: раскладываем заново по снимку
## позиций (у новых врагов в нём место появления).
func _ensure_grid() -> bool:
	if _grid_ok:
		return true
	var count := _reg.size()
	if count == 0:
		return false
	if _core != null:
		_core.call(&"ensure_grid", _reg, _snap)
		_take_grid()
		_grid_ok = true
		return true
	var snap := _snap
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in _reg:
		var p: Vector2 = snap[t]
		lo = lo.min(p)
		hi = hi.max(p)
	_fit_grid(lo, hi)
	_build_grid(count)
	_grid_ok = true
	return true


## Шаг толпы ядром на C++: то же, что _read_positions, _build_grid, _push_apart и
## _touch_player ниже, одним вызовом. Ядро считает в свои копии массивов Horde, Horde
## забирает их себе: get() отдаёт ссылку на буфер ядра, без копирования.
func _core_step(delta: float) -> void:
	_core.call(&"step", _reg, pos, _snap, _sep_vel, _radius, _mass, _response, _max_push,
			_contact_r2, _contact_damage, _dead, _player.global_position, _player.body_radius, _player.mass)
	_snap = _core.get(&"snap")
	_sep_vel = _core.get(&"sep_vel")
	_take_grid()
	_grid_ok = true
	overlaps = _core.get(&"overlaps")
	touching_player = _core.get(&"touching")
	var total: float = _core.get(&"contact_total")
	if total > 0.0:
		_player.take_damage(total * delta)


## Сетку разложило ядро: её массивы и размеры — в поля Horde, по ним идут запросы.
func _take_grid() -> void:
	_cell_of = _core.get(&"cell_of")
	_sorted = _core.get(&"sorted")
	_cell_count = _core.get(&"cell_count")
	_cell_start = _core.get(&"cell_start")
	_origin = _core.get(&"origin")
	_grid_w = _core.get(&"grid_w")
	_grid_h = _core.get(&"grid_h")


## Позиции начала шага: все толкаются по одному снимку, а не по уже сдвинутым соседям.
func _read_positions(count: int) -> void:
	var reg := _reg
	var p_arr := pos
	var snap := _snap
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in count:
		var t: int = reg[i]
		var p: Vector2 = p_arr[t]
		snap[t] = p
		lo = lo.min(p)
		hi = hi.max(p)
	_fit_grid(lo, hi)


func _fit_grid(lo: Vector2, hi: Vector2) -> void:
	_origin = lo
	_grid_w = clampi(int((hi.x - lo.x) * INV_CELL) + 1, 1, MAX_CELLS)
	_grid_h = clampi(int((hi.y - lo.y) * INV_CELL) + 1, 1, MAX_CELLS)


func _build_grid(count: int) -> void:
	var w := _grid_w
	var h := _grid_h
	var cells := w * h
	var cnt := _cell_count
	cnt.fill(0)
	var cell_of := _cell_of
	var reg := _reg
	var snap := _snap
	var ox := _origin.x
	var oy := _origin.y
	for i in count:
		var p: Vector2 = snap[reg[i]]
		var c := mini(int((p.x - ox) * INV_CELL), w - 1) + mini(int((p.y - oy) * INV_CELL), h - 1) * w
		cell_of[i] = c
		cnt[c] += 1
	var start := _cell_start
	var fill := _cell_fill
	var acc := 0
	for c in cells:
		start[c] = acc
		fill[c] = acc
		acc += cnt[c]
	var sorted := _sorted
	for i in count:
		var c: int = cell_of[i]
		sorted[fill[c]] = reg[i]
		fill[c] += 1


## Формула прежняя (было в EnemyBehaviorData._get_separation): каждый перекрытый сосед
## толкает на глубину перекрытия, доля толчка — масса соседа к сумме масс; плюс толчок
## от игрока; итог × separation_response, не больше предела. Пишет только свою строку.
func _push_apart(count: int) -> void:
	var reg := _reg
	var snap := _snap
	var radius := _radius
	var mass := _mass
	var response := _response
	var max_push := _max_push
	var cell_of := _cell_of
	var cnt := _cell_count
	var start := _cell_start
	var sorted := _sorted
	var out := _sep_vel
	var w := _grid_w
	var h := _grid_h
	var player_pos := _player.global_position
	var player_radius := _player.body_radius
	var player_mass := _player.mass
	var overlap_count := 0
	for i in count:
		var t: int = reg[i]
		var p: Vector2 = snap[t]
		var ri: float = radius[t]
		var mi: float = mass[t]
		var c: int = cell_of[i]
		@warning_ignore("integer_division")
		var cy: int = c / w
		var cx: int = c - cy * w
		var push := Vector2.ZERO
		for gy in range(maxi(cy - 1, 0), mini(cy + 2, h)):
			var row := gy * w
			for gx in range(maxi(cx - 1, 0), mini(cx + 2, w)):
				var cc := row + gx
				var s: int = start[cc]
				for k in range(s, s + cnt[cc]):
					var j: int = sorted[k]
					if j == t:
						continue
					var offset: Vector2 = p - snap[j]
					var reach: float = ri + radius[j]
					var d2 := offset.length_squared()
					if d2 < reach * reach and d2 > 0.0:
						var d := sqrt(d2)
						var mj: float = mass[j]
						push += offset * ((reach - d) / d * mj / (mi + mj))
						overlap_count += 1
		var to_me := p - player_pos
		var reach_p := ri + player_radius
		var dp2 := to_me.length_squared()
		if dp2 < reach_p * reach_p and dp2 > 0.0:
			var dp := sqrt(dp2)
			push += to_me * ((reach_p - dp) / dp * player_mass / (mi + player_mass))
		out[t] = (push * response[t]).limit_length(max_push[t])
	overlaps = overlap_count


## Касание: центры ближе, чем hurt_radius игрока плюс радиус тела врага — то, что раньше
## ловил HurtBox. Урон всех касающихся одним вызовом, как было у игрока.
func _touch_player(count: int, delta: float) -> void:
	var reg := _reg
	var snap := _snap
	var touch_r2 := _contact_r2
	var damage := _contact_damage
	var dead := _dead
	var player_pos := _player.global_position
	var total := 0.0
	var touching := 0
	for i in count:
		var t: int = reg[i]
		if player_pos.distance_squared_to(snap[t]) < touch_r2[t]:
			# Убитый в этом шаге ждёт уборки, но уже не бьёт.
			if dead[t]:
				continue
			total += damage[t]
			touching += 1
	touching_player = touching
	if total > 0.0:
		_player.take_damage(total * delta)


# ---------------------------------------------------------------- конец кадра

func _queue_frame_end() -> void:
	if not _end_queued:
		_end_queued = true
		_frame_end.call_deferred()


## Конец кадра (и каждого шага физики): убранные уходят из реестра и с экрана,
## отрисовка получает новые позиции и цвета. Отложенный вызов доходит и на паузе.
func _frame_end() -> void:
	_end_queued = false
	if not _leaving.is_empty():
		_retire()
	_upload()


## Убранные в этом кадре уходят из реестра, по порядку уборки, и их стаки снимаются,
## как раньше в Enemy.leave(). Номер строки свободен. Порядок появления и экземпляры
## их типов собираются без них, остальные строки свой порядок не меняют.
func _retire() -> void:
	var reg := _reg
	var reg_at := _reg_at
	for t in _leaving:
		var i := reg_at[t]
		var last := reg.size() - 1
		if i != last:
			var moved := reg[last]
			reg[i] = moved
			reg_at[moved] = i
		reg.resize(last)
		reg_at[t] = -1
		if _effects != null:
			_effects.clear(t)
		_redraw[_kind[t]] = 1
		_gen[t] += 1
		_data[t] = null
		_behavior[t] = null
		_stack_effect[t] = null
		_free_rows.append(t)
	_leaving.clear()
	_grid_ok = false
	var order := _order
	var n := 0
	for k in order.size():
		var t: int = order[k]
		if reg_at[t] >= 0:
			order[n] = t
			n += 1
	order.resize(n)
	var redraw := _redraw
	for kind in redraw.size():
		if redraw[kind]:
			_drawn[kind].clear()
	for t in order:
		var kind := _kind[t]
		if redraw[kind]:
			var drawn := _drawn[kind]
			_inst[t] = drawn.size()
			drawn.append(t)


## Позиции и цвета экземпляров — в буферы MultiMesh, буферы — в отрисовку.
## Тип, где появился или ушёл враг, переписывается целиком; иначе только позиции
## (был ход) и сменившиеся цвета.
func _upload() -> void:
	var redraw := _redraw
	var shown := _shown_tint
	for t in _recolor:
		var kind := _kind[t]
		if _reg_at[t] < 0 or redraw[kind]:
			continue
		var at := _inst[t] * STRIDE + 8
		var c: Color = shown[t]
		var buffer := _buffers[kind]
		buffer[at] = c.r
		buffer[at + 1] = c.g
		buffer[at + 2] = c.b
		buffer[at + 3] = c.a
	var recolored := not _recolor.is_empty()
	_recolor.clear()
	var p_arr := pos
	for kind in _views.size():
		var drawn := _drawn[kind]
		var count := drawn.size()
		var buffer := _buffers[kind]
		var multimesh := _views[kind].multimesh
		if count > multimesh.instance_count:
			# Экземпляров не хватает: новый размер сбрасывает буфер в отрисовке.
			var capacity := maxi(64, nearest_po2(count))
			multimesh.instance_count = capacity
			buffer.resize(capacity * STRIDE)
			redraw[kind] = 1
		elif multimesh.instance_count == 0:
			# Тип ещё ни разу не рисовали и рисовать некого.
			redraw[kind] = 0
			continue
		if redraw[kind]:
			redraw[kind] = 0
			for i in count:
				var t: int = drawn[i]
				var p: Vector2 = p_arr[t]
				var c: Color = shown[t]
				var at := i * STRIDE
				# Поворота и масштаба у врага нет: базис единичный. Размер — у квада типа.
				buffer[at] = 1.0
				buffer[at + 3] = p.x
				buffer[at + 5] = 1.0
				buffer[at + 7] = p.y
				buffer[at + 8] = c.r
				buffer[at + 9] = c.g
				buffer[at + 10] = c.b
				buffer[at + 11] = c.a
		elif _moved:
			for i in count:
				var p: Vector2 = p_arr[drawn[i]]
				var at := i * STRIDE
				buffer[at + 3] = p.x
				buffer[at + 7] = p.y
		elif not recolored:
			continue
		var rid := multimesh.get_rid()
		RenderingServer.multimesh_set_buffer(rid, buffer)
		RenderingServer.multimesh_set_visible_instances(rid, count)
	_moved = false


## Номер типа для отрисовки: свой MultiMesh на каждый EnemyData, заводится с первым врагом.
func _kind_of(data: EnemyData) -> int:
	var known: Variant = _kind_ids.get(data)
	if known != null:
		return known
	var kind := _views.size()
	_kind_ids[data] = kind
	var texture := data.texture if data.texture != null else DEFAULT_TEXTURE
	var size := texture.get_size() * data.visual_scale
	# Высота квада со знаком минус: QuadMesh в 2D иначе рисует картинку вверх ногами.
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, -size.y)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	# Цвет экземпляра — оттенок врага: шейдер берёт его из COLOR, как раньше self_modulate.
	multimesh.use_colors = true
	multimesh.mesh = quad
	# Своя рамка на весь мир: рамку MultiMesh для отсечения за экраном Godot берёт
	# один раз и потом не обновляет (закон 72).
	multimesh.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	var view := MultiMeshInstance2D.new()
	view.name = "Enemies_" + (data.enemy_name if not data.enemy_name.is_empty() else str(kind))
	view.multimesh = multimesh
	view.texture = texture
	view.material = _material
	if data.pixel_art:
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.z_index = DRAW_Z + data.draw_order
	add_child(view)
	_views.append(view)
	_buffers.append(PackedFloat32Array())
	_drawn.append(PackedInt32Array())
	_redraw.append(1)
	return kind


## Строк не хватило: все колонки вдвое длиннее, новые номера свободны.
func _grow() -> void:
	var old := _gen.size()
	var size := maxi(old * 2, 256)
	_data.resize(size)
	_behavior.resize(size)
	_stack_effect.resize(size)
	pos.resize(size)
	speed.resize(size)
	speed_mult.resize(size)
	state.resize(size)
	timer.resize(size)
	angle.resize(size)
	aim.resize(size)
	_kind.resize(size)
	_inst.resize(size)
	_gen.resize(size)
	_dead.resize(size)
	_removed.resize(size)
	_health.resize(size)
	_snap.resize(size)
	_sep_vel.resize(size)
	_radius.resize(size)
	_mass.resize(size)
	_response.resize(size)
	_max_push.resize(size)
	_contact_r2.resize(size)
	_contact_damage.resize(size)
	_hit_radius.resize(size)
	_flash_left.resize(size)
	_flash_color.resize(size)
	_shown_tint.resize(size)
	_tint_pending.resize(size)
	_reg_at.resize(size)
	_cell_of.resize(size)
	_sorted.resize(size)
	# Свободные сверху вниз: первыми выдаются младшие номера.
	for t in range(size - 1, old - 1, -1):
		_reg_at[t] = -1
		_removed[t] = 1
		_free_rows.append(t)


## Фигура удара: круг (частый и дешёвый случай) или любая Shape2D с поворотом и масштабом.
## Строится один раз при появлении снаряда или зоны, центр приходит в каждый запрос.
class HitShape extends RefCounted:
	# Круг радиусом 1: тело врага или игрока для collide(), растянутый до своего радиуса.
	static var _unit_circle: CircleShape2D = _make_unit_circle()

	## Радиус круга в мире. Меньше нуля — фигура не круг: работают shape и basis.
	var circle_radius: float = -1.0
	var shape: Shape2D
	## Поворот и масштаб фигуры в мире, без позиции.
	var basis := Transform2D.IDENTITY
	## Радиус круга вокруг центра, в который вписана фигура: дальше запрос не ищет.
	var bound: float = 0.0

	static func circle(radius: float) -> HitShape:
		var hit := HitShape.new()
		hit.circle_radius = radius
		hit.bound = radius
		return hit

	## Масштаб в p_basis одинаковый по осям, как у снаряда (projectile_scale).
	static func from_shape(p_shape: Shape2D, p_basis: Transform2D) -> HitShape:
		var scale := p_basis.get_scale().x
		var round_shape := p_shape as CircleShape2D
		if round_shape != null:
			return circle(round_shape.radius * scale)
		var hit := HitShape.new()
		hit.shape = p_shape
		hit.basis = p_basis
		var rect := p_shape.get_rect()
		for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			hit.bound = maxf(hit.bound, corner.length() * scale)
		return hit

	## Задевает ли фигура с центром at круг радиусом radius вокруг center.
	func touches(at: Vector2, center: Vector2, radius: float) -> bool:
		if circle_radius >= 0.0:
			var reach := circle_radius + radius
			return at.distance_squared_to(center) < reach * reach
		var lim := bound + radius
		if at.distance_squared_to(center) >= lim * lim:
			return false
		var xform := basis
		xform.origin = at
		return shape.collide(xform, _unit_circle, Transform2D(0.0, Vector2(radius, radius), 0.0, center))

	static func _make_unit_circle() -> CircleShape2D:
		var unit := CircleShape2D.new()
		unit.radius = 1.0
		return unit
