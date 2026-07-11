class_name TrajectoryData
extends Resource

func on_spawn(projectile:Projectile) -> void:
	pass
	
func move(projectile:Projectile, delta:float) -> void:
	push_error("TrajectoryData.move() не переопределен" + str(get_script().resource_path))
