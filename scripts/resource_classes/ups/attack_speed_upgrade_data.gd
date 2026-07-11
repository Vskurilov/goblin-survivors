class_name AttackSpeedUpgradeData
extends UpgradeData

@export var amount: float = 0.15

func apply(player:Node) -> void:
	player.attack_speed_mult += amount
