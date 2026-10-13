class_name Reactions

## Все реакции игры. Новая пара — ресурс в resources/reactions и строка в ALL.
const ALL: Array[ReactionData] = [
	preload("res://resources/reactions/thermal_shock.tres")
]

## Реакция, которую запустит входящий эффект на цели с такими стаками, или null.
static func find(incoming: StatusEffectData, entries: Array) -> ReactionData:
	for reaction in ALL:
		if reaction.matches(incoming, entries):
			return reaction
	return null

## Громкая проверка на старте: в паре две разные стихии из Tags, пары не повторяются.
static func validate() -> void:
	var seen := {}
	for reaction in ALL:
		var pair := reaction.elements.duplicate()
		pair.sort()
		if pair.size() != 2 or pair[0] == pair[1]:
			push_error("Reactions: у '%s' не две разные стихии: %s." % [reaction.resource_path, reaction.elements])
			continue
		for element in pair:
			if not element in Tags.ELEMENTS:
				push_error("Reactions: у '%s' стихия не из '%s' не из Tags.ELEMENS." % [reaction.resource_path, reaction.elements])
		var key := "+".join(pair)
		if seen.has(key):
			push_error("Reaction: пара %s задана дважды: '%s' и '%s'." % [key, seen[key], reaction.resource_path])
		seen[key] = reaction.resource_path
