extends CanvasLayer

## Экран конца забега. Слушает Player.run_ended; рестарт - его собственная кнопка

## Пауза - забота окна: оно её ставит, кнопка рестарта снимает.
func _on_player_run_ended(kills: int, survival_time: float, level: int) -> void:
	get_tree().paused = true
	$GameOverBox/StaticticLabel.text = "Ты завалил " + str(kills)
	visible = true

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
