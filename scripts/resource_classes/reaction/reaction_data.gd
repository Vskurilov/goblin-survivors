class_name ReactionData
extends Resource

## Реакция стихий: две стихии пары встретились на одной цели.
## Ищет её Reactions.find() из EffectTable.apply — единственного пути наложения эффекта.

# Номера стихий пары в Tags.ELEMENTS: считаются один раз, когда пара задана.
# Объявлены раньше пары: её сеттер пишет сюда.
var _pair := PackedInt32Array()

## Две разные стихии, порядок не важен.
@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var elements: Array[String] = []:
	set(value):
		elements = value
		_pair.clear()
		for element in value:
			_pair.append(Tags.ELEMENTS.find(element))
## Цвет вспышки реакции на цели.
@export var flash_color: Color = Color(0.85,0.6, 1.0)

## Входящий эффект несёт одну стихию пары, а на цели висит стак другой.
## incoming — стихии входящего битами, target_stacks — счётчики стаков цели по стихиям.
func matches(incoming: int, target_stacks: PackedInt32Array) -> bool:
	# Кривую пару громко ловит Reactions.validate() на старте, здесь просто мимо.
	if _pair.size() != 2 or _pair[0] < 0 or _pair[1] < 0 or target_stacks.is_empty():
		return false
	for i in 2:
		if incoming & (1 << _pair[i]) and target_stacks[_pair[1 - i]] > 0:
			return true
	return false

## Стихии пары битами Tags.element_bits: стак с любой из них реакция снимает.
func pair_bits() -> int:
	return Tags.element_bits(elements)

## Что делает реакция. incoming_row — строка входящего эффекта в таблице: снимок есть,
## но на цель она не ложится и после реакции освобождается.
func react(_table: EffectTable, _target: Actor, _incoming_row: int) -> void:
	push_error("ReactionData.react() не переопределен в " + str(get_script().resource_path))
