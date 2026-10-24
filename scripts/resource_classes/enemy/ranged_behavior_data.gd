class_name RangedBehaviorData

extends EnemyBehaviorData

## Колонка строки: Horde.timer — сколько до следующего выстрела.

@export var projectile_data: ProjectileWeaponData
@export var preferred_distance: float = 250.0
@export var distance_tolerance: float = 30.0

func _get_velocity(horde: Horde, t: int, player_pos: Vector2, _delta: float) -> Vector2:
	var to_player = player_pos - horde.pos[t]
	var distance = to_player.length()
	var direction = to_player.normalized()
	if distance > preferred_distance + distance_tolerance:
		return direction * horde.speed[t]
	elif distance < preferred_distance - distance_tolerance:
		return -direction * horde.speed[t]
	else:
		return Vector2.ZERO
func  _try_attack(horde: Horde, t: int, player_pos: Vector2, delta: float) -> void:
		if projectile_data == null:
			return
		var cooldown = horde.timer[t] - delta
		if cooldown > 0.0:
			horde.timer[t] = cooldown
			return
		horde.timer[t] = projectile_data.fire_rate / projectile_data.attack_speed_mult
		var direction:= horde.pos[t].direction_to(player_pos)
		projectile_data.spawn_row_projectile(horde, t, direction)
