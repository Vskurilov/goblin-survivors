class_name UpgradeData

extends Resource

@export var upgrade_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

func apply(player:Node) -> void:
	push_error("UpgradeData.apply () не переопределен в " + str(get_script().resource_path))
