class_name DetonationReactionData
extends ReactionData

## «Термоудар»: всё горение пары на цели, включая входящее, отдаёт оставшийся урон разом.
## Обе стихии снимаются.

## 1.0 — ровно оставшийся урон, только сейчас.
@export var damage_mult: float = 1.0

func react(table: EffectTable, target: Actor, incoming_row: int) -> void:
	var burst := table.remaining_damage(incoming_row)
	var pair := pair_bits()
	var rows := target.stack_rows
	for i in range(rows.size() - 1, -1, -1):
		var row := rows[i]
		if table.elements_of(row) & pair:
			burst += table.remaining_damage(row)
			table.remove(row)
	# Урон реакции без стихии: это не наложение эффекта, цепочек не будет.
	target.take_damage(burst * damage_mult)
	target.flash_hit(flash_color)
