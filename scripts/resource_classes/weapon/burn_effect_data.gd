class_name BurnEffectData
extends StatusEffectData

@export var damage_per_tick: float = 2.0

func apply_tick(enemy:Node2D, owner_actor: Actor = null, weapon_bonuses: Dictionary = {}, crit_chance: float = 0.05, crit_mult: float = 2.0) -> void:
	var final_damage = WeaponData.roll_crit(damage_per_tick, crit_chance, crit_mult)
	enemy.take_damage(final_damage, true)
