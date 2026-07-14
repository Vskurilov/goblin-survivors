class_name TaggedStatUpgradeData

extends UpgradeData

enum TargetType { WEAPON_FIELD, WEAPON_EFFECT, WEAPON_BONUS}

@export_flags("Physical", "Fire", "Ice", "Poison", "Lightning") var required_tags: int = 0
@export var target: TargetType = TargetType.WEAPON_FIELD
@export var stat_name: String
@export var amount: float 
@export var is_multiplicative: bool = false

func is_available(player: Node) -> bool:
	if required_tags == 0:
		return true
	for weapon in player.weapons:
		if weapon.tags & required_tags != 0:
			return true
	return false

func apply(player:Node) -> void:
	for weapon in player.weapons:
		if required_tags != 0 and weapon.tags & required_tags == 0:
			continue
		match target:
			TargetType.WEAPON_BONUS:
				if is_multiplicative:
					push_warning("WEAPON_BONUS не поддерживает is_multiplicative(база 0.0): " + stat_name)
					continue
				var current = weapon.weapon_bonuses.get(stat_name,  0.0)
				weapon.weapon_bonuses[stat_name] = current + amount
			TargetType.WEAPON_EFFECT:
				var effect = weapon.get("on_hit_effect")
				if effect == null:
					continue
				var current = effect.get(stat_name)
				if current == null:
					push_warning("TaggedStatUpgradeData: нет поля " + stat_name + " на эффект оружия " + weapon.weapon_name)
					continue
				effect.set(stat_name, current * amount if is_multiplicative else current + amount)
			TargetType.WEAPON_FIELD:
				var current  = weapon.get(stat_name)
				if current == null:
					push_warning("TaggedStatUpgradeData: нет поля " + stat_name + "на оружии " + weapon.weapon_name)
					continue
				weapon.set(stat_name, current * amount if is_multiplicative else current + amount)
