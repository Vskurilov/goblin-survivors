class_name BurnEffectData
extends StatusEffectData

@export var damage_per_tick: float = 2.0

func apply_tick(enemy:Node2D, owner_actor: Actor = null) -> void:
	var final_damage = damage_per_tick
	if owner_actor:
		final_damage = owner_actor.roll_crit(damage_per_tick)
	enemy.take_damage(final_damage, true)
