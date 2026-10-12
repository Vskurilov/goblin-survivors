class_name Gem
extends Area2D

const ATTRACT_ACCELERATION: float = 1500.0
## Гем летит быстрее игрока
const ATTRACT_MAX_SPEED: float = 900.0

##Опыт за подбор. Ставит враг при выпадении из своего EnemyData.xp_reward.
var xp_value: int = 5

var _target: Node2D = null
var _speed: float = 0.0

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
