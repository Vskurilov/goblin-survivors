class_name WaveTrajectoryData

extends TrajectoryData

@export var amplitude: float = 40.0
@export var frequency: float = 6.0
@export_range (0.0, 1.0) var phase_jitter: float = 0.0

func on_spawn(projectile: Projectile) -> void:
	super.on_spawn(projectile)
	projectile.wave_phase_offset = randf() * TAU * phase_jitter

func move(projectile: Projectile, delta: float) -> void:
	projectile.travel_time = projectile.travel_time + delta
	var forward: Vector2 = projectile.direction * projectile.speed 
	var perpendicular: Vector2 = projectile.direction.rotated(PI/2)
	var phase: float = projectile.travel_time * frequency + projectile.wave_phase_offset
	var lateral_displacement_rate: Vector2 = perpendicular * amplitude * frequency * cos(phase)
	projectile.global_position += (forward + lateral_displacement_rate) * delta
