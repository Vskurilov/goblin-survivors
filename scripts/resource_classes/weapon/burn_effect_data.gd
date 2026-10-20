class_name BurnEffectData
extends StatusEffectData

@export var damage_per_tick: float = 2.0

func get_tick_damage() -> float:
	return damage_per_tick
