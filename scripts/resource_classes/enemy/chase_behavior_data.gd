class_name ChaseBehaviorData

extends  EnemyBehaviorData

func _get_velocity(enemy: Enemy, player: Node2D, _delta: float) -> Vector2:
	var direction = (player.global_position -enemy.global_position).normalized()
	return direction * enemy.speed
	
