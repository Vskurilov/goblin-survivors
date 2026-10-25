class_name GameCamera
extends Camera2D

## Камера игрока. Отдаление — обычное поле Zoom этой камеры в player.tscn: меньше 1 — дальше,
## в кадре больше мира. Спавнер и фон читают его сами (Spawner._spawn_radius, background.gd).
## В отладочной сборке (F5, F6) колесо мыши меняет отдаление по ступеням wheel_steps:
## так подбирается число, которое потом вписывается в Zoom.

## Ступени колеса, от ближней к дальней. 2/3 при пиксельном масштабе ×3 даёт ровно ×2 на экране.
@export var wheel_steps: PackedFloat32Array = PackedFloat32Array([1.0, 0.75, 2.0 / 3.0, 0.5, 0.4, 0.3])
## Колесо мыши меняет отдаление. Работает только в отладочной сборке; стресс-сцена его выключает.
@export var wheel_zoom: bool = true

# Выбор колесом живёт до закрытия игры: рестарт забега его не сбрасывает. 0 — колесом не выбирали.
static var _wheel_pick := 0.0

func _ready() -> void:
	if _wheel_pick > 0.0:
		zoom = Vector2.ONE * _wheel_pick

## Колесо от себя — ближе, на себя — дальше, по ступени за щелчок.
func _unhandled_input(event: InputEvent) -> void:
	if not wheel_zoom or not OS.is_debug_build() or wheel_steps.is_empty():
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var dir := 0
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		dir = -1
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dir = 1
	else:
		return
	get_viewport().set_input_as_handled()
	_wheel_pick = _step_from(zoom.x, dir)
	zoom = Vector2.ONE * _wheel_pick
	print("[камера] отдаление %.3f" % _wheel_pick)

## Ступень рядом с ближайшей к value: dir -1 — ближе, +1 — дальше, за края списка не выходит.
func _step_from(value: float, dir: int) -> float:
	var nearest := 0
	for i in wheel_steps.size():
		if absf(wheel_steps[i] - value) < absf(wheel_steps[nearest] - value):
			nearest = i
	return wheel_steps[clampi(nearest + dir, 0, wheel_steps.size() - 1)]
