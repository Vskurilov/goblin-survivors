class_name Tags

## ИСТОЧНИК ИСТИНЫ для обоих наборов имён.
## Порядок НЕ ЗНАЧИТ НИЧЕГО: в .tres хранятся строки, а не биты. Добавляй,
## переставляй, сортируй свободно. Удалённое имя не переосмыслится в соседнее —
## оно останется в ресурсе и будет поймано валидатором.
const ELEMENTS: Array[String] = ["Physical", "Fire", "Ice", "Poison", "Lightning",]

const IDENTITIES: Array[String] = ["Melee", "Thrown", "Zone", "Beam", "Martial", "Magic", "Axe", "Javelin", "FireRing", "FlameThrower",]

## Подсказка инспектора: "<TYPE_STRING>/<PROPERTY_HINT_ENUM>:имена" — даёт
## выпадающий список на каждый элемент массива, поэтому имя не набирается руками.
## Собрать её из массива нельзя: аннотация требует КОНСТАНТНОЕ выражение,
## а ",".join() — вызов метода (проверено 4.6). Отсюда двойная запись списка —
## зато на соседних строках, и рассинхрон ловит hints_match().

const ELEMENT_HINT := "4/2:Physical,Fire,Ice,Poison,Lightning"
const IDENTITY_HINT := "4/2:Melee,Thrown,Zone,Beam,Martial,Magic,Axe,Javelin,FireRing,FlameThrower"

## Совпадают ли подсказки со своими массивами. Зовётся из стартового валидатора.
static func hints_match() -> bool:
	return ELEMENT_HINT == "4/2:" + ",".join(ELEMENTS) \
	 and IDENTITY_HINT == "4/2:" + ",".join(IDENTITIES)
