extends Node2D
class_name Shots

## Снаряды — строки в массивах этого узла, а не узлы (срез С5 плана орды). Снаряд игрока
## и снаряд врага — одна и та же строка: позиция, направление, траектория, фигура удара,
## кого бьёт, предел целей, стрелок и заряд (Charge) — снимок атакующих статов оружия.
## Каждый шаг физики, после игрока и всех узлов сцены (Shots стоит в конце Main), снаряды
## идут в порядке появления, как раньше узлы снарядов: кого задел — бьёт и уходит, иначе
## летит по траектории и стареет. Цели — по снимку Horde на начало шага (Horde.query_hits).
## Поиск целей и полёт считает ядро на C++ (класс ShotsCore из bin/horde_core.gdextension),
## удары — этот скрипт, по порядку и тем же кодом, что был у снаряда-узла.
## Рисует снаряды MultiMesh, по одному на вид (сцена снаряда и картинка).
## Номер снаряда действителен, пока снаряд летит; ушедший номер получает следующий выстрел.

## Снаряд появился: колонки заполнены, стрелок известен.
signal fired(shot: int)
## Удар снаряда shot по цели target — номеру в Horde (враг или Horde.PLAYER). Идёт до урона:
## подписчик видит цель такой, какой её застал снаряд.
signal hit(shot: int, target: int)
## Снаряд ушёл: ударил или кончилась жизнь. Номер освободится после шага.
signal retired(shot: int)

# Кого бьёт снаряд: биты колонки _flags.
const HITS_ENEMIES: int = 1
const HITS_PLAYER: int = 2
# Чисел на экземпляр MultiMesh: базис и позиция.
const STRIDE: int = 8
# Записей на снаряд в списке ударов ядра: место в порядке, номер, начало целей, их число,
# обрезан ли список пределом целей.
const EVENT: int = 5

## Поиск целей и полёт считает ядро на C++ (native/, класс ShotsCore библиотеки
## bin/horde_core.gdextension) — те же формулы, что функции ниже, бой тот же до бита.
## Выключено или в библиотеке нет ShotsCore — считают сами эти функции на GDScript.
@export var native_core: bool = true


## Заряд снаряда: снимок атакующих статов оружия в момент выстрела (WeaponData.arm_carrier).
## Апгрейд, взятый позже, летящий снаряд не меняет. Эффект при ударе берёт из заряда
## скорость атаки и крит (EffectTable.apply), как раньше из узла снаряда.
class Charge extends RefCounted:
	var damage: float = 1.0
	var crit_chance: float = 0.05
	var crit_mult: float = 2.0
	var attack_speed_mult: float = 1.0
	var weapon_bonuses: Dictionary = {}
	var on_hit_effects: Array[StatusEffectData] = []
	## Кого бьёт снаряд: врагов, игрока или обоих (френдли-фаер). Владельца не бьёт никогда.
	## По умолчанию никого: забытое присваивание даёт снаряд, который никого не бьёт,
	## а не снаряд, бьющий своих.
	var hits_enemies: bool = false
	var hits_player: bool = false


# ---------------------------------------------------------------- строки
# Колонки: номер снаряда — индекс во всех сразу. Числа оружия и траектории копируются
# при выстреле, чтобы шаг не ходил через ресурсы. Колонки без подчёркивания читают
# и пишут траектории (TrajectoryData); полёт ядром заменяет pos, travel_time и age
# новыми массивами, поэтому держать их в своих полях между шагами нельзя.

## Позиция снаряда сейчас.
var pos := PackedVector2Array()
## Направление полёта, единичное. Не меняется.
var direction := PackedVector2Array()
## Скорость (ProjectileWeaponData.projectile_speed).
var speed := PackedFloat64Array()
## Сколько снаряд летит волной: его пишет волна.
var travel_time := PackedFloat64Array()
## Сколько снаряд живёт: растёт после каждого шага полёта, если у снаряда есть срок.
var age := PackedFloat64Array()
## Числа волны (WaveTrajectoryData): их кладёт траектория при выстреле.
var wave_amplitude := PackedFloat64Array()
var wave_frequency := PackedFloat64Array()
var wave_phase := PackedFloat64Array()

