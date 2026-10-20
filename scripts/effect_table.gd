extends Node
class_name EffectTable

## Все стаки статус-эффектов всех целей, врагов и игрока (срез С3 плана орды).
## Строка таблицы — один стак: снимок чисел эффекта и носителя в момент наложения.
## У каждой строки один кадр её ближайшего события (тик или конец), и шаг физики
## трогает только строки своего кадра, а не все стаки всех целей.
## Цель хранит номера своих строк (Actor.stack_rows) и счётчики стихий: по ним реакции.

## Колесо кадров. Событие дальше этого строка ждёт по частям: таблица будит её
## раньше, видит, что ещё рано, и перекладывает дальше.
const WHEEL: int = 256
## Допуск сравнения времён: тик ровно в момент конца стака ещё случается.
const EPS: float = 0.000001

# Колонки строк: номер строки — индекс во всех сразу.
var _target: Array[Actor] = []
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

# Ячейка колеса — номера строк на кадр, у которого тот же остаток от деления на WHEEL.
var _wheel: Array[PackedInt32Array] = []
var _wheel_count := PackedInt32Array()

# Шаг физики таблицы и игровое время: на паузе стоят вместе с игрой.
var _frame: int = 0
var _now: float = 0.0
var _step: float = 1.0 / 60.0


func _enter_tree() -> void:
	add_to_group(&"effect_table")


func _ready() -> void:
	# Раньше врагов и игрока (у них 0), как Horde: тик, который убил, случился до хода врага.
	process_physics_priority = -1
	_step = 1.0 / Engine.physics_ticks_per_second
	_wheel.resize(WHEEL)
	for slot in WHEEL:
		_wheel[slot] = PackedInt32Array()
	_wheel_count.resize(WHEEL)


func _physics_process(delta: float) -> void:
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
		# Убитый ждёт удаления: стаки ему больше не тикают, их снимет clear().
		if target.is_dead:
			continue
		var next := _next_tick[row]
		if _damage[row] > 0.0 and next <= cut and next <= _expire[row] + EPS:
			# Следующий тик — ровно через интервал от этого: остаток не теряется (закон 62).
			_next_tick[row] = next + _interval[row]
			# Эффект — источник урона: вспышка тика его цвета.
			target.take_damage(WeaponData.roll_crit(_damage[row], _crit_chance[row], _crit_mult[row]), _effect[row])
			if _due[row] != _frame or target.is_dead:
				continue
		if _expire[row] <= cut:
			remove(row)
		else:
			_schedule(row)


## Наложение эффекта на цель, путь один: Actor.apply_status_effect.
## carrier — снаряд или зона: скорость атаки и крит в момент удара. Без носителя — 1.0, 5% и ×2.
func apply(target: Actor, effect: StatusEffectData, carrier: Node) -> void:
	var elements := Tags.element_bits(effect.tags)
	# Реакция стихий съедает входящий эффект: стаком он уже не ложится.
	if elements != 0 and not target.element_stacks.is_empty():
		var reaction := Reactions.find(elements, target.element_stacks)
		if reaction != null:
			var incoming := _alloc()
			_fill(incoming, target, effect, -1, elements, carrier)
			reaction.react(self, target, incoming)
			_release(incoming)
			return
	var key := _key_of(effect)
	var rows := target.stack_rows
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
		target.status_speed_mult = minf(target.status_speed_mult, _speed[row])
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
			target.status_speed_mult = minf(target.status_speed_mult, _speed[oldest])
		_schedule(oldest)
	else:
		return
	target.show_stack_tint(_effect[rows[rows.size() - 1]])


## Снимает стак с цели: строка свободна, стихии и замедление цели пересчитаны без него.
func remove(row: int) -> void:
	var target := _target[row]
	var rows := target.stack_rows
	rows.remove_at(rows.find(row))
	_count_elements(target, _elements[row], -1)
	var was_slower := _speed[row] < 1.0
	_release(row)
	if was_slower:
		_update_speed(target)
	target.show_stack_tint(null if rows.is_empty() else _effect[rows[rows.size() - 1]])


## Цель уходит из игры (Enemy._exit_tree): все её строки свободны.
func clear(target: Actor) -> void:
	for row in target.stack_rows:
		_release(row)
	target.stack_rows.clear()
	target.element_stacks.clear()
	target.status_speed_mult = 1.0


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
	_target[row] = null
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
func _fill(row: int, target: Actor, effect: StatusEffectData, key: int, elements: int, carrier: Node) -> void:
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


func _count_elements(target: Actor, elements: int, change: int) -> void:
	if elements == 0:
		return
	var stacks := target.element_stacks
	if stacks.is_empty():
		stacks.resize(Tags.ELEMENTS.size())
	for i in stacks.size():
		if elements & (1 << i):
			stacks[i] += change


## Из нескольких замедлений действует сильнейшее, они не перемножаются.
func _update_speed(target: Actor) -> void:
	var mult := 1.0
	for row in target.stack_rows:
		mult = minf(mult, _speed[row])
	target.status_speed_mult = mult


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
