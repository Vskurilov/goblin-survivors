extends Node2D
class_name Gems

## Гемы опыта (срез С7 плана орды). Гем — строка в массивах, а не узел: в кадре
## смерти выпадение не создаёт узлов, а все гемы рисуются одним MultiMesh.
## Магнит и подбор — по расстоянию до игрока, без Area2D.
## Ход гема тот же, что был с физикой. Касание ищется в конце шага, после скриптов,
## как его искал шаг физики; подбор и магнит срабатывают в начале следующего шага,
## раньше всех узлов, как раньше приходили сигналы area_entered.
## Вид гема задаёт его сцена (EnemyData.gem_scene), в игру она не попадает.
## Узел стоит в начале координат: позиции гемов — мировые.

## Сверх этого числа новые гемы не появляются: их опыт копится в одном геме-копилке.
const MAX_ON_MAP: int = 300
const ATTRACT_ACCELERATION: float = 1500.0
## Гем летит быстрее игрока.
const ATTRACT_MAX_SPEED: float = 900.0

# Что нашёл конец прошлого шага.
const FOUND_NONE: int = 0
const FOUND_MAGNET: int = 1
const FOUND_PICKUP: int = 2

# Обычные гемы: строка i — экземпляр i в MultiMesh.
var _pos := PackedVector2Array()
var _xp := PackedInt32Array()
# Скорость полёта к игроку. Меньше нуля — магнит гем ещё не взял.
# float64, как было поле гема: иначе путь гема разойдётся с прежним.
var _speed := PackedFloat64Array()
var _found := PackedByteArray()

# Копилка: не больше одной, свои поля и свой спрайт.
var _bank_on: bool = false
var _bank_pos := Vector2.ZERO
var _bank_xp: int = 0
var _bank_speed: float = -1.0
var _bank_found: int = FOUND_NONE

# Подобраны в начале этого шага. Раньше такой гем удалялся в конце шага и до тех пор
# считался в лимите MAX_ON_MAP: выпавшее в этом шаге видит лимит так же.
var _picked_now: int = 0

var _player: Player
# Вид: сцена гема, радиус гема и копилки.
var _look: PackedScene
var _other_look_warned: bool = false
var _radius: float = 10.0
var _bank_radius: float = 15.0
var _multimesh: MultiMesh
# Экземпляры MultiMesh одним буфером: 8 чисел на гем, в отрисовку уходит одним вызовом.
var _buffer := PackedFloat32Array()
var _upload_queued: bool = false
var _bank_sprite: Sprite2D


func _enter_tree() -> void:
	add_to_group(&"gems")


func _ready() -> void:
	# Позже всех узлов: гемы летят за уже сдвинутым игроком, касание — по итогу шага.
	process_physics_priority = 1000
	_player = get_tree().get_first_node_in_group(&"player") as Player
	# Раньше всех узлов шага: так приходили сигналы областей игрока.
	get_tree().physics_frame.connect(_apply_found)


## Гем с опытом xp в точке at. Сверх MAX_ON_MAP опыт уходит в копилку.
func drop(scene: PackedScene, xp: int, at: Vector2) -> void:
	if not _ensure_look(scene):
		return
	var alive := _pos.size() + int(_bank_on) + _picked_now
	if alive >= MAX_ON_MAP and _bank_on:
		_bank_xp += xp
		return
	# Лимит набран, но копилки нет — этот гем станет ей.
	if alive + 1 > MAX_ON_MAP:
		_bank_on = true
		_bank_pos = at
		_bank_xp = xp
		_bank_speed = -1.0
		_bank_found = FOUND_NONE
		_bank_sprite.position = at
		_bank_sprite.visible = true
		return
	var i := _pos.size()
	_pos.append(at)
	_xp.append(xp)
	_speed.append(-1.0)
	_found.append(FOUND_NONE)
	_buffer[i * 8 + 3] = at.x
	_buffer[i * 8 + 7] = at.y
	_queue_upload()


## Гемов на карте, с копилкой.
func count() -> int:
	return _pos.size() + int(_bank_on)


## Опыт в гемах на карте, с копилкой.
func xp_on_map() -> int:
	var total := _bank_xp if _bank_on else 0
	for xp in _xp:
		total += xp
	return total


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var target := _player.global_position
	_fly(target, delta)
	_find(target)


## Гемы, которые взял магнит, летят к игроку: разгон до предела, как раньше в Gem.
func _fly(target: Vector2, delta: float) -> void:
	var pos := _pos
	var speed := _speed
	var buffer := _buffer
	var moved := false
	for i in pos.size():
		var s: float = speed[i]
		if s < 0.0:
			continue
		s = minf(s + ATTRACT_ACCELERATION * delta, ATTRACT_MAX_SPEED)
		speed[i] = s
		var p: Vector2 = pos[i].move_toward(target, s * delta)
		pos[i] = p
		buffer[i * 8 + 3] = p.x
		buffer[i * 8 + 7] = p.y
		moved = true
	if moved:
		_queue_upload()
	if _bank_on and _bank_speed >= 0.0:
		_bank_speed = minf(_bank_speed + ATTRACT_ACCELERATION * delta, ATTRACT_MAX_SPEED)
		_bank_pos = _bank_pos.move_toward(target, _bank_speed * delta)
		_bank_sprite.position = _bank_pos


