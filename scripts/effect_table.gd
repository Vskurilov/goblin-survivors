extends Node
class_name EffectTable

## Все стаки статус-эффектов всех целей, врагов и игрока (срез С3 плана орды).
## Строка таблицы — один стак: снимок чисел эффекта и носителя в момент наложения.
## У каждой строки один кадр её ближайшего события (тик или конец), и шаг таблицы
## трогает только строки своего кадра, а не все стаки всех целей.
## Цель — номер в Horde: строка врага или Horde.PLAYER (срез С4). Номера строк каждой
## цели и её счётчики стихий (по ним реакции) таблица держит у себя, замедление цели
## пишет в Horde, урон и вспышки наносит через Horde.
## Шаг таблицы зовёт Horde в своём шаге физики: после толчка, раньше хода врагов.

## Колесо кадров. Событие дальше этого строка ждёт по частям: таблица будит её
## раньше, видит, что ещё рано, и перекладывает дальше.
const WHEEL: int = 256
## Допуск сравнения времён: тик ровно в момент конца стака ещё случается.
const EPS: float = 0.000001

# Колонки строк: номер строки — индекс во всех сразу.
# Цель стака — номер в Horde.
var _target := PackedInt32Array()
# Эффект оружия, с которого снят снимок: ключ стака, лимит, стихии и цвет берутся с него.
var _effect: Array[StatusEffectData] = []
var _key := PackedInt32Array()
var _elements := PackedInt32Array()
var _damage := PackedFloat64Array()
var _speed := PackedFloat64Array()
var _interval := PackedFloat64Array()
var _crit_chance := PackedFloat64Array()
var _crit_mult := PackedFloat64Array()
var _next_tick := PackedFloat64Array()
var _expire := PackedFloat64Array()
# Кадр, на который строка лежит в колесе; -1 — строка свободна.
var _due := PackedInt32Array()
var _free := PackedInt32Array()

# Ключ стака числом: stack_group или сам эффект → номер. Сравнивать числа дешевле.
var _key_ids: Dictionary = {}

# Стаки каждой цели — номера строк в порядке наложения — и сколько стаков каждой стихии
# на ней висит (номер стихии — в Tags.ELEMENTS). Индекс — номер цели плюс один:
# у игрока (Horde.PLAYER) это 0.
var _stacks: Array[PackedInt32Array] = []
var _element_stacks: Array[PackedInt32Array] = []

# Ячейка колеса — номера строк на кадр, у которого тот же остаток от деления на WHEEL.
var _wheel: Array[PackedInt32Array] = []
var _wheel_count := PackedInt32Array()

# Шаг физики таблицы и игровое время: на паузе стоят вместе с игрой.
var _frame: int = 0
var _now: float = 0.0
var _step: float = 1.0 / 60.0

var _horde: Horde


func _enter_tree() -> void:
	add_to_group(&"effect_table")


func _ready() -> void:
	_step = 1.0 / Engine.physics_ticks_per_second
	_wheel.resize(WHEEL)
	for slot in WHEEL:
		_wheel[slot] = PackedInt32Array()
	_wheel_count.resize(WHEEL)
	_horde = get_tree().get_first_node_in_group(&"horde") as Horde
	if _horde == null:
		push_warning("В сцене нет узла Horde: тикать эффектам некому.")


## Шаг таблицы: тики и концы стаков этого кадра. Зовёт Horde в своём шаге физики,
## раньше хода врагов: тик, который убил, случился до хода врага.
func step(delta: float) -> void:
	_frame += 1
	_now += delta
	_step = delta
	var slot := _frame % WHEEL
	var count := _wheel_count[slot]
	if count == 0:
		return
	# Ячейка освобождается сразу: всё, что ниже переложено, ляжет в другие (_schedule
	# откладывает не меньше чем на кадр и меньше чем на круг колеса).
	var due := _wheel[slot]
	_wheel_count[slot] = 0
	var cut := _now + EPS
	for i in count:
		var row := due[i]
		# Строку переложили на другой кадр, заменили или сняли: здесь её уже нет.
		if _due[row] != _frame:
			continue
		var target := _target[row]
		# Убитый ждёт уборки: стаки ему больше не тикают, их снимет clear().
		if _horde.is_dead(target):
			continue
		var next := _next_tick[row]
		if _damage[row] > 0.0 and next <= cut and next <= _expire[row] + EPS:
			# Следующий тик — ровно через интервал от этого: остаток не теряется (закон 62).
			_next_tick[row] = next + _interval[row]
			# Эффект — источник урона: вспышка тика его цвета.
			_horde.hurt(target, WeaponData.roll_crit(_damage[row], _crit_chance[row], _crit_mult[row]), _effect[row])
			if _due[row] != _frame or _horde.is_dead(target):
				continue
		if _expire[row] <= cut:
			remove(row)
		else:
			_schedule(row)


