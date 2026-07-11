class_name  EnemyBehaviorData
extends Resource

func get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
		return _get_velocity(enemy, player, delta)

func _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	return Vector2.ZERO

func try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
	_try_attack(enemy, player, delta)
	
func  _try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
	pass
	
	
