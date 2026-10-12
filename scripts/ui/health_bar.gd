extends ProgressBar

## Полоска здоровья игрока. Слушает Player.health_changed; сам player о ней не знает

## $Label, а не @onready: игрок стоит в дереве раньше HUD и шлет первый сигнал
## из своего _ready - еще когда @onready поля имеют значения null
func _on_player_health_changed(current: float, maximum: float) -> void:
	#сначала максимум:value клампится по max_value
	max_value = maximum
	value = current
	$Label.text = str(int(current)) + "/" + str(int(maximum))
