extends Label

## Уровень и опыт игрока. Слушает Player.xp_changed.
func  _on_player_xp_changed(level: int, current_xp: int, xp_to_next: int) -> void:
	text = "уровень: " + str(level) + " | XP: " + str(current_xp) + " | нужно до уровня: " + str(xp_to_next)
