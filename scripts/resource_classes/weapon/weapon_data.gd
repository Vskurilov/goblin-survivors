class_name WeaponData
extends TaggedResource

enum TargetMode{NEAREST, FARTHEST, RANDOM}

@export var weapon_name:String = ''

## Чем оружие ЯВЛЯЕТСЯ: семейство и конкретный предмет сразу.
## Выдаётся при создании и НЕ МЕНЯЕТСЯ НИКОГДА — по нему апгрейды отбирают мишень.
## Противоположность tags: те могут быть выданы по ходу забега (Этап 1.5b).
@export_custom(PROPERTY_HINT_TYPE_STRING, Tags.IDENTITY_HINT) var identity:Array[String] = []

## fire_rate — ПЕРИОД в секундах, не частота. Идентичность оружия
## (топор тяжёлый, копьё быстрое). Апгрейды его НЕ трогают — их
## мишень attack_speed_mult ниже.
@export var fire_rate:float = 1.0


## Тело = защита и движение; оружие = ВСЁ нападение.
@export var crit_chance: float = 0.05
@export var crit_mult: float = 2.0

## Множитель скорости атаки. Растёт АДДИТИВНО от 1.0 — апгрейды
## прибавляют к нему, а потребители ДЕЛЯТ период на него.
## Ноль периода структурно недостижим (закон «аддитив на убывающий
## стат запрещён»). Инвариант положительности
## в апгрейдах страхует и его: ≤0 сюда не проедет.
@export var attack_speed_mult: float = 1.0

## Мост для ИСТИННО ТЕЛЕСНЫХ статов, даруемых оружием
## (кинжал → +скорость бега). Ключ добавляется только парой
## с читателем в BODY_STATS_UPGRADABLE_BY_WEAPON (actor.gd).
@export var weapon_bonuses : Dictionary = {}
## Эффекты, которые оружие вешает при попадании.
@export var on_hit_effects: Array[StatusEffectData] = []
## Какой эффект это оружие получает от гранта стихии: Fire → свой ожог топора.
## Стихии нет в словаре — оружие получит Granted Effect самого гранта.
@export var grant_effects: Dictionary[String, StatusEffectData] = {}
## Френдли-фаер (ядро §5.2): удар бьёт и своих — снаряд врага задевает других врагов.
## Владельца не бьёт никогда. У игрока своих нет, ему флаг ничего не меняет.
@export var friendly_fire: bool = false

# Получило ли оружие грант стихии. Грант на оружие один, второй сюда не ляжет.
## Не @export: живёт только в копии оружия у игрока и в .tres не попадает.
var has_grant: bool = false
# Параметры намеренно повторяют имена полей: функция static, доступа к полям
# экземпляра нет, а зовут её носители (Projectile/AoeZone) со своего снапшота.
@warning_ignore("shadowed_variable")
static func roll_crit(base_damage:float, crit_chance:float, crit_mult: float) -> float:
	if randf() < crit_chance:
		return base_damage * crit_mult
	return base_damage
## ЕДИНАЯ точка снаряжения носителя (Projectile / AoeZone) атакующими
## статами оружия. Закон §4.10 («все спавн-ветки синхронно») соблюдается
## конструктивно: новая ветка спавна обязана звать этот метод, а новый
## переносимый стат добавляется ТОЛЬКО сюда — ветки не трогаются.
## Снапшот при спавне: снаряд в полёте не получает апгрейды задним числом.
## foes — сторона владельца: группа его целей (get_target_group(), у врага-строки
## Horde.FOES). Носитель бьёт её, а с френдли-фаером ещё и врагов.
func arm_carrier(carrier:Node, foes: StringName) -> void:
	carrier.hits_enemies = foes == &"enemies" or friendly_fire
	carrier.hits_player = foes == &"player"
	carrier.crit_chance = crit_chance
	carrier.crit_mult = crit_mult
	carrier.attack_speed_mult = attack_speed_mult
	carrier.weapon_bonuses = weapon_bonuses.duplicate()
	#Снимок списка: эффект, выданный позже, не попадёт в уже летящий снаряд
	carrier.on_hit_effects = on_hit_effects.duplicate()

## Ключ словаря набирается руками — опечатка («fire») молча не сработает.
## Поэтому громкая проверка на старте забега.
func validate_grant_effects() -> void:
	for tag in grant_effects:
		var effect: StatusEffectData = grant_effects[tag]
		if not tag in Tags.ELEMENTS:
			push_error("Оружие '%s': в grant_effects ключ '%s' не из Tags.ELEMENTS." % [weapon_name, tag])
		elif effect == null:
			push_error("Оружие '%s': в grant_effects для '%s' пустой эффект." % [weapon_name, tag])
		elif not effect.has_tag(tag):
			push_error("Оружие '%s': эффект для '%s' не несёт этот тег - апгрейды стихий до него не дойдут." % [weapon_name, tag])
func fire(_player:Node):
	push_warning("fire не реализован для: " + weapon_name)
	
## Цели оружия — их позиции. Игрок выбирает из живых врагов Horde (Horde.pick),
## у врага цель одна — игрок.
func pick_targets(shooter:Node, mode: TargetMode, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var foes: StringName = shooter.get_target_group()
	if foes == &"enemies":
		var horde := shooter.get_tree().get_first_node_in_group(&"horde") as Horde
		if horde != null:
			result = horde.pick(shooter.global_position, mode, count)
		return result
	var target := shooter.get_tree().get_first_node_in_group(foes) as Actor
	if count > 0 and target != null and not target.is_dead:
		result.append(target.global_position)
	return result
