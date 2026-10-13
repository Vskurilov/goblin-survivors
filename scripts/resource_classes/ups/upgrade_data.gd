class_name UpgradeData

extends Resource

@export var upgrade_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

func apply(_player:Node) -> void:
	push_error("UpgradeData.apply () не переопределен в " + str(get_script().resource_path))

func is_available(_player:Node) -> bool:
	return true

## Что показать на карточке левелапа. Обычный апгрейд показывает себя.
## Грант переопределяет: выбирает оружие и называет его на карточке.
func make_offer(_player: Node) -> UpgradeData:
	return self

## Сколько карточек даёт эта запись пула. Обычно одну.
## Бафф с one_weapon переопределяет: по карточке на каждое подходящее оружие.
func make_offers(player: Node) -> Array[UpgradeData]:
	var offers: Array[UpgradeData] = [make_offer(player)]
	return offers
