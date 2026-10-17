extends ProgressBar

## Полоска здоровья игрока. Слушает Player.health_changed; сам player о ней не знает

# Ссылка берётся при первом сигнале, а не в @onready: игрок стоит в дереве раньше
# HUD и шлёт первый сигнал из своего _ready, когда @onready поля ещё null (закон 45).
var _label: Label
# Что сейчас написано: контактный урон шлёт сигнал каждый шаг физики,
# а текст меняется, только когда меняется целое число.
var _shown_current: int = -1
var _shown_maximum: int = -1

func _on_player_health_changed(current: float, maximum: float) -> void:
	#сначала максимум:value клампится по max_value
	max_value = maximum
	value = current
	var whole_current := int(current)
	var whole_maximum := int(maximum)
	if whole_current == _shown_current and whole_maximum == _shown_maximum:
		return
	_shown_current = whole_current
	_shown_maximum = whole_maximum
	if _label == null:
		_label = $Label
	_label.text = str(whole_current) + "/" + str(whole_maximum)
