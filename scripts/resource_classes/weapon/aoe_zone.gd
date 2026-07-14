extends Area2D

@export var damage_per_tick: float = 5.0
@export var tick_interval: float = 0.5
@export var telegraph_time: float = 0.8
@export var duration: float = 3.0
@export var radius: float = 40.0
@export var texture: Texture2D

var on_hit_effect: StatusEffectData
var owner_actor: Actor
var weapon_bonuses : Dictionary = {}
var crit_chance: float = 0.05
var crit_mult:float = 2.0
var attack_speed_mult:float = 1.0

func _ready() -> void:
	if texture:
		$Sprite2D.texture = texture
		var texture_radius = texture.get_width() / 2.0
		$Sprite2D.scale = Vector2.ONE * (radius / texture_radius)
	
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	$CollisionShape2D.shape.radius = radius
	
	modulate.a = 0.3
	monitoring = false
	
	await get_tree().create_timer(telegraph_time,false).timeout
	_activate()

func _activate() -> void:
	modulate.a = 1.0
	monitoring = true
	
	var tick_timer = Timer.new()
	tick_timer.wait_time = tick_interval
	tick_timer.timeout.connect(_deal_tick_damage)
	add_child(tick_timer)
	tick_timer.start()
	
	await get_tree().create_timer(duration,false).timeout
	queue_free()

func _deal_tick_damage() -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group("enemies"):
			var final_damage = WeaponData.roll_crit(damage_per_tick, crit_chance, crit_mult)
			body.take_damage(final_damage)
			if on_hit_effect:
				var interval_mult = 1.0 / owner_actor.attack_speed_mult if is_instance_valid(owner_actor) else 1.0
				body.apply_status_effect(on_hit_effect, owner_actor if is_instance_valid(owner_actor) else null, self)
