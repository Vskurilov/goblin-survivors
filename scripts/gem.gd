class_name Gem
extends Area2D

const ATTRACT_ACCELERATION: float = 1500.0
## Гем летит быстрее игрока
const ATTRACT_MAX_SPEED: float = 900.0
##Сверх этого числа новые гемы не появляются, их опыт складируется в один мегагем
const MAX_ON_MAP: int = 300
const OVERFLOW_SCALE: float = 1.5

##Живые гемы, общий счётчик на класс, 
##растет при создании нового объекта, падает при удалении
static var alive_count: int = 0
static var _overflow_gem: Gem = null

##Опыт за подбор. Ставит враг при выпадении из своего EnemyData.xp_reward.
var xp_value: int = 5

## Вид копилки. Ставится в gem.tscn; пусто - выглядит как обычный гем
@export var overflow_texture: Texture2D

var _target: Node2D = null
var _speed: float = 0.0

func _init() -> void:
	alive_count += 1

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		alive_count -= 1

## Единственная точка появления гема. Сверх лимита опыт идет в копилку.
static func drop(scene: PackedScene, xp: int, at: Vector2, parent: Node) -> void:
	if alive_count >= MAX_ON_MAP and _overflow_alive():
		_overflow_gem.xp_value += xp
		return
	var gem: Gem = scene.instantiate()
	gem.xp_value = xp
	gem.global_position = at
	# Лимит достигнут, но копилки нет - следующий станет ей
	if alive_count > MAX_ON_MAP:
		gem._become_overflow()
	parent.add_child.call_deferred(gem)

## Если копилку уже подобрали - опыт в нее не кладется, во избежание потери опыта
static func _overflow_alive() -> bool:
	return is_instance_valid(_overflow_gem) and not _overflow_gem.is_queued_for_deletion()
	
func _become_overflow() -> void:
	_overflow_gem = self
	# $Sprite2D доспупен до добавления в дерево: дети есть сразу после intantiate
	if overflow_texture != null:
		$Sprite2D.texture = overflow_texture
	scale = Vector2.ONE * OVERFLOW_SCALE

##Физика гема до взаимодействия не считается
func _ready() -> void:
	set_physics_process(false)

##Вызов магнита игрока. Повторный вызов не меняет цель
func attract_to(target: Node2D) -> void:
	if _target != null:
		return
	_target = target
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = null
		set_physics_process(false)
		return
	_speed = minf(_speed + ATTRACT_ACCELERATION * delta, ATTRACT_MAX_SPEED)
	global_position = global_position.move_toward(_target.global_position, _speed * delta)
