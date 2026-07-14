class_name TaggedStatUpgradeData
extends UpgradeData

## Апгрейд статов, который САМ находит свою мишень по тегу.
##
## Принцип: улучшение ложится на носителя тега. Носителей у оружия два —
## само оружие (fire_rate, damage, target_count...) и его эффект
## (damage_per_tick, duration, max_stacks...). Тег может стоять на любом из них.
##
## Куда именно ляжет стат — ВЫЧИСЛЯЕТСЯ из данных, а не указывается вручную.
## Это возможно потому, что имена статов уникальны во всём проекте: поля зоны
## называются zone_damage_per_tick / zone_duration / zone_tick_interval, а не так же,
## как одноимённые поля эффектов. Если уникальность когда-нибудь нарушат —
## apply() поймает это как ошибку, а не разъедет баланс молча (см. коллизию ниже).
##
## Если стата нет ни у одного носителя, но он есть в белом списке статов тела —
## это бонус к телу, действующий только для атак этим оружием (weapon_bonuses).
##
## Создание ресурса: проставить теги, вписать имя стата и значение. Больше ничего.

## Поля, которые апгрейд статов не имеет права трогать никогда.
## tags — битовая маска: сложение на ней не идемпотентно (8 + 8 = 16, это ДРУГОЙ тег,
## а не "Poison дважды"). Выдача тегов — задача отдельного класса апгрейда
## с побитовым ИЛИ (Этап 1.5), не этого. Рефлексия иначе пустила бы к маске
## через чёрный ход: stat_name = "tags" — валидное имя поля.
const FORBIDDEN_STATS: Array[String] = ["tags", "identity"]

@export_flags("Physical", "Fire", "Ice", "Poison", "Lightning") var required_tags: int = 0
@export var stat_name: String
@export var amount: float
@export var is_multiplicative: bool = false


## Несёт ли ресурс (оружие или эффект) требуемый тег.
## required_tags == 0 — универсальный апгрейд, подходит всем носителям.
func _carries_tag(tagged_resource: TaggedResource) -> bool:
	return required_tags == 0 or tagged_resource.tags & required_tags != 0


## Носители тега у данного оружия, у которых РЕАЛЬНО есть поле stat_name.
## Возвращает 0, 1 или 2 элемента. Два — это коллизия имён полей, её ловит apply().
## "stat_name in resource" (а не get() != null) — потому что get() не различает
## "поля нет" и "поле есть, но равно null" (проверено на 4.6).
func _find_stat_carriers(weapon: WeaponData) -> Array:
	var carriers: Array = []
	if _carries_tag(weapon) and stat_name in weapon:
		carriers.append(weapon)
	var effect: StatusEffectData = weapon.get("on_hit_effect")
	if effect != null and _carries_tag(effect) and stat_name in effect:
		carriers.append(effect)
	return carriers


## Приложится ли апгрейд к этому оружию хоть как-нибудь.
## Либо есть носитель тега с таким полем, либо это бонус к стату тела.
func _applies_to_weapon(weapon: WeaponData) -> bool:
	if not _find_stat_carriers(weapon).is_empty():
		return true
	return _carries_tag(weapon) and stat_name in Actor.BODY_STATS_UPGRADABLE_BY_WEAPON


## Апгрейд показывается на левелапе, только если ему есть куда лечь.
## Проверять один лишь тег недостаточно: тег может совпасть, а поля не быть —
## тогда игрок сжигает выбор впустую ("мёртвый выбор").
func is_available(player: Node) -> bool:
	for weapon in player.weapons:
		if _applies_to_weapon(weapon):
			return true
	return false


## Записать стат в найденного носителя (оружие или эффект — код один и тот же).
## ВНИМАНИЕ: int-поля (max_stacks, target_count, zone_count) движок усекает молча:
## 5 + 1.7 запишется как 6, а amount = 0.5 не даст вообще ничего (проверено на 4.6).
## Для int-статов задавай целый amount.
func _apply_to_carrier(carrier: Resource) -> void:
	var current = carrier.get(stat_name)
	var current_type := typeof(current)
	if current_type != TYPE_FLOAT and current_type != TYPE_INT:
		push_error("TaggedStatUpgradeData '%s': стат '%s' — не число (тип %d). Апгрейд не применён." % [
			upgrade_name, stat_name, current_type
		])
		return
	carrier.set(stat_name, current * amount if is_multiplicative else current + amount)


## Бонус к стату тела, действующий только для атак этим оружием.
## is_multiplicative здесь запрещён: словарь стартует пустым, база 0.0,
## а 0.0 * что угодно = 0.0 — умножение на пустом месте бессмысленно.
func _apply_body_bonus(weapon: WeaponData) -> void:
	if is_multiplicative:
		push_warning("TaggedStatUpgradeData '%s': WEAPON_BONUS не поддерживает is_multiplicative (база 0.0): %s" % [
			upgrade_name, stat_name
		])
		return
	var current: float = weapon.weapon_bonuses.get(stat_name, 0.0)
	weapon.weapon_bonuses[stat_name] = current + amount


func apply(player: Node) -> void:
	if stat_name in FORBIDDEN_STATS:
		push_error("TaggedStatUpgradeData '%s': стат '%s' запрещён к изменению апгрейдом статов." % [
			upgrade_name, stat_name
		])
		return

	for weapon in player.weapons:
		var carriers := _find_stat_carriers(weapon)

		# Двое носителей с одинаковым именем поля — коллизия имён в проекте.
		# Молча применить к любому = тихо сдвинуть не тот баланс. Ругаемся громко.
		if carriers.size() > 1:
			push_error("TaggedStatUpgradeData '%s': коллизия имён — стат '%s' есть И у оружия '%s', И у его эффекта. Переименуй одно из полей." % [
				upgrade_name, stat_name, weapon.weapon_name
			])
			continue

		if carriers.size() == 1:
			_apply_to_carrier(carriers[0])
			continue

		# Носителя с таким полем нет. Оружие вообще не про этот тег — молча мимо, это норма.
		if not _carries_tag(weapon):
			continue

		# Тег совпал, поля нет — либо это бонус к телу, либо опечатка в stat_name.
		if stat_name in Actor.BODY_STATS_UPGRADABLE_BY_WEAPON:
			_apply_body_bonus(weapon)
		else:
			push_warning("TaggedStatUpgradeData '%s': стат '%s' некуда положить у оружия '%s' — ни поля, ни бонуса к телу." % [
				upgrade_name, stat_name, weapon.weapon_name
			])
