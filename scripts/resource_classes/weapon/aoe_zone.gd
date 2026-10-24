extends Node2D

@export var damage_per_tick: float = 5.0
@export var tick_interval: float = 0.5
@export var telegraph_time: float = 0.8
@export var duration: float = 3.0
@export var radius: float = 40.0
@export var texture: Texture2D

var on_hit_effects: Array[StatusEffectData] = []
var owner_actor: Actor
var weapon_bonuses : Dictionary = {}
var crit_chance: float = 0.05
var crit_mult:float = 2.0
var attack_speed_mult:float = 1.0
## Кого бьёт зона: врагов, игрока или обоих, как у близнеца projectile.gd.
## Ставит WeaponData.arm_carrier. По умолчанию никого: забытое присваивание даёт зону,
## которая никого не бьёт, а не зону, бьющую своих.
var hits_enemies: bool = false
var hits_player: bool = false

var _horde: Horde
var _hit_shape: Horde.HitShape

## Нижняя граница периода тика: Timer.wait_time = 0 роняет таймер.
## Близнец того же предохранителя у оружия — Player.MIN_FIRE_PERIOD.
const MIN_TICK_INTERVAL: float = 0.01

func _ready() -> void:
	if texture:
		$Sprite2D.texture = texture
		var texture_radius = texture.get_width() / 2.0
		$Sprite2D.scale = Vector2.ONE * (radius / texture_radius)
	_horde = get_tree().get_first_node_in_group(&"horde") as Horde
	_hit_shape = Horde.HitShape.circle(radius)
	modulate.a = 0.3
	
	get_tree().create_timer(telegraph_time,false).timeout.connect(_activate)

func _activate() -> void:
	modulate.a = 1.0
	
	var tick_timer = Timer.new()
	tick_timer.wait_time = maxf(tick_interval / attack_speed_mult, MIN_TICK_INTERVAL)
	tick_timer.timeout.connect(_deal_tick_damage)
	add_child(tick_timer)
	tick_timer.start()
	
	get_tree().create_timer(duration,false).timeout.connect(queue_free)
	
## Все живые в круге. Позиции — снимок Horde на начало шага:
## по нему же раньше физика держала список тех, кто в зоне.
## Зону ставит игрок, а себя он не бьёт (hits_player у его зоны выключен).
func _deal_tick_damage() -> void:
	if _horde == null:
		return
	for target in _horde.query_hits(_hit_shape, global_position, hits_enemies, hits_player, Horde.NOBODY, 0):
		var final_damage = WeaponData.roll_crit(damage_per_tick, crit_chance, crit_mult)
		_horde.hurt(target, final_damage)
		for effect in on_hit_effects:
			if effect != null:
				_horde.apply_effect(target, effect, self)
