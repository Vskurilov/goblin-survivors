class_name ProjectileWeaponData
extends WeaponData

@export var projectile_scene: PackedScene
@export var damage: float = 1.0
@export var lifetime: float = 10.0
@export var projectile_speed: float = 400
@export var texture: Texture2D
@export var projectile_scale: float = 1.0
@export var collision_shape: Shape2D
@export_range(-180, 180, 0.1, "radians_as_degrees") var sprite_angle_offset: float = 0.0
@export_range(-180, 180, 0.1, "radians_as_degrees") var hitbox_angle_offset: float = 0.0
@export var target_mode: TargetMode = TargetMode.NEAREST
@export var base_trajectory: TrajectoryData
@export_range(0.0, 1, 0.01) var spawn_delay_max: float = 0.0
@export var target_count: int = 1
## Сколько врагов снаряд бьёт в момент первого касания: ближайших к своему центру.
## 0 — без предела, как было до шага 1.
@export_range(0, 100,1, "or_greater") var hit_limit: int = 0
@export var projectile_per_target: int = 1
@export_range(-180, 180, 0.1) var spread_angle_degrees: float = 30.0
@export var sync_spawn_delay: bool = true
@export var spawn_offset_distance: float = 0.0

func fire(player: Node) -> void:
	if player.is_dead:
		return
	if projectile_scene == null:
		push_warning("Projectile scene не задана для оружия: " + weapon_name)
		return
	var targets = pick_targets(player, target_mode, target_count)
	if targets.is_empty():
		return
		
	var directions: Array[Vector2] = []
	for target in targets:
		var base_direction: Vector2 = (target - player.global_position).normalized()
		for i in range(projectile_per_target):
			var angle_offset_degrees = 0.0
			if projectile_per_target > 1:
				var step = spread_angle_degrees / (projectile_per_target - 1)
				angle_offset_degrees = -spread_angle_degrees / 2.0 + i * step
			directions.append(base_direction.rotated(deg_to_rad(angle_offset_degrees)))
		
	var shared_delay = randf_range(0.0, spawn_delay_max)
	for final_direction in directions:
		var delay = shared_delay if sync_spawn_delay else randf_range(0.0, spawn_delay_max)
		if delay <= 0.0:
			_spawn_projectile(player, final_direction)
		else:
			player.get_tree().create_timer(delay, false).timeout.connect(_spawn_projectile.bind(player, final_direction))
## Выстрел узла (игрока): снаряд летит из его позиции и бьёт его цели.
func spawn_projectile(shooter: Actor, direction: Vector2) -> void:
	_assemble(shooter, shooter.global_position, direction, shooter.get_target_group(), shooter, Horde.NOBODY, 0)

## Выстрел врага — строки t в Horde: снаряд летит из её позиции и бьёт игрока.
## Номер стрелка снаряд хранит вместе с его generation: свой выстрел его не заденет.
func spawn_row_projectile(horde: Horde, t: int, direction: Vector2) -> void:
	_assemble(horde, horde.pos[t], direction, Horde.FOES, null, t, horde.generation(t))

## Единственное место сборки снаряда — и для игрока, и для врагов. Снаряд — строка Shots
## (срез С5): числа оружия (скорость, жизнь, фигура, вид, траектория) Shots.fire берёт
## сам, атакующие статы — снимком в заряд. Новое поле снаряда добавляется в Shots.fire.
func _assemble(from: Node, at: Vector2, direction: Vector2, foes: StringName,
		owner_actor: Actor, owner_row: int, owner_gen: int) -> void:
	if projectile_scene == null:
		push_warning("projectile_scene не задана: " + (weapon_name if not weapon_name.is_empty() else resource_path))
		return
	var shots := from.get_tree().get_first_node_in_group(&"shots") as Shots
	if shots == null:
		push_warning("В сцене нет узла Shots: снаряд %s не выпущен." % (weapon_name if not weapon_name.is_empty() else resource_path))
		return
	var charge := Shots.Charge.new()
	charge.damage = damage
	arm_carrier(charge, foes)
	shots.fire(self, at + direction * spawn_offset_distance, direction, charge, owner_actor, owner_row, owner_gen)
	
## Обёртка для отложенного выстрела: за время задержки игрок мог умереть или исчезнуть.
func _spawn_projectile(player: Node, direction: Vector2) -> void:
	if not is_instance_valid(player) or player.is_dead:
		return
	spawn_projectile(player, direction)
		
