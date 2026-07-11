class_name StatUpgradeData
extends UpgradeData

@export var stat_name: String
@export var amount: float
@export var is_multiplicative: bool = false

func apply(player:Node) -> void:
	var current = player.get(stat_name)
	if is_multiplicative:
		player.set(stat_name, current * amount)
	else:
		player.set(stat_name, current + amount)
	
