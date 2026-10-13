class_name DetonationReactionData
extends ReactionData

## «Термоудар»: всё горение пары на цели, включая входящее, отдаёт оставшийся урон разом.
## Обе стихии снимаются.

## 1.0 — ровно оставшийся урон, только сейчас.
@export var damage_mult: float = 1.0

func react(target: Actor, incoming_entry: Dictionary) -> void:
	var burst := _remaining_damage(incoming_entry)
	for i in range(target.active_effects.size() - 1, -1, -1):
		var entry: Dictionary = target.active_effects[i]
		if _is_pair_element(entry["effect"]):
			burst += _remaining_damage(entry)
			target.active_effects.remove_at(i)
	# Урон реакции без стихии: это не наложение эффекта, цепочек не будет.
	target.take_damage(burst * damage_mult)
	target.flash_hit(flash_color)

## Сколько стак нанёс бы, если бы дотикал до конца.
func _remaining_damage(entry: Dictionary) -> float:
	var ticks := floori((entry["time_since_tick"] + entry["time_left"]) / entry["tick_interval"])
	return entry["effect"].damage_over_ticks(ticks, entry["crit_chance"], entry["crit_mult"])
