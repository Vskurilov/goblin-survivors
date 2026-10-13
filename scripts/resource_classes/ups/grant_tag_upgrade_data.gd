class_name GrantTagUpgradeData
extends FilteredUpgradeData

## Грант стихии: ОДНОМУ оружию выдаёт теги и свой эффект. identity не трогает никогда.
## Оружие выбирается при показе карточки (make_offer) и называется на ней.
## У оружия не больше одного гранта: получившее выпадает из кандидатов.

@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var granted_tags: Array[String] = []
## Эффект стихии, который грант добавляет оружию (холод → мороз). Пусто — только тег.
@export var granted_effect: StatusEffectData

## Оружие прошло фильтр, и ему не хватает хотя бы одного выдаваемого тега.
func _can_receive(weapon: WeaponData) -> bool:
	if weapon.has_grant:
		return false
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

## Грант всегда на одно оружие: карточка выбирает его из тех, кто может принять.
func make_offer(player: Node) -> UpgradeData: 
	var candidates: Array[WeaponData] = []
	for weapon in player.weapons:
		if _can_receive(weapon):
			candidates.append(weapon)
	return _offer_for_one_of(candidates)

## Эффект стихии для этого оружия: свой из его grant_effects, иначе общий granted_effect.
func _effect_for(weapon: WeaponData) -> SlowEffectData:
	for tag in granted_tags:
		if weapon.grant_effects.has(tag):
			return weapon.grant_effects[tag]
	return granted_effect

func apply(_player: Node) -> void:
	if granted_tags.is_empty():
		push_error("GrantTagUpgradeData '%s': granted_tags пуст. Апгрейд не применён." % upgrade_name)
		return
	if target_weapon == null:
		push_error("GrantTagUpgradeData '%s': оружие не выбрано - грант пришёл мимо make_offer(). Апгрейд не примёнен" % upgrade_name)
		return
	for tag in granted_tags:
		if not target_weapon.has_tag(tag):
			target_weapon.tags.append(tag)
	# Своя копия эффекта: её прокачка не заденет тот же эффект на другом оружии.
	var effect := _effect_for(target_weapon)
	if effect != null:
		target_weapon.on_hit_effects.append(effect.duplicate())
	target_weapon.has_grant = true
	