# Направление, повёрнутое на PI/2: поперёк полёта, для волны.
var _side := PackedVector2Array()
# Режим полёта (TrajectoryData.Move) и сама траектория: её move() зовётся в режиме SCRIPT.
var _move := PackedByteArray()
var _trajectory: Array[TrajectoryData] = []
var _lifetime := PackedFloat64Array()
var _flags := PackedByteArray()
var _limit := PackedInt32Array()
# Стрелок: узел (игрок) или строка врага с её generation — своего стрелка снаряд не бьёт.
var _owner: Array[Actor] = []
var _owner_row := PackedInt32Array()
var _owner_gen := PackedInt32Array()
var _charge: Array[Charge] = []
# Фигура удара в мире: поворот и масштаб снаряда задаются при выстреле и дальше не меняются.
# Для ядра она же числами: радиус круга (меньше нуля — не круг), радиус охвата, базис
# (два вектора на снаряд) и номер фигуры в _shapes (-1 у круга).
var _hit_shape: Array[Horde.HitShape] = []
var _radius := PackedFloat64Array()
var _bound := PackedFloat64Array()
var _basis := PackedVector2Array()
var _shape := PackedInt32Array()
var _shapes: Array[Shape2D] = []
var _shape_ids: Dictionary = {}
# Шаг физики, в котором снаряд выпущен, или -1 — выпущен вне шага. Выпущенный в шаге
# летит со следующего, как новый узел, которого нет в списке уже идущего шага.
var _born := PackedInt64Array()
# Ушёл в этом шаге или номер свободен: в порядок не возвращается.
var _done := PackedByteArray()
# Вид для отрисовки и базис картинки (два вектора на снаряд): поворот и масштаб спрайта.
var _kind := PackedInt32Array()
var _view := PackedVector2Array()
var _free_rows := PackedInt32Array()
# Снаряды в порядке появления: так они ходят и рисуются, как раньше шли узлы.
var _order := PackedInt32Array()
# Ушли в этом шаге: номера свободны после шага.
var _leaving := PackedInt32Array()

# Сколько летящих снарядов бьют врагов и сколько из них выпущены в шаге _young_frame.
# Сетку Horde раскладывает только поиск того, кто бьёт врагов, как в query_hits.
var _enemy_hitters: int = 0
var _young_hitters: int = 0
var _young_frame: int = -1

var _horde: Horde
# Ядро на C++ (класс ShotsCore из библиотеки) или null — тогда снаряды считает GDScript.
# Тип Object, а не ShotsCore: без библиотеки этого класса нет, и скрипт не собрался бы.
var _core: Object

# Отрисовка: вид — свой MultiMesh. Буферы видов здесь — для пути на GDScript, у ядра свои.
var _kind_ids: Dictionary = {}
var _views: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
var _kind_count := PackedInt32Array()
var _capacity := PackedInt32Array()
var _shown := PackedInt32Array()
# Сцена снаряда — образец вида: картинка и масштаб её спрайта. В игру сцена не попадает.
var _sprites: Dictionary = {}
var _auto_shapes: Dictionary = {}
var _draw_queued: bool = false


func _enter_tree() -> void:
	add_to_group(&"shots")


func _ready() -> void:
	_horde = get_tree().get_first_node_in_group(&"horde") as Horde
	use_native_core(native_core)


