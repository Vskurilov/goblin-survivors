class_name Projectile
extends Area2D

## Удар по одной цели. Идёт до урона: подписчик видит цель такой, какой её застал снаряд.
signal hit(target: Actor)

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
var on_hit_effects: Array[StatusEffectData] = []
var owner_actor: Actor
var target_group: StringName = &""
var weapon_bonuses : Dictionary = {}
var crit_chance: float = 0.05
var crit_mult: float = 2.0
var attack_speed_mult:float = 1.0
## Сколько целей снаряд бьёт в момент первого касания. 0 — без предела.
var hit_limit: int = 0

# Кого снаряд коснулся за шаг физики. Все касания шага приходят
# до _physics_process, поэтому там список полный.
var _touched: Array[Actor] = []
# Удар нанесён: снаряд больше не летит и не бьёт, ждёт удаления.
var _spent: bool = false


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
	if _spent: 
		return
	if not _touched.is_empty():
		_hit_touched()
		if _spent:
			return
	trajectory.move(self, delta)
	if lifetime > 0.0:
		age = age + delta
		if age >= lifetime:
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	if _spent or body == owner_actor:
		return
	if body == owner_actor:
		return
	_touched.append(body as Actor)
	
## Бьёт живых из коснувшихся: не больше hit_limit, ближайших к центру снаряда.
## Живых нет (всех уже убили в этом шаге) — снаряд не тратится и летит дальше.
func _hit_touched() -> void:
	var targets: Array[Actor] = []
	for body in _touched:
		if is_instance_valid(body) and not body.is_dead:
			targets.append(body)
	_touched.clear()
	if targets.is_empty():
		return
	_spent = true
	if hit_limit > 0 and targets.size() > hit_limit:
		var center := global_position
		targets.sort_custom(func(a: Actor, b: Actor) -> bool:
			return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
		targets.resize(hit_limit)
	var effect_owner: Actor = owner_actor if is_instance_valid(owner_actor) else null
	for target in targets:
		hit.emit(target)
		var final_damage = WeaponData.roll_crit(damage, crit_chance, crit_mult)
		target.take_damage(final_damage)
		for effect in on_hit_effects:
			if effect != null:
				target.apply_status_effect(effect, effect_owner, self)
		queue_free()
