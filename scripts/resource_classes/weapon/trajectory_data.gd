class_name TrajectoryData
extends Resource

## Траектория снаряда. Снаряд — строка Shots (срез С5): обычные режимы ведёт сам Shots,
## ядром на C++ или своим GDScript, по числам, которые траектория кладёт в колонки
## снаряда при выстреле (on_spawn). Новый режим — номер сюда, функция в ядре
## (native/src/shots_core.cpp) и такая же в Shots._fly.
## SCRIPT — особый снаряд со своим движением: Shots зовёт его move() каждый шаг, в черёд
## снаряда. Годится для единиц, а не тысяч. На позиции других снарядов в этом шаге
## не опираться: обычные снаряды ядро двигает после.
enum Move { STRAIGHT, WAVE, SCRIPT }

## Режим полёта снаряда.
func get_move() -> Move:
	return Move.SCRIPT

## Выстрел: снаряд shot уже в Shots, его колонки заполнены. Числа и память траектории
## кладутся в колонки снаряда по номеру shot (Shots.wave_phase, Shots.travel_time…).
func on_spawn(_shots: Shots, _shot: int) -> void:
	pass

## Шаг снаряда в режиме SCRIPT: сдвинуть Shots.pos[shot]. Возраст и конец жизни ведёт Shots.
func move(_shots: Shots, _shot: int, _delta: float) -> void:
	push_error("TrajectoryData.move() не переопределен" + str(get_script().resource_path))