## Выстрел оружия weapon из точки at по направлению dir (единичному). charge — снимок
## оружия (WeaponData.arm_carrier). Стрелок — узел owner_actor (игрок) или строка врага
## owner_row с её generation. Ответ — номер снаряда.
## Единственное место, где снаряд получает свои поля: новое поле добавляется сюда.
func fire(weapon: ProjectileWeaponData, at: Vector2, dir: Vector2, charge: Charge,
		owner_actor: Actor = null, owner_row: int = Horde.NOBODY, owner_gen: int = 0) -> int:
	var scene := weapon.projectile_scene
	var sprite := _sprite_of(scene)
	var texture: Texture2D = sprite[0]
	if weapon.texture != null:
		texture = weapon.texture
	var kind := _kind_of(scene, texture, sprite[1])
	if _free_rows.is_empty():
		_grow()
	var last := _free_rows.size() - 1
	var shot := _free_rows[last]
	_free_rows.resize(last)
	# Поворот и масштаб — как у прежнего узла снаряда: Node2D хранит поворот 32-битным,
	# и фигура удара строилась уже по нему.
	var turn := Vector2(dir.angle() + weapon.sprite_angle_offset, 0.0).x
	var shot_scale := Vector2.ONE * weapon.projectile_scale
	var hit_shape := Horde.HitShape.from_shape(_hit_shape_of(weapon, sprite[1]),
			Transform2D(turn + weapon.hitbox_angle_offset, shot_scale, 0.0, Vector2.ZERO))
	var view := Transform2D(turn, shot_scale, 0.0, Vector2.ZERO)
	pos[shot] = at
	direction[shot] = dir
	_side[shot] = dir.rotated(PI / 2)
	speed[shot] = weapon.projectile_speed
	travel_time[shot] = 0.0
	age[shot] = 0.0
	wave_amplitude[shot] = 0.0
	wave_frequency[shot] = 0.0
	wave_phase[shot] = 0.0
	var trajectory := weapon.base_trajectory
	if trajectory == null:
		push_warning("У оружия %s нет base_trajectory: снаряд летит прямо." % weapon.resource_path)
		_move[shot] = TrajectoryData.Move.STRAIGHT
	else:
		_move[shot] = trajectory.get_move()
	_trajectory[shot] = trajectory
	_lifetime[shot] = weapon.lifetime
	_limit[shot] = weapon.hit_limit
	var flags := (HITS_ENEMIES if charge.hits_enemies else 0) | (HITS_PLAYER if charge.hits_player else 0)
	_flags[shot] = flags
	_owner[shot] = owner_actor
	_owner_row[shot] = owner_row
	_owner_gen[shot] = owner_gen
	_charge[shot] = charge
	_hit_shape[shot] = hit_shape
	_radius[shot] = hit_shape.circle_radius
	_bound[shot] = hit_shape.bound
	_basis[shot * 2] = hit_shape.basis.x
	_basis[shot * 2 + 1] = hit_shape.basis.y
	_shape[shot] = _shape_id(hit_shape.shape)
	_kind[shot] = kind
	_view[shot * 2] = view.x
	_view[shot * 2 + 1] = view.y
	_kind_count[kind] += 1
	_done[shot] = 0
	var in_step := Engine.is_in_physics_frame()
	var frame := Engine.get_physics_frames()
	_born[shot] = frame if in_step else -1
	if flags & HITS_ENEMIES:
		_enemy_hitters += 1
		if in_step:
			if _young_frame != frame:
				_young_frame = frame
				_young_hitters = 0
			_young_hitters += 1
	_order.append(shot)
	# Последним, как раньше в _ready снаряда: траектория может бросить кубик.
	if trajectory != null:
		trajectory.on_spawn(self, shot)
	fired.emit(shot)
	_queue_draw()
	return shot


## Летящих снарядов.
func alive_count() -> int:
	return _order.size()


## Летящие снаряды в порядке появления.
func alive_rows() -> PackedInt32Array:
	return _order.duplicate()


## Стрелок-узел снаряда (игрок) или null у выстрела врага.
func owner_of(shot: int) -> Actor:
	return _owner[shot]


## Строка врага-стрелка или Horde.NOBODY.
func owner_row_of(shot: int) -> int:
	return _owner_row[shot]


## Включает ядро на C++ (on) или отдаёт снаряды GDScript. Между шагами ядро ничего своего
## не хранит, поэтому переключать можно между любыми шагами: так стресс-сцена и пробы
## сравнивают оба пути. Нет библиотеки или в ней нет ShotsCore — предупреждение,
## и снаряды считает GDScript.
func use_native_core(on: bool) -> void:
	native_core = on
	_core = null
	if not on:
		return
	if not ClassDB.class_exists(&"ShotsCore"):
		push_warning("Ядро снарядов на C++ не загружено (bin/horde_core.gdextension, класс ShotsCore): снаряды считает GDScript.")
		return
	_core = ClassDB.instantiate(&"ShotsCore")


## Считает ли снаряды ядро на C++.
func uses_native_core() -> bool:
	return _core != null


func _physics_process(delta: float) -> void:
	# Снаряд, выпущенный в этом цикле, летит со следующего шага, как раньше новый узел.
	var count := _order.size()
	if count == 0:
		return
	var frame := Engine.get_physics_frames()
	if _core != null:
		_step_core(count, frame, delta)
	else:
		_step_gd(count, frame, delta)
	_free_rows.append_array(_leaving)
	_leaving.clear()
	_queue_draw()


