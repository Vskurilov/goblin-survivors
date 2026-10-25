class_name StraightTrajectoryData

extends TrajectoryData

## Прямо: за шаг direction × speed × delta. Полёт ведёт Shots (ядро или Shots._fly).
func get_move() -> Move:
	return Move.STRAIGHT
