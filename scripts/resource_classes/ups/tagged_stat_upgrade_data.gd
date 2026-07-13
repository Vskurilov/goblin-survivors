class_name TaggedStatUpgradeData

extends UpgradeData

@export_flags("Physical", "Fire", "Ice", "Poison", "Lightning") var required_tags: int = 0
@export var apply_to_effect: bool = false
@export var stat_name: String
@export var amount: float 
@export var is_multiplicative: bool = false

func apply(player:Node) -> void:
	for weapon in player.weapons:
		if weapon.tags & required_tags == 0:
			continue
		var target_resource = weapon
		if apply_to_effect:
			target_resource = weapon.get("on_hit_effect")
			if target_resource == null:
				continue
		var current = target_resource.get(stat_name)
		if current == null:
			push_warning("TaggedStatUpgradeData нет поля: " + stat_name + "на" + str(target_resource))
			continue
		if is_multiplicative:
			target_resource.set(stat_name, current * amount)
		else:
			target_resource.set(stat_name, current + amount)

func  is_available(player:Node) -> bool:
	if required_tags == 0:
		return true
	for weapon in player.weapons:
		if weapon.tags & required_tags != 0:
			return true
	return false
