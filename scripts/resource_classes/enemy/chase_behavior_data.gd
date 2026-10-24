class_name ChaseBehaviorData

extends  EnemyBehaviorData

func _get_velocity(horde: Horde, t: int, player_pos: Vector2, _delta: float) -> Vector2:
	var direction = (player_pos - horde.pos[t]).normalized()
	return direction * horde.speed[t]
	