## Наложение эффекта на цель target (номер в Horde), путь один: Horde.apply_effect.
## carrier — снаряд или зона: скорость атаки и крит в момент удара. Без носителя — 1.0, 5% и ×2.
func apply(target: int, effect: StatusEffectData, carrier: Node) -> void:
	_ensure_target(target)
	var elements := Tags.element_bits(effect.tags)
	var element_stacks := _element_stacks[target + 1]
	# Реакция стихий съедает входящий эффект: стаком он уже не ложится.
	if elements != 0 and not element_stacks.is_empty():
		var reaction := Reactions.find(elements, element_stacks)
		if reaction != null:
			var incoming := _alloc()
			_fill(incoming, target, effect, -1, elements, carrier)
			reaction.react(self, target, incoming)
			_release(incoming)
			return
	var key := _key_of(effect)
	var rows := _stacks[target + 1]
	var count := 0
	var oldest := -1
	var oldest_expire := INF
	for row in rows:
		if _key[row] != key:
			continue
		var existing := _effect[row]
		if existing != effect and existing.max_stacks != effect.max_stacks:
			push_warning("stack_group %s: разные max_stacks у %s (%d) и %s (%d) — держи один лимит на всю группу" % [
				str(effect.stack_group), existing.resource_path, existing.max_stacks,
				effect.resource_path, effect.max_stacks
			])
		count += 1
		if _expire[row] < oldest_expire:
			oldest_expire = _expire[row]
			oldest = row
	if count < effect.max_stacks:
		var row := _alloc()
		_fill(row, target, effect, key, elements, carrier)
		rows.append(row)
		_count_elements(target, elements, 1)
		_horde.set_speed_mult(target, minf(_horde.get_speed_mult(target), _speed[row]))
		_schedule(row)
	elif oldest != -1:
		# Лимит набран: старейший стак заменяется свежим наложением — новые статы и полная
		# длительность. Фаза тика сохраняется: иначе частые попадания не дадут стаку тикнуть ни разу.
		var last_tick := _next_tick[oldest] - _interval[oldest]
		var was_slower := _speed[oldest] < 1.0
		_count_elements(target, _elements[oldest], -1)
		_fill(oldest, target, effect, key, elements, carrier)
		_next_tick[oldest] = last_tick + _interval[oldest]
		_count_elements(target, elements, 1)
		if was_slower:
			_update_speed(target)
		else:
			_horde.set_speed_mult(target, minf(_horde.get_speed_mult(target), _speed[oldest]))
		_schedule(oldest)
	else:
		return
	_horde.show_stack_tint(target, _effect[rows[rows.size() - 1]])


## Снимает стак с цели: строка свободна, стихии и замедление цели пересчитаны без него.
func remove(row: int) -> void:
	var target := _target[row]
	var rows := _stacks[target + 1]
	rows.remove_at(rows.find(row))
	_count_elements(target, _elements[row], -1)
	var was_slower := _speed[row] < 1.0
	_release(row)
	if was_slower:
		_update_speed(target)
	_horde.show_stack_tint(target, null if rows.is_empty() else _effect[rows[rows.size() - 1]])


## Цель уходит из игры (Horde, конец кадра её уборки): все её строки свободны,
## номер цели достанется следующему врагу чистым.
func clear(target: int) -> void:
	if target + 1 >= _stacks.size():
		return
	var rows := _stacks[target + 1]
	for row in rows:
		_release(row)
	rows.clear()
	_element_stacks[target + 1].clear()
	_horde.set_speed_mult(target, 1.0)


## Номера строк стаков цели, в порядке наложения. Снимать стак — только через remove().
func rows_of(target: int) -> PackedInt32Array:
	_ensure_target(target)
	return _stacks[target + 1]


## Сколько стаков висит на цели.
func stack_count(target: int) -> int:
	return _stacks[target + 1].size() if target + 1 < _stacks.size() else 0


## Урон реакции цели: без эффекта-источника, вспышка обычная.
func hurt(target: int, amount: float) -> void:
	_horde.hurt(target, amount)


