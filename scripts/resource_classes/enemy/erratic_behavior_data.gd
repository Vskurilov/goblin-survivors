class_name  ErraticBehaviorData

extends  EnemyBehaviorData

## Колонки строки: Horde.timer — сколько до смены направления, Horde.angle — отклонение.

@export var direction_charge_interval: float = 0.5
@export var wander_angle_range_degrees: float = 90.0
@export_range(0.0,1.0, 0.01) var wander_strength: float = 0.6

func _get_velocity(horde: Horde, t: int, player_pos: Vector2, delta: float) -> Vector2:
	var wander_timer = horde.timer[t] - delta
	if wander_timer <= 0.0:
		wander_timer = direction_charge_interval
		var random_angle_degrees = randf_range(-wander_angle_range_degrees, wander_angle_range_degrees)
		horde.angle[t] = deg_to_rad(random_angle_degrees)
	horde.timer[t] = wander_timer
	var wander_offset_angle = horde.angle[t]
	var direction_to_player = (player_pos - horde.pos[t]).normalized()
	var wandering_direction = direction_to_player.rotated(wander_offset_angle)
	var final_direction = direction_to_player.lerp(wandering_direction, wander_strength).normalized()
	return final_direction * horde.speed[t]
