class_name DashBehaviorData

extends  EnemyBehaviorData

const STATE_APPROACH:= 0
const STATE_CHARGE:= 1
const STATE_DASH:= 2
const STATE_RECOVER:= 3

@export var trigger_distance: float = 300.0
@export var charge_time: float = 0.8
@export var dash_speed: float = 700.0
@export var dash_duration: float = 0.35
@export var recovery_time: float = 1.0
@export_range(0.0, 1.0, 0.01) var recovery_speed_mult:float = 0.3


func _get_velocity(enemy: CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	var state = enemy.behavior_state.get("dash_state", STATE_APPROACH)
	match state:
		STATE_APPROACH:
			return _approach(enemy, player)
		STATE_CHARGE:
			return _charge(enemy, player, delta)
		STATE_DASH:
			return _dash(enemy,delta)
		STATE_RECOVER:
			return _recover(enemy, player, delta)
	return Vector2.ZERO

func  _approach(enemy:CharacterBody2D, player:Node2D) -> Vector2:
	var direction = (player.global_position - enemy.global_position).normalized()
	var distance = enemy.global_position.distance_to(player.global_position)
	if distance <= trigger_distance:
		enemy.behavior_state["dash_state"] = STATE_CHARGE
		enemy.behavior_state["dash_timer"] = charge_time
	return direction * enemy.speed
	
func _charge(enemy:CharacterBody2D, player:Node2D, delta:float) -> Vector2:
	var dash_timer = enemy.behavior_state.get("dash_timer", 0.0) - delta
	if dash_timer <= 0.0:
		enemy.behavior_state["dash_state"] = STATE_DASH
		enemy.behavior_state["dash_timer"] = dash_duration
		enemy.behavior_state["dash_direction"] = (player.global_position - enemy.global_position).normalized()
	else:
		enemy.behavior_state["dash_timer"] = dash_timer
	return Vector2.ZERO

func  _dash(enemy:CharacterBody2D, delta: float) -> Vector2:
	var dash_timer = enemy.behavior_state.get("dash_timer", 0.0) - delta
	if dash_timer <= 0:
		enemy.behavior_state["dash_state"] = STATE_RECOVER
		enemy.behavior_state["dash_timer"] = recovery_time
	else:
		enemy.behavior_state["dash_timer"] = dash_timer
	var dash_direction = enemy.behavior_state.get("dash_direction", Vector2.ZERO)
	return dash_direction * dash_speed

func _recover(enemy:CharacterBody2D, player: Node2D, delta: float) -> Vector2:
	var dash_timer = enemy.behavior_state.get("dash_timer", 0.0) - delta
	if dash_timer <= 0.0:
		enemy.behavior_state["dash_state"] = STATE_APPROACH
	else:
		enemy.behavior_state["dash_timer"] = dash_timer
	var direction = (player.global_position - enemy.global_position).normalized()
	return direction * enemy.speed * recovery_speed_mult
