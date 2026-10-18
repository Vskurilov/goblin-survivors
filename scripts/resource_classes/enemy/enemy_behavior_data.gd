class_name EnemyBehaviorData
extends Resource

## Расталкивание считает Horde по этим числам, они читаются при появлении врага.
## Сила толчка на пиксель перекрытия с соседом.
@export var separation_response: float = 500.0
## Предел скорости расталкивания. Horde не даёт ему быть ниже скорости врага
## × Horde.push_to_speed, иначе враг продавит толпу и сожмёт её в точку.
@export var max_separation_speed: float = 150.0

## Собственный ход врага. Толчок соседей прибавляет Enemy из Horde.sep_vel.
## Замедление режет собственный ход врага (бег, рывок), но не расталкивание:
## замёрзшего толкают соседи с обычной силой.
func get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
		return _get_velocity(enemy, player, delta) * enemy.get_status_speed_mult()

func _get_velocity(_enemy: CharacterBody2D, _player: Node2D, _delta: float) -> Vector2:
	return Vector2.ZERO

func try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
	_try_attack(enemy, player, delta)
	
func _try_attack(_enemy: CharacterBody2D, _player: Node2D, _delta: float) -> void:
	pass
