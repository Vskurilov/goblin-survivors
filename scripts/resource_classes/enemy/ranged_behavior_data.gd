class_name RangedBehaviorData

extends EnemyBehaviorData

@export var projectile_data: ProjectileWeaponData
@export var preferred_distance: float = 250.0
@export var distance_tolerance: float = 30.0

func  _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
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
		enemy.behavior_state["attack_cooldown"] = projectile_data.fire_rate / enemy.attack_speed_mult
		_spawn_projectile(enemy, player)
	
func _spawn_projectile(enemy: CharacterBody2D, player: Node2D) -> void:
	if projectile_data.projectile_scene == null:
		push_warning("Projectile Scene в projectile_data не задана для дальнобойного противника: ")
		return
	var direction = (player.global_position - enemy.global_position).normalized()
	var projectile = projectile_data.projectile_scene.instantiate()
	projectile.global_position = enemy.global_position + direction * projectile_data.spawn_offset_distance
	projectile.direction = direction
	projectile.damage = projectile_data.damage
	projectile.speed = projectile_data.projectile_speed
	projectile.texture = projectile_data.texture
	projectile.projectile_scale = projectile_data.projectile_scale
	projectile.collision_shape = projectile_data.collision_shape
	projectile.sprite_angle_offset = projectile_data.sprite_angle_offset
	projectile.hitbox_angle_offset = projectile_data.hitbox_angle_offset
	projectile.trajectory = projectile_data.base_trajectory
	projectile.lifetime = projectile_data.lifetime
	projectile.on_hit_effect = projectile_data.on_hit_effect
	projectile.owner_actor = enemy
	projectile.target_group = enemy.get_target_group()
	enemy.get_tree().current_scene.add_child(projectile)
