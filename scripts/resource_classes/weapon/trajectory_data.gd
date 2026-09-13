class_name TrajectoryData
extends Resource

func on_spawn(_projectile:Projectile) -> void:
	pass
	
func move(_projectile:Projectile, _delta:float) -> void:
	push_error("TrajectoryData.move() не переопределен" + str(get_script().resource_path))
