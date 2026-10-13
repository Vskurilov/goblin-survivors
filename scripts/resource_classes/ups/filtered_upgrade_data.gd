class_name FilteredUpgradeData
extends UpgradeData

##Общий фильтр апгрейда: по чему отбирается мишень
## Между required_tags и required_identity действует И, внутри каждого - ИЛИ
## Пустое поле - фильтра нет. Наследники: апгрейд статов и выдача тегов.

@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var required_tags: Array[String] = []
##Чем оружие ЯВЛЯЕТСЯ. Фильтр УРОВНЯ ОРУЖИЯ: эффект своего identity не несёт
## и отсекается вместе со своим оружием
@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.IDENTITY_HINT) var required_identity: Array[String] = []

## Оружие с карточки. Заполняет _offer_for_one_of() у копии апгрейда, в .tres всегда пусто.
var target_weapon: WeaponData

##Несет ли ресурс(оружие или эффект) требуемый тег.
func _carries_tag(tagged_resource: TaggedResource) -> bool:
	if required_tags.is_empty():
		return true
	for tag in required_tags:
		if tagged_resource.has_tag(tag):
			return true
	return false

## Подходит ли оружие под фильтр identity. Пустой фильтр подходит любому.
func _matches_identity(weapon: WeaponData) -> bool:
	if required_identity.is_empty():
		return true
	for identity_name in weapon.identity:
		if identity_name in required_identity:
			return true
	return false
	
## Грант: одна карточка, оружие случайное — шанс не растёт от числа оружия.
func _offer_for_one_of(candidates: Array[WeaponData]) -> UpgradeData:
	if candidates.is_empty():
		push_error("'%s': некому выдать, а карточка уже показана." % upgrade_name)
		return self
	return _offer_for(candidates.pick_random())

## Копия апгрейда для карточки с этим оружием в названии.
## Оригинал лежит в пуле и не должен помнить выбранное оружие.
func _offer_for(weapon: WeaponData) -> UpgradeData:
	var offer: FilteredUpgradeData = duplicate()
	offer.target_weapon = weapon
	offer.upgrade_name = "%s → %s" % [upgrade_name, weapon.weapon_name]
	return offer
