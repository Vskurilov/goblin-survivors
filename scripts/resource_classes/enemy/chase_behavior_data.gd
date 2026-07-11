class_name ChaseBehaviorData

extends  EnemyBehaviorData

func _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	var direction = (player.global_position -enemy.global_position).normalized()
	return direction * enemy.speed
	
