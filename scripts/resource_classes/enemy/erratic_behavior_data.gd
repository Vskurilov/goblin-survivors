class_name  ErraticBehaviorData

extends  EnemyBehaviorData

@export var direction_charge_interval: float = 0.5
@export var wander_angle_range_degrees: float = 90.0
@export_range(0.0,1.0, 0.01) var wander_strength: float = 0.6

func _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	var wander_timer= enemy.behavior_state.get("wander_timer", 0.0) - delta
	if wander_timer <= 0.0:
		wander_timer = direction_charge_interval
		var random_angle_degrees = randf_range(-wander_angle_range_degrees, wander_angle_range_degrees)
		enemy.behavior_state["wander_offset_angle"] = deg_to_rad(random_angle_degrees)
	enemy.behavior_state["wander_timer"] = wander_timer	
	var wander_offset_angle = enemy.behavior_state.get("wander_offset_angle", 0.0)
	var direction_to_player = (player.global_position - enemy.global_position).normalized()
	var wandering_direction = direction_to_player.rotated(wander_offset_angle)
	var final_direction = direction_to_player.lerp(wandering_direction, wander_strength).normalized()
	return final_direction * enemy.speed