## Шаг ядром на C++. Ядро ищет цели всех снарядов шага разом, по убитым на начало шага.
## Удары — по порядку здесь же (_strike_all). Потом ядро двигает и старит тех, кто не ударил,
## и собирает порядок без ушедших. pos, travel_time и age ядро считает в свои копии,
## Shots забирает их себе.
func _step_core(count: int, frame: int, delta: float) -> void:
	var stop := count
	if _horde != null:
		var hitters := _enemy_hitters - (_young_hitters if _young_frame == frame else 0)
		_horde.lend_targets(_core, hitters > 0)
	var events: int = _core.call(&"query", _order, count, frame, _born, pos, _flags, _limit,
			_owner_row, _owner_gen, _radius, _bound, _basis, _shape, _shapes, _move)
	if events > 0:
		stop = _strike_all(_core.get(&"events"), _core.get(&"targets"), count, delta)
	_core.call(&"move", _order, stop, frame, _born, _done, _move, direction, _side, speed,
			wave_amplitude, wave_frequency, wave_phase, _lifetime, pos, travel_time, age, delta)
	_order = _core.get(&"order")
	pos = _core.get(&"pos")
	travel_time = _core.get(&"travel_time")
	age = _core.get(&"age")
	for shot: int in _core.get(&"expired") as PackedInt32Array:
		_finish(shot)


## Удары шага по порядку появления снарядов. Цели ядро нашло по убитым на начало шага.
## Если с тех пор кто-то умер, снаряд сверяет цели, как сверил бы снаряд-узел в свой черёд:
## без обрезки пределом убитые просто выбывают, обрезанный список ищется заново.
## Снаряд режима SCRIPT без целей летит здесь же, в свой черёд. Ответ — до какого места
## порядка дошёл шаг: удар, после которого игра встала на паузу (смерть игрока),
## останавливает шаг, как раньше пауза останавливала следующие узлы.
func _strike_all(events: PackedInt32Array, targets: PackedInt32Array, count: int, delta: float) -> int:
	var horde := _horde
	var deaths := horde.deaths if horde != null else 0
	var player_alive := horde != null and horde.is_player_alive()
	var tree := get_tree()
	for i in range(0, events.size(), EVENT):
		var shot := events[i + 1]
		var n := events[i + 3]
		var struck := PackedInt32Array()
		if n > 0:
			var first := events[i + 2]
			struck = targets.slice(first, first + n)
			if horde.deaths != deaths or (player_alive and not horde.is_player_alive()):
				struck = _query(shot) if events[i + 4] else _alive_only(struck)
		if not struck.is_empty():
			_strike(shot, struck)
			_finish(shot)
			if tree.paused:
				return events[i] + 1
		elif _move[shot] == TrajectoryData.Move.SCRIPT:
			_fly(shot, delta)
	return count


## Шаг на GDScript, запасной путь без ядра: снаряд за снарядом, как раньше узлы.
func _step_gd(count: int, frame: int, delta: float) -> void:
	var order := _order
	var born := _born
	var tree := get_tree()
	for k in count:
		var shot: int = order[k]
		if born[shot] == frame:
			continue
		if _horde != null:
			var struck := _query(shot)
			if not struck.is_empty():
				_strike(shot, struck)
				_finish(shot)
				# Пауза (смерть игрока) останавливает шаг: дальше снаряды стоят.
				if tree.paused:
					break
				continue
		_fly(shot, delta)
	var done := _done
	var n := 0
	for k in order.size():
		var shot: int = order[k]
		if not done[shot]:
			order[n] = shot
			n += 1
	order.resize(n)


## Цели снаряда сейчас — тот же запрос, что был у снаряда-узла. Враг-стрелок своим
## снарядом себя не бьёт, пока он тот же (френдли-фаер).
func _query(shot: int) -> PackedInt32Array:
	var owner_row := _owner_row[shot]
	var exclude := owner_row if _horde.is_same(owner_row, _owner_gen[shot]) else Horde.NOBODY
	var flags := _flags[shot]
	return _horde.query_hits(_hit_shape[shot], pos[shot], (flags & HITS_ENEMIES) != 0,
			(flags & HITS_PLAYER) != 0, exclude, _limit[shot])


## Цели, которые ещё живы: убитые после поиска выбывают, остальные стоят в том же порядке.
func _alive_only(targets: PackedInt32Array) -> PackedInt32Array:
	var alive := PackedInt32Array()
	for target in targets:
		if not _horde.is_dead(target):
			alive.append(target)
	return alive


