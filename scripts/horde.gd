extends Node
class_name Horde

## Реестр врагов и всё, что ищет их по месту (срезы С1 и С2 плана орды). Каждый шаг
## физики, раньше врагов и игрока: копия позиций, сетка, толчок от соседей, касание игрока.
## Враг двигается сам и берёт свой толчок из sep_vel по своему horde_index.
## По той же сетке снаряды и зоны узнают, кого задели (query_hits), а оружие выбирает
## цели (pick). Физики у врагов, игрока, снарядов и зон нет: это Node2D.

## Клетка сетки. Не меньше наибольшей суммы радиусов тел пары (орк + орк = 100):
## иначе перекрытый сосед окажется через клетку и не найдётся.
const CELL: float = 100.0
const INV_CELL: float = 1.0 / CELL
## Сетка накрывает толпу, но не больше MAX_CELLS клеток по стороне:
## кто дальше, ложится в крайнюю клетку. Толкаются они верно, только дороже.
const MAX_CELLS: int = 64

## Предел расталкивания каждого врага не ниже его скорости, умноженной на это число.
## Иначе враг идёт к игроку быстрее, чем соседи успевают его отталкивать, продавливает
## толпу и сбивается в точку с другими. 1.0 — на грани, толпа медленно оседает к игроку;
## 1.1 — плотность как до новых скоростей гоблина и ловкача; больше — толпа реже.
## max_separation_speed в поведении может поднять предел выше, но не опустить.
## Скорость берётся из EnemyData.speed, а не текущая: рывок громилы (700) по-прежнему
## проламывает толпу. Читается при появлении врага.
@export_range(1.0, 3.0, 0.05) var push_to_speed: float = 1.1

## Живые и ещё не удалённые враги. Номер в списке — Enemy.horde_index.
var enemies: Array[Enemy] = []
## Скорость расталкивания каждого врага в этом шаге.
var sep_vel := PackedVector2Array()
## Сколько врагов касаются игрока в этом шаге.
var touching_player: int = 0
## Сколько раз враг перекрыт соседом в этом шаге (пара считается дважды) — мера плотности толпы.
var overlaps: int = 0

# Числа врага копируются при появлении, чтобы цикл не ходил через ресурсы.
# В циклах ниже у массивов локальные имена — так быстрее. Упакованный массив в Godot 4
# общий: запись через локальное имя меняет само поле.
var _pos := PackedVector2Array()
var _radius := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _response := PackedFloat32Array()
var _max_push := PackedFloat32Array()
var _contact_r2 := PackedFloat32Array()
var _contact_damage := PackedFloat32Array()
# Радиус тела для попаданий (Enemy.get_hit_radius) и наибольший из них:
# на столько запрос попадания расширяет поиск по сетке.
var _hit_radius := PackedFloat32Array()
var _max_hit_radius: float = 0.0

# Сетка — сортировка подсчётом: в клетке c лежат _sorted[_cell_start[c] .. + _cell_count[c]].
var _cell_of := PackedInt32Array()
var _sorted := PackedInt32Array()
var _cell_count := PackedInt32Array()
var _cell_start := PackedInt32Array()
var _cell_fill := PackedInt32Array()
var _origin := Vector2.ZERO
var _grid_w: int = 0
var _grid_h: int = 0
# Сетка разложена по нынешним номерам реестра. Удаление врага переставляет номера,
# и до следующего шага первый запрос раскладывает сетку заново (_ensure_grid).
var _grid_ok: bool = false

var _player: Player
# Позиция игрока в начале шага: по ней удары врагов попадают в игрока.
var _player_pos := Vector2.ZERO


func _enter_tree() -> void:
	add_to_group(&"horde")


func _ready() -> void:
	# Раньше врагов (у них 0): толчок этого шага готов, когда враг двигается.
	process_physics_priority = -1
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player != null:
		_player_pos = _player.global_position
	var cells := MAX_CELLS * MAX_CELLS
	_cell_count.resize(cells)
	_cell_start.resize(cells)
	_cell_fill.resize(cells)


