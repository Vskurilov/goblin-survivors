class_name Projectile
extends Node2D

## Удар по одной цели — её номеру в Horde (враг или Horde.PLAYER). Идёт до урона:
## подписчик видит цель такой, какой её застал снаряд.
signal hit(target: int)

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
## Владелец-узел (игрок). У выстрела врага узла нет: его номер в Horde и generation.
var owner_actor: Actor
var owner_row: int = Horde.NOBODY
var owner_gen: int = 0
## Кого бьёт снаряд: врагов, игрока или обоих (френдли-фаер). Владельца не бьёт никогда.
## Ставит WeaponData.arm_carrier. По умолчанию никого: забытое присваивание даёт снаряд,
## который никого не бьёт, а не снаряд, бьющий своих.
var hits_enemies: bool = false
var hits_player: bool = false
var weapon_bonuses : Dictionary = {}
var crit_chance: float = 0.05
var crit_mult: float = 2.0
var attack_speed_mult:float = 1.0
## Сколько целей снаряд бьёт в момент первого касания. 0 — без предела.
var hit_limit: int = 0

var _horde: Horde
# Фигура удара в мире: поворот и масштаб снаряда задаются при появлении и дальше не меняются.
var _hit_shape: Horde.HitShape


func _ready() -> void:
	if texture:
		$Sprite2D.texture = texture
	scale = Vector2.ONE * projectile_scale
	rotation = direction.angle() + sprite_angle_offset
	_horde = get_tree().get_first_node_in_group(&"horde") as Horde
	_hit_shape = Horde.HitShape.from_shape(_pick_shape(), Transform2D(rotation + hitbox_angle_offset, scale, 0.0, Vector2.ZERO))
	trajectory.on_spawn(self)

func _physics_process(delta):
	if _hit():
		return
	trajectory.move(self, delta)
	if lifetime > 0.0:
		age = age + delta
		if age >= lifetime:
			queue_free()

## Фигура удара: своя у оружия; без неё — прямоугольник по картинке;
## без картинки — круг радиусом 10, как фигура по умолчанию в прежней сцене снаряда.
func _pick_shape() -> Shape2D:
	if collision_shape:
		return collision_shape
	if texture:
		var auto_shape := RectangleShape2D.new()
		auto_shape.size = texture.get_size() * $Sprite2D.scale
		return auto_shape
	return CircleShape2D.new()

## Бьёт живых, кого снаряд касается: не больше hit_limit, ближайших к своему центру.
## Цели — снимок Horde на начало шага: по тем же позициям раньше физика сообщала о касаниях.
## Никого — снаряд летит дальше. true — удар нанесён, снаряд удаляется.
func _hit() -> bool:
	if _horde == null:
		return false
	# Враг-стрелок своим снарядом себя не бьёт, пока он тот же (френдли-фаер).
	var exclude := owner_row if _horde.is_same(owner_row, owner_gen) else Horde.NOBODY
	var targets := _horde.query_hits(_hit_shape, global_position, hits_enemies, hits_player, exclude, hit_limit)
	if targets.is_empty():
		return false
	for target in targets:
		hit.emit(target)
		var final_damage = WeaponData.roll_crit(damage, crit_chance, crit_mult)
		_horde.hurt(target, final_damage)
		for effect in on_hit_effects:
			if effect != null:
				_horde.apply_effect(target, effect, self)
	queue_free()
	return true
