extends Node
class_name Horde

## Реестр врагов и их расталкивание (срез С1 плана орды). Каждый шаг физики, раньше
## врагов и игрока: копия позиций, сетка, толчок от соседей, касание игрока.
## Враг двигается сам и берёт свой толчок из sep_vel по своему horde_index.
## Соседей ищет сетка, а не физика: у врага больше нет SeparationArea, у игрока — HurtBox.

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

# Сетка — сортировка подсчётом: в клетке c лежат _sorted[_cell_start[c] .. + _cell_count[c]].
var _cell_of := PackedInt32Array()
var _sorted := PackedInt32Array()
var _cell_count := PackedInt32Array()
var _cell_start := PackedInt32Array()
var _cell_fill := PackedInt32Array()
var _origin := Vector2.ZERO
var _grid_w: int = 0
var _grid_h: int = 0

var _player: Player


func _enter_tree() -> void:
	add_to_group(&"horde")


func _ready() -> void:
	# Раньше врагов (у них 0): толчок этого шага готов, когда враг двигается.
	process_physics_priority = -1
	_player = get_tree().get_first_node_in_group(&"player") as Player
	var cells := MAX_CELLS * MAX_CELLS
	_cell_count.resize(cells)
	_cell_start.resize(cells)
	_cell_fill.resize(cells)


func register(enemy: Enemy) -> void:
	var data := enemy.enemy_data
	enemy.horde_index = enemies.size()
	enemies.append(enemy)
	_pos.append(enemy.global_position)
	_radius.append(data.body_radius)
	_mass.append(data.mass)
	_response.append(data.behavior.separation_response)
	_max_push.append(maxf(data.behavior.max_separation_speed, data.speed * push_to_speed))
	var touch := enemy.get_contact_radius() + (_player.hurt_radius if _player != null else 0.0)
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
		sep_vel[i] = sep_vel[last]
	enemies.resize(last)
	_pos.resize(last)
	_radius.resize(last)
	_mass.resize(last)
	_response.resize(last)
	_max_push.resize(last)
	_contact_r2.resize(last)
	_contact_damage.resize(last)
	sep_vel.resize(last)
	_cell_of.resize(last)
	_sorted.resize(last)
	enemy.horde_index = -1


func _physics_process(delta: float) -> void:
	touching_player = 0
	overlaps = 0
	if not is_instance_valid(_player) or _player.is_dead:
		return
	var count := enemies.size()
	if count == 0:
		return
	_read_positions(count)
	_build_grid(count)
	_push_apart(count)
	_touch_player(count, delta)


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