## Касание с кругами игрока по итогу шага: круг подбора и круг магнита плюс радиус гема.
## Срабатывает в начале следующего шага (_apply_found).
func _find(target: Vector2) -> void:
	var pick := _player.pickup_radius + _radius
	var pick2 := pick * pick
	var pull := _player.magnet_radius + _radius
	var pull2 := pull * pull
	var pos := _pos
	var speed := _speed
	var found := _found
	for i in pos.size():
		var d2 := target.distance_squared_to(pos[i])
		if d2 < pick2:
			found[i] = FOUND_PICKUP
		elif d2 < pull2 and speed[i] < 0.0:
			found[i] = FOUND_MAGNET
	if _bank_on:
		var d2 := target.distance_squared_to(_bank_pos)
		var bank_pick := _player.pickup_radius + _bank_radius
		var bank_pull := _player.magnet_radius + _bank_radius
		if d2 < bank_pick * bank_pick:
			_bank_found = FOUND_PICKUP
		elif d2 < bank_pull * bank_pull and _bank_speed < 0.0:
			_bank_found = FOUND_MAGNET


## Начало шага: подбор и магнит по тому, что нашёл конец прошлого шага. На паузе шага
## физики не было бы, и находки ждут снятия паузы, как ждала физика.
## Окно уровня ставит паузу посреди цикла, а подбор идёт дальше: сигналы одного шага
## физики тоже приходили все (закон 63).
func _apply_found() -> void:
	if get_tree().paused or not is_instance_valid(_player):
		return
	var picked := false
	# С конца: удалённую строку занимает последняя, а она уже пройдена.
	for i in range(_pos.size() - 1, -1, -1):
		var f: int = _found[i]
		if f == FOUND_NONE:
			continue
		_found[i] = FOUND_NONE
		if f == FOUND_MAGNET:
			_speed[i] = 0.0
			continue
		var xp: int = _xp[i]
		_remove_row(i)
		_picked_now += 1
		picked = true
		_player.gain_xp(xp)
	if _bank_on and _bank_found != FOUND_NONE:
		var f := _bank_found
		_bank_found = FOUND_NONE
		if f == FOUND_MAGNET:
			_bank_speed = 0.0
		else:
			_bank_on = false
			_bank_sprite.visible = false
			_picked_now += 1
			picked = true
			_player.gain_xp(_bank_xp)
	if picked:
		# Конец этого шага, где раньше удалялся узел гема. Отложенный вызов
		# доходит и на паузе от окна уровня.
		_forget_picked.call_deferred()


func _forget_picked() -> void:
	_picked_now = 0


## Строку i занимает последняя: номера остальных не сдвигаются.
func _remove_row(i: int) -> void:
	var last := _pos.size() - 1
	if i != last:
		_pos[i] = _pos[last]
		_xp[i] = _xp[last]
		_speed[i] = _speed[last]
		_found[i] = _found[last]
		_buffer[i * 8 + 3] = _buffer[last * 8 + 3]
		_buffer[i * 8 + 7] = _buffer[last * 8 + 7]
	_pos.resize(last)
	_xp.resize(last)
	_speed.resize(last)
	_found.resize(last)
	_queue_upload()


## Буфер уходит в отрисовку в конце кадра, один раз, и на паузе тоже: подобранный
## перед окном уровня гем не висит под окном, как раньше не висел удалённый узел.
func _queue_upload() -> void:
	if not _upload_queued:
		_upload_queued = true
		_upload.call_deferred()


func _upload() -> void:
	_upload_queued = false
	var rid := _multimesh.get_rid()
	RenderingServer.multimesh_set_buffer(rid, _buffer)
	RenderingServer.multimesh_set_visible_instances(rid, _pos.size())


## Вид гема читается из его сцены один раз, при первом выпадении. Все враги роняют
## одну сцену; вторую этот узел не рисует, о ней предупреждение.
func _ensure_look(scene: PackedScene) -> bool:
	if scene == _look:
		return true
	if _look != null:
		if not _other_look_warned:
			_other_look_warned = true
			push_warning("Gems: второй вид гема (%s) не поддержан, рисую как %s." % [scene.resource_path, _look.resource_path])
		return true
	var gem := scene.instantiate() as Gem
	if gem == null:
		push_error("Gems: корень сцены %s — не Gem." % scene.resource_path)
		return false
	_look = scene
	var sprite := gem.get_node("Sprite2D") as Sprite2D
	var size := sprite.texture.get_size() * sprite.scale
	_radius = gem.radius
	_bank_radius = gem.radius * gem.overflow_scale
	# Высота квада со знаком минус: QuadMesh в 2D иначе рисует картинку вверх ногами.
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, -size.y)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = quad
	# Своя рамка на весь мир. Рамку MultiMesh для отсечения за экраном Godot берёт один раз
	# и потом не обновляет: без своей гемы пропадали, когда камера уходила от первых гемов.
	# Гемов не больше 300, рисовать их всегда дешевле, чем пересчитывать рамку.
	_multimesh.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0), Vector3(2.0e6, 2.0e6, 2.0))
	_multimesh.instance_count = MAX_ON_MAP
	_multimesh.visible_instance_count = 0
	# Поворота и масштаба у гема нет: базис единичный, меняется только позиция.
	_buffer.resize(MAX_ON_MAP * 8)
	for i in MAX_ON_MAP:
		_buffer[i * 8] = 1.0
		_buffer[i * 8 + 5] = 1.0
	var view := MultiMeshInstance2D.new()
	view.multimesh = _multimesh
	view.texture = sprite.texture
	add_child(view)
	_bank_sprite = Sprite2D.new()
	_bank_sprite.texture = gem.overflow_texture if gem.overflow_texture != null else sprite.texture
	_bank_sprite.scale = sprite.scale * gem.overflow_scale
	_bank_sprite.visible = false
	add_child(_bank_sprite)
	gem.free()
	return true
