class_name  EnemyBehaviorData
extends Resource

@export var separation_response: float = 500.0
@export var max_separation_speed: float = 150.0

func get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
		return _get_velocity(enemy, player, delta) + _get_separation(enemy)

func _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	return Vector2.ZERO

func  _get_separation(enemy: CharacterBody2D) -> Vector2:
	var push = Vector2.ZERO
	var own_mass = enemy.enemy_data.mass
	var own_radius = enemy.enemy_data.body_radius
	for i in range(enemy.nearby_enemies.size() - 1, -1, -1):
		
		var other = enemy.nearby_enemies[i]
		if not is_instance_valid(other):
			enemy.nearby_enemies.remove_at(i)
			continue
		var offset = enemy.global_position - other.global_position
		var distance = offset.length()
		var combined_radius = own_radius + other.enemy_data.body_radius
		var overlap = combined_radius - distance
		if distance > 0.0 and overlap > 0.0:
			var push_ratio = other.enemy_data.mass / (own_mass + other.enemy_data.mass)
			push += offset.normalized() * overlap * push_ratio
	var separation_velocity = push * separation_response
	return separation_velocity.limit_length(max_separation_speed)
		

func try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
	_try_attack(enemy, player, delta)
	
func  _try_attack(enemy: CharacterBody2D, player: Node2D, delta: float) -> void:
	pass
