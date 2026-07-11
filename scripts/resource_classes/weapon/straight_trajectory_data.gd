class_name StraightTrajectoryData

extends TrajectoryData

func move(projectile: Projectile, delta: float) -> void:
	projectile.global_position += projectile.direction * projectile.speed * delta
