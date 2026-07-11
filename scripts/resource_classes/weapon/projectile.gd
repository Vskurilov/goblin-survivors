class_name Projectile
extends Area2D

@export var speed: float = 400
@export var damage: float = 1.0
@export var texture: Texture2D
@export var projectile_scale: float = 1.0
@export var collision_shape: Shape2D
@export var lifetime: float = 5.0
@export_range(-180, 180, 0.1, "radians_as_degrees") var sprite_angle_offset: float = 0.0
@export_range(-180, 180, 0.1, "radians_as_degrees") var hitbox_angle_offset: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var trajectory: TrajectoryData
var travel_time: float = 0.0
var wave_phase_offset: float = 0.0
var age: float = 0.0
var on_hit_effect: StatusEffectData
var owner_actor: Actor
var target_group: StringName = &""

func _ready() -> void:
	if texture:
		$Sprite2D.texture = texture	
	if collision_shape:
		$CollisionShape2D.shape = collision_shape
	elif texture:
		var auto_shape := RectangleShape2D.new()
		auto_shape.size = texture.get_size() * $Sprite2D.scale
		$CollisionShape2D.shape = auto_shape
	scale = Vector2.ONE * projectile_scale
	rotation = direction.angle() + sprite_angle_offset
	$CollisionShape2D.rotation = hitbox_angle_offset
	trajectory.on_spawn(self)
	
func _physics_process(delta):
	trajectory.move(self, delta)
	if lifetime > 0.0:
		age = age + delta
		if age >= lifetime:
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == owner_actor:
		return
	if not body.is_in_group(target_group):
		return
	var final_damage = damage
	if is_instance_valid(owner_actor):
		final_damage = owner_actor.roll_crit(damage)
	body.take_damage(final_damage)
	if on_hit_effect:
		var interval_mult = owner_actor.attack_speed_mult if is_instance_valid(owner_actor) else 1.0
		
		body.apply_status_effect(on_hit_effect, owner_actor if is_instance_valid(owner_actor) else null, 1.0 / interval_mult)
	queue_free()