## Удар снаряда по целям, как было у снаряда-узла: сигнал до урона, крит, урон, эффекты
## оружия с зарядом снаряда.
func _strike(shot: int, targets: PackedInt32Array) -> void:
	var charge := _charge[shot]
	var horde := _horde
	for target in targets:
		hit.emit(shot, target)
		var final_damage = WeaponData.roll_crit(charge.damage, charge.crit_chance, charge.crit_mult)
		horde.hurt(target, final_damage)
		for effect in charge.on_hit_effects:
			if effect != null:
				horde.apply_effect(target, effect, charge)


## Полёт снаряда на шаг, потом возраст. Формулы те же, что были у траекторий узла
## (global_position += …), и те же, что в ядре (ShotsCore.move).
func _fly(shot: int, delta: float) -> void:
	var move := _move[shot]
	if move == TrajectoryData.Move.STRAIGHT:
		pos[shot] += direction[shot] * speed[shot] * delta
	elif move == TrajectoryData.Move.WAVE:
		var t := travel_time[shot] + delta
		travel_time[shot] = t
		var forward: Vector2 = direction[shot] * speed[shot]
		var frequency := wave_frequency[shot]
		var phase: float = t * frequency + wave_phase[shot]
		var lateral_displacement_rate: Vector2 = _side[shot] * wave_amplitude[shot] * frequency * cos(phase)
		pos[shot] += (forward + lateral_displacement_rate) * delta
	else:
		_trajectory[shot].move(self, shot, delta)
	var lifetime := _lifetime[shot]
	if lifetime > 0.0:
		var lived := age[shot] + delta
		age[shot] = lived
		if lived >= lifetime:
			_finish(shot)


## Снаряд уходит: ударил или кончилась жизнь. Из порядка он выпадет в конце шага,
## номер освободится после шага.
func _finish(shot: int) -> void:
	_done[shot] = 1
	_kind_count[_kind[shot]] -= 1
	if _flags[shot] & HITS_ENEMIES:
		_enemy_hitters -= 1
	retired.emit(shot)
	_owner[shot] = null
	_charge[shot] = null
	_hit_shape[shot] = null
	_trajectory[shot] = null
	_leaving.append(shot)


# ---------------------------------------------------------------- вид и фигура

## Картинка и масштаб спрайта сцены снаряда (её узел Sprite2D): сцена — образец вида.
func _sprite_of(scene: PackedScene) -> Array:
	var known: Variant = _sprites.get(scene)
	if known != null:
		return known
	var texture: Texture2D = null
	var sprite_scale := Vector2.ONE
	if scene != null:
		var sample := scene.instantiate()
		var sprite := sample.get_node_or_null(^"Sprite2D") as Sprite2D
		if sprite != null:
			texture = sprite.texture
			sprite_scale = sprite.scale
		sample.free()
	var look := [texture, sprite_scale]
	_sprites[scene] = look
	return look


## Фигура удара оружия: своя (collision_shape); без неё — прямоугольник по картинке оружия
## в масштабе спрайта сцены; без картинки — круг радиусом 10, как было у снаряда-узла.
func _hit_shape_of(weapon: ProjectileWeaponData, sprite_scale: Vector2) -> Shape2D:
	if weapon.collision_shape:
		return weapon.collision_shape
	var key := [weapon.texture, sprite_scale]
	var known: Variant = _auto_shapes.get(key)
	if known != null:
		return known
	var shape: Shape2D
	if weapon.texture:
		var auto_shape := RectangleShape2D.new()
		auto_shape.size = weapon.texture.get_size() * sprite_scale
		shape = auto_shape
	else:
		shape = CircleShape2D.new()
	_auto_shapes[key] = shape
	return shape


# Номер фигуры для ядра: фигуры не-круги лежат в _shapes по одной.
func _shape_id(shape: Shape2D) -> int:
	if shape == null:
		return -1
	var known: Variant = _shape_ids.get(shape)
	if known != null:
		return known
	var id := _shapes.size()
	_shapes.append(shape)
	_shape_ids[shape] = id
	return id