## Вспышка на цели цветом реакции.
func flash(target: int, color: Color) -> void:
	_horde.flash(target, color)


## Сколько стак нанёс бы, если бы дотикал до конца: каждый тик со своим броском крита.
func remaining_damage(row: int) -> float:
	var damage := _damage[row]
	if damage <= 0.0:
		return 0.0
	var interval := _interval[row]
	var ticks := floori((_expire[row] - _next_tick[row] + interval) / interval + EPS)
	var total := 0.0
	for i in ticks:
		total += WeaponData.roll_crit(damage, _crit_chance[row], _crit_mult[row])
	return total


## Стихии стака битами Tags.element_bits.
func elements_of(row: int) -> int:
	return _elements[row]


func _alloc() -> int:
	if _free.is_empty():
		_grow()
	var last := _free.size() - 1
	var row := _free[last]
	_free.resize(last)
	return row


func _release(row: int) -> void:
	_due[row] = -1
	_target[row] = Horde.NOBODY
	_effect[row] = null
	_free.append(row)


func _grow() -> void:
	var old := _due.size()
	var size := maxi(old * 2, 1024)
	_target.resize(size)
	_effect.resize(size)
	_key.resize(size)
	_elements.resize(size)
	_damage.resize(size)
	_speed.resize(size)
	_interval.resize(size)
	_crit_chance.resize(size)
	_crit_mult.resize(size)
	_next_tick.resize(size)
	_expire.resize(size)
	_due.resize(size)
	# Свободные сверху вниз: первыми выдаются младшие номера.
	for row in range(size - 1, old - 1, -1):
		_due[row] = -1
		_free.append(row)


## Снимок в строку: статы эффекта и носителя в момент наложения.
## Апгрейд, взятый позже, достаётся только следующим наложениям.
func _fill(row: int, target: int, effect: StatusEffectData, key: int, elements: int, carrier: Node) -> void:
	_target[row] = target
	_effect[row] = effect
	_key[row] = key
	_elements[row] = elements
	_damage[row] = effect.get_tick_damage()
	_speed[row] = effect.get_move_speed_mult()
	_interval[row] = effect.tick_interval / (carrier.attack_speed_mult if carrier else 1.0)
	_crit_chance[row] = carrier.crit_chance if carrier else 0.05
	_crit_mult[row] = carrier.crit_mult if carrier else 2.0
	_next_tick[row] = _now + _interval[row]
	_expire[row] = _now + effect.duration


## Ключ стака: stack_group, если задан, иначе сам эффект. Одинаковый ключ — один лимит.
func _key_of(effect: StatusEffectData) -> int:
	var key: Variant = effect
	if effect.stack_group != &"":
		key = effect.stack_group
	var id: Variant = _key_ids.get(key)
	if id == null:
		id = _key_ids.size()
		_key_ids[key] = id
	return id


# Списки цели: номера врагов растут вместе с Horde, игрок — на нуле.
func _ensure_target(target: int) -> void:
	var need := target + 2
	var old := _stacks.size()
	if old >= need:
		return
	var size := maxi(need, maxi(old * 2, 256))
	_stacks.resize(size)
	_element_stacks.resize(size)
	for i in range(old, size):
		_stacks[i] = PackedInt32Array()
		_element_stacks[i] = PackedInt32Array()


func _count_elements(target: int, elements: int, change: int) -> void:
	if elements == 0:
		return
	var stacks := _element_stacks[target + 1]
	if stacks.is_empty():
		stacks.resize(Tags.ELEMENTS.size())
	for i in stacks.size():
		if elements & (1 << i):
			stacks[i] += change


## Из нескольких замедлений действует сильнейшее, они не перемножаются.
func _update_speed(target: int) -> void:
	var mult := 1.0
	for row in _stacks[target + 1]:
		mult = minf(mult, _speed[row])
	_horde.set_speed_mult(target, mult)


## Кладёт строку в колесо на кадр её ближайшего события: тик или конец стака.
func _schedule(row: int) -> void:
	var at := _expire[row]
	if _damage[row] > 0.0:
		at = minf(at, _next_tick[row])
	var frame := _frame + clampi(ceili((at - _now - EPS) / _step), 1, WHEEL - 1)
	_due[row] = frame
	var slot := frame % WHEEL
	var count := _wheel_count[slot]
	var list := _wheel[slot]
	if count == list.size():
		list.resize(maxi(count * 2, 64))
	list[count] = row
	_wheel_count[slot] = count + 1
