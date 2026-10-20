class_name Actor
extends Node2D


## Статы тела, которые оружие может усилить через weapon_bonuses.
## Пуст до появления улучшений тела(кинжал -> скорость бега)
## ВНИМАНИЕ: ключ попадает сюда ТОЛЬКО парой с читателем этого ключа.
const BODY_STATS_UPGRADABLE_BY_WEAPON: Array[String] = []

@onready var sprite: Sprite2D = $Sprite2D

@export var hit_flash_duration:float = 0.12
@export var hit_flash_color: Color = Color(1, 0.3, 0.3)

var is_dead:bool = false
## Скорость последнего шага физики: её пишут игрок и враг. Физического тела нет,
## это просто число (раньше было свойством CharacterBody2D).
var velocity: Vector2 = Vector2.ZERO
var current_health:float = 0.0
var _hit_flash_time_left:float = 0.0
var damage_taken_mult: float = 1.0
var _flash_color:Color = Color.WHITE
## Оттенок ждёт шага цели: идёт вспышка удара или сменился последний стак.
## Враг и игрок зовут _update_tint в шаге физики, только пока флаг поднят.
var _tint_pending: bool = false

## Стаки статус-эффектов этой цели — номера строк в EffectTable, в порядке наложения.
## Ведёт их таблица, цель только хранит.
var stack_rows := PackedInt32Array()
## Сколько стаков каждой стихии висит на цели, номер — в Tags.ELEMENTS. По ним реакции.
var element_stacks := PackedInt32Array()
## Множитель скорости от эффектов: из нескольких замедлений действует сильнейшее,
## они не перемножаются. При 1.0 скорость не меняется. Пишет EffectTable.
var status_speed_mult: float = 1.0
# Эффект последнего наложенного стака, пока он висит: его цвет — оттенок цели.
var _stack_effect: StatusEffectData
var _shown_tint := Color.WHITE
var _effects: EffectTable

func get_target_group() -> StringName:
	return &""

func flash_hit(color: Color = hit_flash_color) -> void:
	_hit_flash_time_left = hit_flash_duration
	_flash_color = color
	_tint_pending = true

## Последний наложенный стак сменился. Зовёт EffectTable, null — стаков не осталось.
func show_stack_tint(effect: StatusEffectData) -> void:
	if effect != _stack_effect:
		_stack_effect = effect
		_tint_pending = true

## Оттенок спрайта в шаге цели: вспышка удара, пока от неё что-то осталось в начале шага,
## иначе цвет последнего наложенного стака, иначе без оттенка. Зовётся только после
## события (удар, смена стаков) и до конца вспышки, а не каждый шаг. Убитый до своего
## шага не доходит, и оттенок ему не пишется.
func _update_tint(delta: float) -> void:
	# Белый с альфой 1.0 — без оттенка.
	var tint := Color.WHITE
	if _hit_flash_time_left > 0.0:
		# Флаг не снимаем: в следующем шаге вспышку надо погасить.
		_hit_flash_time_left -= delta
		tint = _make_tint(_flash_color, 1.0)
	else:
		_tint_pending = false
		if _stack_effect != null:
			tint = _make_tint(_stack_effect.tint_color, 0.6)
	# Пишем только при смене: незачем звать сервер отрисовки каждый шаг вспышки.
	if tint != _shown_tint:
		_shown_tint = tint
		sprite.self_modulate = tint

## Оттенок для шейдера одним цветом, его несёт self_modulate спрайта: rgb — цвет,
## альфа — сила (1.0 — без оттенка, 0.5 — полный). Материал тогда у всех врагов
## общий, и их спрайты склеиваются в один вызов отрисовки.
static func _make_tint(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, 1.0 - amount * 0.5)

## Единственная точка наложения эффекта. Стаки, тики и реакции ведёт EffectTable.
## Кто наложил, таблица пока не хранит: тику он не нужен.
func apply_status_effect(effect: StatusEffectData, _owner_actor: Actor = null, carrier: Node = null) -> void:
	# На убитого не ложатся ни стаки, ни реакции: он только ждёт удаления.
	if is_dead:
		return
	if _effects == null:
		_effects = get_tree().get_first_node_in_group(&"effect_table") as EffectTable
		if _effects == null:
			push_warning("В сцене нет узла EffectTable: эффект %s не наложен." % effect.resource_path)
			return
	_effects.apply(self, effect, carrier)

## Цель уходит из игры: её стаки снимаются, иначе таблица позовёт удалённый узел.
func _clear_status_effects() -> void:
	if not stack_rows.is_empty() and is_instance_valid(_effects):
		_effects.clear(self)

## ЕДИНСТВЕННЫЙ путь урона для обеих сущностей: прямое попадание, тик зоны
## и тик статус-эффекта приходят сюда. Поэтому сторож is_dead стоит один раз
## на всех: queue_free() отложен до конца кадра, и узел продолжает принимать
## удары, поставленные в очередь в этом же кадре.
## source_effect — эффект, чей тик нанёс урон: вспышка его цветом. Прямой удар — null.
func take_damage(amount:float, source_effect: StatusEffectData = null) -> void:
	if is_dead:
		return
	flash_hit(source_effect.tint_color if source_effect != null else hit_flash_color)
	current_health = maxf(current_health - amount * damage_taken_mult, 0.0)
	_on_health_changed()
	if current_health <= 0.0:
		is_dead = true
		_die()


## Реакция вида на изменение здоровья. У врага вида нет — заглушка пуста.
func _on_health_changed() -> void:
	pass

## Смерть — событие, а не состояние здоровья. Флаг поднимается в take_damage
## ДО вызова: сигналы синхронны, и подписчик увидит уже мёртвого актора.
func _die() -> void:
	pass
