extends Label

## Счетчик убийств. Слушает Player.kill_changed
func _on_player_kills_changed(kills: int) -> void:
	text = "убито: " + str(kills)
