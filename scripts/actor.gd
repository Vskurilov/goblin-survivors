class_name Actor
extends CharacterBody2D


## Статы тела, которые оружие может усилить через weapon_bonuses.
## Пуст до появления улучшений тела(кинжал -> скорость бега)
## ВНИМАНИЕ: ключ попадает сюда ТОЛЬКО парой с читателем этого ключа.
const BODY_STATS_UPGRADABLE_BY_WEAPON: Array[String] = []

@onready var sprite: Sprite2D = $Sprite2D

@export var hit_flash_duration:float = 0.12
@export var hit_flash_color: Color = Color(1, 0.3, 0.3)
@export var dot_tint_color: Color = Color(0.3, 1.0, 0.3)


var _hit_flash_time_left:float = 0.0
var damage_taken_mult: float = 1.0
var active_effects: Array = []
var _flash_color:Color = Color.WHITE

func get_target_group() -> StringName:
	return &""

func flash_hit(color: Color = hit_flash_color) -> void:
	_hit_flash_time_left = hit_flash_duration
	_flash_color = color

func _upgrade_visual_feedback(delta: float) -> void:
	if _hit_flash_time_left > 0.0:
		_hit_flash_time_left -= delta
		sprite.material.set_shader_parameter("tint_color", _flash_color)
		sprite.material.set_shader_parameter("tint_amount", 1.0)
	elif active_effects.size() > 0:
		sprite.material.set_shader_parameter("tint_color", dot_tint_color)
		sprite.material.set_shader_parameter("tint_amount", 0.6)
	else:
		sprite.material.set_shader_parameter("tint_amount", 0.0)
 
func _get_stack_key(effect: StatusEffectData):
	if effect.stack_group != '':
		return effect.stack_group
	else:
		return effect

func _key_match(key_a, key_b) -> bool:
	if typeof(key_a) != typeof(key_b):
		return false
	return key_a == key_b

func apply_status_effect(effect: StatusEffectData, owner_actor: Actor = null, carrier: Node = null) -> void:
	var new_key = _get_stack_key(effect)
	var existing_count := 0
	var oldest_index := -1
	var oldest_time_left := INF
		
	for i in range(active_effects.size()):
		var existing_effect: StatusEffectData = active_effects[i]["effect"]
		if _key_match(_get_stack_key(existing_effect), new_key):
			if existing_effect.max_stacks != effect.max_stacks:
				push_warning("stack_group %s: разные max_stacks у %s (%d) и %s (%d) — держи один лимит на всю группу" % [
					str(new_key), existing_effect.resource_path, existing_effect.max_stacks,
					effect.resource_path, effect.max_stacks
				])
			existing_count += 1
			if active_effects[i]["time_left"] < oldest_time_left:
				oldest_time_left = active_effects[i]["time_left"]
				oldest_index = i
	if existing_count < effect.max_stacks:
		active_effects.append({
		"effect": effect,
		"time_left": effect.duration,
		"time_since_tick": 0.0,
		"owner_actor": owner_actor,
		"tick_interval": effect.tick_interval / (carrier.attack_speed_mult if carrier else 1.0),
		"crit_chance": carrier.crit_chance if carrier else 0.05,
		"crit_mult": carrier.crit_mult if carrier else 2.0,
		"weapon_bonuses": carrier.weapon_bonuses if carrier else {},
		})
	elif oldest_index != -1:
		active_effects[oldest_index]["time_left"] = active_effects[oldest_index]["effect"].duration

func _process_status_effects(delta: float) -> void:
	for i in range(active_effects.size() - 1, -1, -1):
		var effect_data = active_effects[i]
		var effect_owner = effect_data["owner_actor"]
		if not is_instance_valid(effect_owner):
			effect_owner = null
			effect_data["owner_actor"] = null
		effect_data["time_since_tick"] += delta
		if effect_data["time_since_tick"] >= effect_data["tick_interval"]:
			effect_data["effect"].apply_tick(self, effect_data["owner_actor"], effect_data["weapon_bonuses"], effect_data["crit_chance"], effect_data["crit_mult"])
			effect_data["time_since_tick"] = 0.0
		effect_data["time_left"] -= delta
		if effect_data["time_left"] <= 0:
			active_effects.remove_at(i)
	_upgrade_visual_feedback(delta)

func take_damage(amount: float, is_dot_tick:bool = false):
	push_error("Actor.take_damage() не переопределен в " + str(get_script().resource_path))

func is_valid_target(body:Node) -> bool:
	return false
