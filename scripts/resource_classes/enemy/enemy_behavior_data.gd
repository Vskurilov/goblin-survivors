class_name EnemyBehaviorData
extends Resource

## Поведение типа врага. Враг — строка Horde (срез С4): поведение получает Horde и номер
## строки t, читает и пишет колонки строки (Horde.pos, Horde.speed, Horde.state, Horde.timer,
## Horde.angle, Horde.aim). Своя память поведения — только в этих колонках, по номеру t.
## Horde зовёт get_velocity и try_attack в ходе строки, по порядку появления врагов.

## Расталкивание считает Horde по этим числам, они читаются при появлении врага.
## Сила толчка на пиксель перекрытия с соседом.
@export var separation_response: float = 500.0
## Предел скорости расталкивания. Horde не даёт ему быть ниже скорости врага
## × Horde.push_to_speed, иначе враг продавит толпу и сожмёт её в точку.
@export var max_separation_speed: float = 150.0

## Собственный ход врага. Толчок соседей прибавляет Horde.
## Замедление режет собственный ход врага (бег, рывок), но не расталкивание:
## замёрзшего толкают соседи с обычной силой.
## player_pos — позиция игрока: в цикле хода врагов игрок стоит на месте.
func get_velocity(horde: Horde, t: int, player_pos: Vector2, delta: float) -> Vector2:
		return _get_velocity(horde, t, player_pos, delta) * horde.speed_mult[t]

func _get_velocity(_horde: Horde, _t: int, _player_pos: Vector2, _delta: float) -> Vector2:
	return Vector2.ZERO

## Атака после хода: враг уже на новой позиции.
func try_attack(horde: Horde, t: int, player_pos: Vector2, delta: float) -> void:
	_try_attack(horde, t, player_pos, delta)
	
func _try_attack(_horde: Horde, _t: int, _player_pos: Vector2, _delta: float) -> void:
	pass
