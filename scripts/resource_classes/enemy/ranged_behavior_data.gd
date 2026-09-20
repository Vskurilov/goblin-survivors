class_name RangedBehaviorData

extends EnemyBehaviorData

@export var projectile_data: ProjectileWeaponData
@export var preferred_distance: float = 250.0
@export var distance_tolerance: float = 30.0

func _get_velocity(enemy: CharacterBody2D, player: Node2D, _delta: float) -> Vector2:
	var to_player = player.global_position - enemy.global_position
	var distance = to_player.length()
	var direction = to_player.normalized()
	if distance > preferred_distance + distance_tolerance:
		return direction * enemy.speed
	elif distance < preferred_distance - distance_tolerance:
		return -direction * enemy.speed
	else:
		return Vector2.ZERO
func  _try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
		if projectile_data == null:
			return
		var cooldown = enemy.behavior_state.get("attack_cooldown", 0.0) - delta
		if cooldown > 0.0:
			enemy.behavior_state["attack_cooldown"] = cooldown
			return
		enemy.behavior_state["attack_cooldown"] = projectile_data.fire_rate / projectile_data.attack_speed_mult
		var direction:= enemy.global_position.direction_to(player.global_position)
		projectile_data._spawn_projectile(enemy, direction)
