class_name GameCamera
extends Camera2D

## Камера игрока. Отдаление — обычное поле Zoom этой камеры в player.tscn: меньше 1 — дальше,
## в кадре больше мира. Спавнер и фон читают его сами (Spawner._spawn_radius, background.gd).
## В отладочной сборке (F5, F6) колесо мыши меняет отдаление по ступеням wheel_steps:
## так подбирается число, которое потом вписывается в Zoom.
## Пиксель-арт в мире увеличен в 3 раза, база экрана — 640×360 (настройки окна в project.godot).
## Ровные пиксели — при отдалении n/3: при 1/3 клетка рисунка — пиксель базы, при 2/3 — два.

## Ступени колеса, от ближней к дальней: в кадре 960, 1280, 1920, 2560, 3200 и 3840 px мира
## по ширине. Ровные пиксели — на 2/3 и 1/3; остальные — посмотреть на большую орду.
@export var wheel_steps: PackedFloat32Array = PackedFloat32Array([2.0 / 3.0, 0.5, 1.0 / 3.0, 0.25, 0.2, 1.0 / 6.0])
## Колесо мыши меняет отдаление. Работает только в отладочной сборке; стресс-сцена его выключает.
@export var wheel_zoom: bool = true

# Выбор колесом живёт до закрытия игры: рестарт забега его не сбрасывает. 0 — колесом не выбирали.
static var _wheel_pick := 0.0

func _ready() -> void:
	if _wheel_pick > 0.0:
		zoom = Vector2.ONE * _wheel_pick
	zoom = Vector2(_pixel_exact(zoom.x), _pixel_exact(zoom.y))

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
	_wheel_pick = _pixel_exact(_step_from(zoom.x, dir))
	zoom = Vector2.ONE * _wheel_pick
	var world := get_viewport().get_visible_rect().size / zoom
	print("[камера] отдаление %.3f, в кадре %d×%d px мира" % [_wheel_pick, roundi(world.x), roundi(world.y)])

## Ступень рядом с ближайшей к value: dir -1 — ближе, +1 — дальше, за края списка не выходит.
func _step_from(value: float, dir: int) -> float:
	var nearest := 0
	for i in wheel_steps.size():
		if absf(wheel_steps[i] - value) < absf(wheel_steps[nearest] - value):
			nearest = i
	return wheel_steps[clampi(nearest + dir, 0, wheel_steps.size() - 1)]

## Инспектор округляет Zoom до тысячных: 1/3 становится 0.333, и пиксели фона чуть расходятся.
## Число не дальше тысячной от n/3 доводится до точного n/3, остальные остаются как есть.
static func _pixel_exact(value: float) -> float:
	var thirds := roundf(value * 3.0)
	if thirds >= 1.0 and absf(value * 3.0 - thirds) <= 0.003:
		return thirds / 3.0
	return value
