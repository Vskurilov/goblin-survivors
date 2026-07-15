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
@export var on_hit_effect: StatusEffectData
@export var target_count: int = 1
@export var projectile_per_target: int = 1
@export_range(-180, 180, 0.1) var spread_angle_degrees: float = 30.0
@export var sync_spawn_delay: bool = true
@export var spawn_offset_distance: float = 0.0

func fire(player: Node) -> void:
	if player.is_dead:
		return
	if projectile_scene == null:
		push_warning("Projectile scene не зада для оружия: " + weapon_name)
	var targets = pick_targets(player, target_mode, target_count)
	if targets.is_empty():
		return
		
	var directions: Array[Vector2] = []
	for target in targets:
		var base_direction: Vector2 = (target.global_position - player.global_position).normalized()
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

func _spawn_projectile(player: Node, direction: Vector2) -> void:
	if not is_instance_valid(player) or player.is_dead:
		return
	var projectile = projectile_scene.instantiate()
	projectile.global_position = player.global_position + direction * spawn_offset_distance
	projectile.direction = direction
	projectile.damage = damage
	projectile.speed = projectile_speed
	projectile.texture = texture
	projectile.projectile_scale = projectile_scale
	projectile.collision_shape = collision_shape
	projectile.sprite_angle_offset = sprite_angle_offset
	projectile.hitbox_angle_offset = hitbox_angle_offset
	projectile.trajectory = base_trajectory
	projectile.lifetime = lifetime
	projectile.on_hit_effect = on_hit_effect
	projectile.owner_actor = player
	projectile.target_group = player.get_target_group()
	arm_carrier(projectile) 
	player.get_tree().current_scene.add_child(projectile)
