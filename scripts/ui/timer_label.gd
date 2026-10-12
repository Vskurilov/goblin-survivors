extends Label

##Таймер времени забега. Слушает Player.survival_time
func  _on_player_survival_time_changed(seconds: float) -> void:
	text = "мочишь гоблинов уже " + Player.format_time(seconds)
