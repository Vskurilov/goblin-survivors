class_name WaveTrajectoryData

extends TrajectoryData

## Волна поперёк полёта. Полёт ведёт Shots (ядро или Shots._fly) по числам ниже:
## при выстреле они ложатся в колонки снаряда.
@export var amplitude: float = 40.0
@export var frequency: float = 6.0
@export_range (0.0, 1.0) var phase_jitter: float = 0.0

func get_move() -> Move:
	return Move.WAVE

func on_spawn(shots: Shots, shot: int) -> void:
	super.on_spawn(shots, shot)
	shots.wave_amplitude[shot] = amplitude
	shots.wave_frequency[shot] = frequency
	shots.wave_phase[shot] = randf() * TAU * phase_jitter
