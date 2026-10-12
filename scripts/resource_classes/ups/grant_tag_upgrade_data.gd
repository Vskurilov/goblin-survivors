class_name GrantTagUpgradeData
extends FilteredUpgradeData

## Выдаёт оружию стихийные теги. Только самому оружию: эффект держит свой тег.
## identity не трогает никогда. Повторная выдача ничего не дублирует.

@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var granted_tags: Array[String] = []

## Оружие прошло фильтр, и ему не хватает хотя бы одного выдаваемого тега.
func _can_receive(weapon: WeaponData) -> bool:
	if not _matches_identity(weapon) or not _carries_tag(weapon):
		return false
	for tag in granted_tags:
		if not weapon.has_tag(tag):
			return true
	return false

## Показываем, только если кому-то есть что добавить — иначе мёртвый выбор.
func is_available(player: Node) -> bool:
	for weapon in player.weapons:
		if _can_receive(weapon):
			return true
	return false

func apply(player: Node) -> void:
	if granted_tags.is_empty():
		push_error("GrantTagUpgradeData '%s': granted_tags пуст. Апгрейд не применён." % upgrade_name)
		return
	for weapon in player.weapons:
		if not _can_receive(weapon):
			continue
		for tag in granted_tags:
			if not weapon.has_tag(tag):
				weapon.tags.append(tag)
