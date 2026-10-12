class_name SlowEffectData

extends StatusEffectData

## Скорость цели под замедлением: 0.6 = 60% от обычной.
## Меньше — сильнее, поэтому апгрейды только умножением (аддитивные на убывающий стат запрещены).
@export_range(0.05, 1.0, 0.05) var slow_speed_mult:float = 0.6

func get_move_speed_mult() -> float:
	return slow_speed_mult

## Урона нет: тик пустой. Без этой заглушки базовый класс ругается на каждом тике.
func apply_tick(_enemy: Node2D, _owner_actor: Actor = null, _weapon_bonuses: Dictionary = {}, _crit_chance: float = 0.05, _crit_mult: float = 2.0) -> void:
	pass
