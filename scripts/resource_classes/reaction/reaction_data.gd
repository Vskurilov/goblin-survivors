class_name ReactionData
extends Resource

## Реакция стихий: две стихии пары встретились на одной цели.
## Ищет её Reactions.find() из Actor.apply_status_effect — единственной точки наложения эффекта.

## Две разные стихии, порядок не важен.
@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var elements: Array[String] = []
## Цвет вспышки реакции на цели.
@export var flash_color: Color = Color(0.85,0.6, 1.0)

## Входящий эффект несёт одну стихию пары, а на цели висит стак другой.
func matches(incoming: StatusEffectData, entries: Array) -> bool:
	# Кривую пару громко ловит Reactions.validate() на старте, здесь просто мимо.
	if elements.size() != 2:
		return false
	for i in 2:
		if incoming.has_tag(elements[i]):
			var other: String = elements[1 - i]
			for entry in entries:
				if entry["effect"].has_tag(other):
					return true
	return false

## Стак несёт одну из стихий пары.
func _is_pair_element(effect: StatusEffectData) -> bool:
	return effect.has_tag(elements[0]) or effect.has_tag(elements[1])

## Что делает реакция. incoming_entry — запись входящего эффекта, на цель она не ложится.
func react(_target: Actor, _incoming_entry: Dictionary) -> void:
	push_error("ReactionData.react() не переопределен в " + str(get_script().resource_path))
