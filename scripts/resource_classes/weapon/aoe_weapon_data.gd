class_name AoeWeaponData

extends  WeaponData

@export var aoe_scene: PackedScene
@export var zone_damage_per_tick:float = 1.0
@export var zone_tick_interval:float = 2.0
@export var telegraph_time:float = 0.8
@export var zone_duration:float = 5.0
@export var radius:float = 40.0
@export var target_mode:TargetMode = TargetMode.RANDOM
@export var texture:Texture2D
@export var on_hit_effect:StatusEffectData
@export var zone_count: int = 1

func  fire(player:Node) -> void:
	if player.is_dead:
		return
	var targets = pick_targets(player, target_mode, zone_count)
	if targets.is_empty():
		return
	for target in targets:
		var aoe:Node2D = aoe_scene.instantiate()
		aoe.global_position = target.global_position
		aoe.owner_actor = player
		aoe.damage_per_tick = zone_damage_per_tick
		aoe.tick_interval = zone_tick_interval
		aoe.telegraph_time = telegraph_time
		aoe.duration = zone_duration
		aoe.radius = radius
		aoe.texture = texture
		aoe.on_hit_effect = on_hit_effect
		arm_carrier(aoe) 
		player.get_tree().current_scene.add_child(aoe)
