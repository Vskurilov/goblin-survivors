class_name WeaponData
extends TaggedResource

enum TargetMode{NEAREST, FARTHEST, RANDOM}


@export var weapon_name:String = ''

## fire_rate — ПЕРИОД в секундах, не частота. Идентичность оружия
## (топор тяжёлый, копьё быстрое). Апгрейды его НЕ трогают — их
## мишень attack_speed_mult ниже. (диздок §2.1, решение 07-15)
@export var fire_rate:float = 1.0

## --- Атакующие статы оружия (миграция 07-15, диздок §2.1) ---
## Тело = защита и движение; оружие = ВСЁ нападение.
## Дефолты намеренно равны прежним значениям на Actor (0.05 / 2.0 / 1.0):
## до перенабора .tres поведение игры не должно измениться.
@export var crit_chance: float = 0.05
@export var crit_mult: float = 2.0

## Множитель скорости атаки. Растёт АДДИТИВНО от 1.0 — апгрейды
## прибавляют к нему, а потребители ДЕЛЯТ период на него.
## Ноль периода структурно недостижим (закон «аддитив на убывающий
## стат запрещён», живой инцидент 07-15). Инвариант положительности
## в апгрейдах страхует и его: ≤0 сюда не проедет.
@export var attack_speed_mult: float = 1.0

## Мост для ИСТИННО ТЕЛЕСНЫХ статов, даруемых оружием
## (кинжал → +скорость бега). Ключ добавляется только парой
## с читателем в BODY_STATS_UPGRADABLE_BY_WEAPON (actor.gd).
@export var weapon_bonuses : Dictionary = {}


static func roll_crit(base_damage:float, crit_chance:float, crit_mult: float) -> float:
	if randf() < crit_chance:
		return base_damage * crit_mult
	return base_damage
## ЕДИНАЯ точка снаряжения носителя (Projectile / AoeZone) атакующими
## статами оружия. Закон §4.10 («все спавн-ветки синхронно») соблюдается
## конструктивно: новая ветка спавна обязана звать этот метод, а новый
## переносимый стат добавляется ТОЛЬКО сюда — ветки не трогаются.
## Снапшот при спавне: снаряд в полёте не получает апгрейды задним числом.
func arm_carrier(carrier:Node) -> void:
	carrier.crit_chance = crit_chance
	carrier.crit_mult = crit_mult
	carrier.attack_speed_mult = attack_speed_mult
	carrier.weapon_bonuses = weapon_bonuses

func  fire(player:Node):
	push_warning("fire не реализован для: " + weapon_name)

func pick_target(player:Node, mode:TargetMode) -> Node2D:
	var targets = pick_targets(player, mode, 1)
	if targets.size() > 0:
		return targets[0]
	else:
		return null


func pick_targets(player:Node, mode: TargetMode, count: int) -> Array[Node2D]:
	var candidates: Array = []
	match  mode:
		TargetMode.NEAREST:
			candidates =  player.get_enemies_sorted(player.nearest_criteria)
		TargetMode.FARTHEST:
			candidates =  player.get_enemies_sorted(player.fartest_criteria)
		TargetMode.RANDOM:
			candidates =  player.get_tree().get_nodes_in_group("enemies")
			candidates.shuffle()
	var actual_count = min(count, candidates.size())
	var result: Array[Node2D] = []
	for i in range(actual_count):
		result.append(candidates[i])
	return result
