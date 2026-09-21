class_name  FilteredUpgradeData
extends UpgradeData

##Общий фильр апгрейда: по чему отбирается мишень
## Между required_tags и required_identity действует И, внутри каждого - ИЛИ
## Пустое поле - фильтра нет. Наследники: апгрейд статов и выдача тегов.

@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.ELEMENT_HINT) var required_tags: Array[String] = []
##Чем оружие ЯВЛЯЕТСЯ. Фильтр УРОВНЯ ОРУЖИЯ: эффект своего identity не несёт
## и отсекается вместе со своим оружие
@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.IDENTITY_HINT) var required_identity: Array[String] = []

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
		
