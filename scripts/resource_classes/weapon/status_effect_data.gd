class_name StatusEffectData
extends TaggedResource

@export var duration:float= 3.0
@export var tick_interval:float = 0.5
@export var max_stacks:int = 1
@export var stack_group: StringName = &"" 

## Цвет подсветки носителя, пока эффект весит, и вспышки его тика.
## По умолчанию зеленый
@export var tint_color: Color = Color(0.3, 1.0, 0.3)

##Во сколько раз эффект меняет скорость движения носителя, при 1.0 - не меняет
## Переопределяет эффекты - модификаторы(замедление); урон по тикам его не трогает
func get_move_speed_mult() -> float:
	return 1.0

## Урон одного тика до крита. 0 — эффект не тикает (замедление).
## EffectTable снимает его в строку стака при наложении и дальше тикает сама.
func get_tick_damage() -> float:
	return 0.0
	