## Номер вида для отрисовки: свой MultiMesh на каждую пару «сцена снаряда + картинка»,
## заводится с первым снарядом. Размер квада — картинка в масштабе спрайта сцены.
func _kind_of(scene: PackedScene, texture: Texture2D, sprite_scale: Vector2) -> int:
	var key := [scene, texture]
	var known: Variant = _kind_ids.get(key)
	if known != null:
		return known
	var kind := _views.size()
	_kind_ids[key] = kind
	var size := texture.get_size() * sprite_scale if texture != null else Vector2.ZERO
	# Высота квада со знаком минус: QuadMesh в 2D иначе рисует картинку вверх ногами.
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, -size.y)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = quad
	# Своя рамка на весь мир: рамку MultiMesh для отсечения за экраном Godot берёт
	# один раз и потом не обновляет (закон 72).
	multimesh.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	var view := MultiMeshInstance2D.new()
	view.name = "Shots_" + (texture.resource_path.get_file().get_basename() if texture != null else str(kind))
	view.multimesh = multimesh
	view.texture = texture
	add_child(view)
	_views.append(view)
	_buffers.append(PackedFloat32Array())
	_kind_count.append(0)
	_capacity.append(0)
	_shown.append(0)
	return kind


## Строк не хватило: все колонки вдвое длиннее, новые номера свободны.
func _grow() -> void:
	var old := _done.size()
	var size := maxi(old * 2, 256)
	pos.resize(size)
	direction.resize(size)
	speed.resize(size)
	travel_time.resize(size)
	age.resize(size)
	wave_amplitude.resize(size)
	wave_frequency.resize(size)
	wave_phase.resize(size)
	_side.resize(size)
	_move.resize(size)
	_trajectory.resize(size)
	_lifetime.resize(size)
	_flags.resize(size)
	_limit.resize(size)
	_owner.resize(size)
	_owner_row.resize(size)
	_owner_gen.resize(size)
	_charge.resize(size)
	_hit_shape.resize(size)
	_radius.resize(size)
	_bound.resize(size)
	_basis.resize(size * 2)
	_shape.resize(size)
	_born.resize(size)
	_done.resize(size)
	_kind.resize(size)
	_view.resize(size * 2)
	# Свободные сверху вниз: первыми выдаются младшие номера.
	for shot in range(size - 1, old - 1, -1):
		_done[shot] = 1
		_free_rows.append(shot)


# ---------------------------------------------------------------- отрисовка

func _queue_draw() -> void:
	if not _draw_queued:
		_draw_queued = true
		_draw_shots.call_deferred()


## Позиции снарядов — в буферы MultiMesh, по видам в порядке появления, буферы —
## в отрисовку. Отложенный вызов: после шага и после выстрелов вне шага, доходит и на паузе.
func _draw_shots() -> void:
	_draw_queued = false
	var kinds := _views.size()
	for kind in kinds:
		var multimesh := _views[kind].multimesh
		var need := _kind_count[kind]
		if need > multimesh.instance_count:
			# Экземпляров не хватает: новый размер сбрасывает буфер в отрисовке.
			multimesh.instance_count = maxi(64, nearest_po2(need))
			_buffers[kind].resize(multimesh.instance_count * STRIDE)
		_capacity[kind] = multimesh.instance_count
	var counts: PackedInt32Array
	var buffers: Array
	if _core != null:
		_core.call(&"draw", _order, _kind, _view, pos, _capacity)
		counts = _core.get(&"counts")
		buffers = _core.get(&"buffers")
	else:
		counts = _fill_buffers()
		buffers = _buffers
	for kind in kinds:
		var count := counts[kind]
		if count == 0 and _shown[kind] == 0:
			continue
		_shown[kind] = count
		var rid := _views[kind].multimesh.get_rid()
		if count > 0:
			RenderingServer.multimesh_set_buffer(rid, buffers[kind])
		RenderingServer.multimesh_set_visible_instances(rid, count)


## Буферы видов на GDScript (путь без ядра): поворот, масштаб и позиция каждого снаряда.
func _fill_buffers() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(_views.size())
	var p_arr := pos
	var view := _view
	var kinds := _kind
	for shot in _order:
		var kind := kinds[shot]
		var i := counts[kind]
		counts[kind] = i + 1
		var buffer := _buffers[kind]
		var at := i * STRIDE
		var x: Vector2 = view[shot * 2]
		var y: Vector2 = view[shot * 2 + 1]
		var p: Vector2 = p_arr[shot]
		buffer[at] = x.x
		buffer[at + 1] = y.x
		buffer[at + 3] = p.x
		buffer[at + 4] = x.y
		buffer[at + 5] = y.y
		buffer[at + 7] = p.y
	return counts
