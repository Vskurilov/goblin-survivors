class_name DashBehaviorData

extends  EnemyBehaviorData

## Колонки строки: Horde.state — фаза (STATE_*), Horde.timer — сколько осталось фазе,
## Horde.aim — направление рывка.

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


func _get_velocity(horde: Horde, t: int, player_pos: Vector2, delta: float) -> Vector2:
	var state = horde.state[t]
	match state:
		STATE_APPROACH:
			return _approach(horde, t, player_pos)
		STATE_CHARGE:
			return _charge(horde, t, player_pos, delta)
		STATE_DASH:
			return _dash(horde, t, delta)
		STATE_RECOVER:
			return _recover(horde, t, player_pos, delta)
	return Vector2.ZERO

func  _approach(horde: Horde, t: int, player_pos: Vector2) -> Vector2:
	var direction = (player_pos - horde.pos[t]).normalized()
	var distance = horde.pos[t].distance_to(player_pos)
	if distance <= trigger_distance:
		horde.state[t] = STATE_CHARGE
		horde.timer[t] = charge_time
	return direction * horde.speed[t]
	
func _charge(horde: Horde, t: int, player_pos: Vector2, delta:float) -> Vector2:
	var dash_timer = horde.timer[t] - delta
	if dash_timer <= 0.0:
		horde.state[t] = STATE_DASH
		horde.timer[t] = dash_duration
		horde.aim[t] = (player_pos - horde.pos[t]).normalized()
	else:
		horde.timer[t] = dash_timer
	return Vector2.ZERO

func  _dash(horde: Horde, t: int, delta: float) -> Vector2:
	var dash_timer = horde.timer[t] - delta
	if dash_timer <= 0:
		horde.state[t] = STATE_RECOVER
		horde.timer[t] = recovery_time
	else:
		horde.timer[t] = dash_timer
	var dash_direction = horde.aim[t]
	return dash_direction * dash_speed

func _recover(horde: Horde, t: int, player_pos: Vector2, delta: float) -> Vector2:
	var dash_timer = horde.timer[t] - delta
	if dash_timer <= 0.0:
		horde.state[t] = STATE_APPROACH
	else:
		horde.timer[t] = dash_timer
	var direction = (player_pos - horde.pos[t]).normalized()
	return direction * horde.speed[t] * recovery_speed_mult