## Новый враг попадает в сетку при её следующей раскладке: до неё удары его не видят,
## как раньше физика не видела новое тело до своего шага.
func register(enemy: Enemy) -> void:
	var data := enemy.enemy_data
	enemy.horde_index = enemies.size()
	enemies.append(enemy)
	_pos.append(enemy.global_position)
	_radius.append(data.body_radius)
	_mass.append(data.mass)
	_response.append(data.behavior.separation_response)
	_max_push.append(maxf(data.behavior.max_separation_speed, data.speed * push_to_speed))
	var hit_r := enemy.get_hit_radius()
	_hit_radius.append(hit_r)
	_max_hit_radius = maxf(_max_hit_radius, hit_r)
	var touch: float = hit_r + (_player.hurt_radius if _player != null else 0.0)
	_contact_r2.append(touch * touch)
	_contact_damage.append(data.contact_damage)
	sep_vel.append(Vector2.ZERO)
	_cell_of.append(0)
	_sorted.append(0)


## Убирает врага, ставя на его место последнего: номера остальных не сдвигаются.
func unregister(enemy: Enemy) -> void:
	var i := enemy.horde_index
	var last := enemies.size() - 1
	if i < 0 or i > last or enemies[i] != enemy:
		return
	if i != last:
		var moved := enemies[last]
		enemies[i] = moved
		moved.horde_index = i
		_pos[i] = _pos[last]
		_radius[i] = _radius[last]
		_mass[i] = _mass[last]
		_response[i] = _response[last]
		_max_push[i] = _max_push[last]
		_contact_r2[i] = _contact_r2[last]
		_contact_damage[i] = _contact_damage[last]
		_hit_radius[i] = _hit_radius[last]
		sep_vel[i] = sep_vel[last]
	enemies.resize(last)
	_pos.resize(last)
	_radius.resize(last)
	_mass.resize(last)
	_response.resize(last)
	_max_push.resize(last)
	_contact_r2.resize(last)
	_contact_damage.resize(last)
	_hit_radius.resize(last)
	sep_vel.resize(last)
	_cell_of.resize(last)
	_sorted.resize(last)
	enemy.horde_index = -1
	_grid_ok = false


func _physics_process(delta: float) -> void:
	touching_player = 0
	overlaps = 0
	_grid_ok = false
	if not is_instance_valid(_player) or _player.is_dead:
		return
	_player_pos = _player.global_position
	var count := enemies.size()
	if count == 0:
		return
	_read_positions(count)
	_build_grid(count)
	_grid_ok = true
	_push_apart(count)
	_touch_player(count, delta)


## Кого задевает удар фигурой shape с центром at: живых врагов (hit_enemies) и игрока
## (hit_player), кроме exclude. Позиции — снимок начала шага: по тем же позициям физика
## раньше сообщала о касаниях. limit > 0 — не больше limit ближайших к центру удара.
func query_hits(shape: HitShape, at: Vector2, hit_enemies: bool, hit_player: bool, exclude: Actor, limit: int) -> Array[Actor]:
	var targets: Array[Actor] = []
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
		var pos := _pos
		var hit_radius := _hit_radius
		var cnt := _cell_count
		var start := _cell_start
		var sorted := _sorted
		for gy in range(y0, y1 + 1):
			var row := gy * w
			for gx in range(x0, x1 + 1):
				var s: int = start[row + gx]
				for k in range(s, s + cnt[row + gx]):
					var j: int = sorted[k]
					var p: Vector2 = pos[j]
					var r: float = hit_radius[j]
					var d2 := at.distance_squared_to(p)
					var lim := bound + r
					if d2 >= lim * lim:
						continue
					var enemy := enemies[j]
					# Убитый в этом шаге ждёт удаления, но уже не цель.
					if enemy.is_dead or enemy == exclude:
						continue
					if not exact and not shape.touches(at, p, r):
						continue
					targets.append(enemy)
					dist2.append(d2)
	if hit_player and is_instance_valid(_player) and not _player.is_dead and _player != exclude:
		var r := _player.hit_radius
		if shape.touches(at, _player_pos, r):
			targets.append(_player)
			dist2.append(at.distance_squared_to(_player_pos))
	if limit > 0 and targets.size() > limit:
		_keep_nearest(targets, dist2, limit)
	return targets


## Цели оружия: count живых врагов, ближайших к origin (NEAREST), самых дальних (FARTHEST)
## или случайных (RANDOM). Позиции нынешние, как раньше у оружия: оно стреляет вне шага
## физики, когда враги уже сдвинулись со снимка, и целится по нынешним позициям.
func pick(origin: Vector2, mode: WeaponData.TargetMode, count: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if count <= 0 or enemies.is_empty():
		return result
	if mode == WeaponData.TargetMode.RANDOM:
		return _pick_random(count)
	# Очко — квадрат расстояния, у FARTHEST со знаком минус. Лучшие лежат по возрастанию очка.
	var sign_mult := -1.0 if mode == WeaponData.TargetMode.FARTHEST else 1.0
	var scores := PackedFloat64Array()
	for enemy in enemies:
		if enemy.is_dead:
			continue
		var score := origin.distance_squared_to(enemy.global_position) * sign_mult
		var filled := result.size()
		if filled == count and score >= scores[filled - 1]:
			continue
		var place := filled
		while place > 0 and scores[place - 1] > score:
			place -= 1
		result.insert(place, enemy)
		scores.insert(place, score)
		if filled == count:
			result.resize(count)
			scores.resize(count)
	return result


## Случайные живые без повторов, как раньше: перемешать всех живых и взять первых.
func _pick_random(count: int) -> Array[Node2D]:
	var alive: Array[Node2D] = []
	for enemy in enemies:
		if not enemy.is_dead:
			alive.append(enemy)
	alive.shuffle()
	if alive.size() > count:
		alive.resize(count)
	return alive


## Оставляет limit ближайших, ближний первым: частичная сортировка выбором, целей немного.
static func _keep_nearest(targets: Array[Actor], dist2: PackedFloat64Array, limit: int) -> void:
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


## Сетка для запроса. Удаление врага переставило номера реестра: раскладываем заново
## по снимку позиций (он переезжает вместе с номером, у новых врагов — место появления).
func _ensure_grid() -> bool:
	if _grid_ok:
		return true
	var count := enemies.size()
	if count == 0:
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _pos:
		lo = lo.min(p)
		hi = hi.max(p)
	_fit_grid(lo, hi)
	_build_grid(count)
	_grid_ok = true
	return true


## Позиции начала шага: все толкаются по одному снимку, а не по уже сдвинутым соседям.
func _read_positions(count: int) -> void:
	var pos := _pos
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in count:
		var p: Vector2 = enemies[i].global_position
		pos[i] = p
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
	var pos := _pos
	var ox := _origin.x
	var oy := _origin.y
	for i in count:
		var p: Vector2 = pos[i]
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
		sorted[fill[c]] = i
		fill[c] += 1


## Формула прежняя (было в EnemyBehaviorData._get_separation): каждый перекрытый сосед
## толкает на глубину перекрытия, доля толчка — масса соседа к сумме масс; плюс толчок
## от игрока; итог × separation_response, не больше предела. Пишет только свою строку.
func _push_apart(count: int) -> void:
	var pos := _pos
	var radius := _radius
	var mass := _mass
	var response := _response
	var max_push := _max_push
	var cell_of := _cell_of
	var cnt := _cell_count
	var start := _cell_start
	var sorted := _sorted
	var out := sep_vel
	var w := _grid_w
	var h := _grid_h
	var player_pos := _player.global_position
	var player_radius := _player.body_radius
	var player_mass := _player.mass
	var overlap_count := 0
	for i in count:
		var p: Vector2 = pos[i]
		var ri: float = radius[i]
		var mi: float = mass[i]
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
					if j == i:
						continue
					var offset: Vector2 = p - pos[j]
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
		out[i] = (push * response[i]).limit_length(max_push[i])
	overlaps = overlap_count


## Касание: центры ближе, чем hurt_radius игрока плюс радиус тела врага — то, что раньше
## ловил HurtBox. Урон всех касающихся одним вызовом, как было у игрока.
func _touch_player(count: int, delta: float) -> void:
	var pos := _pos
	var touch_r2 := _contact_r2
	var damage := _contact_damage
	var player_pos := _player.global_position
	var total := 0.0
	var touching := 0
	for i in count:
		if player_pos.distance_squared_to(pos[i]) < touch_r2[i]:
			# Убитый в этом шаге ждёт удаления, но уже не бьёт.
			if enemies[i].is_dead:
				continue
			total += damage[i]
			touching += 1
	touching_player = touching
	if total > 0.0:
		_player.take_damage(total * delta)


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
