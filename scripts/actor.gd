class_name Actor
extends CharacterBody2D


## Статы тела, которые оружие может усилить через weapon_bonuses.
## Пуст до появления улучшений тела(кинжал -> скорость бега)
## ВНИМАНИЕ: ключ попадает сюда ТОЛЬКО парой с читателем этого ключа.
const BODY_STATS_UPGRADABLE_BY_WEAPON: Array[String] = []

@onready var sprite: Sprite2D = $Sprite2D

@export var hit_flash_duration:float = 0.12
@export var hit_flash_color: Color = Color(1, 0.3, 0.3)

var is_dead:bool = false
var current_health:float = 0.0
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
		# Несколько эффектов - видел последний наложенный стак.
		sprite.material.set_shader_parameter("tint_color", active_effects.back()["effect"].tint_color)
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

## Стак — снимок в момент наложения: статы эффекта и носителя.
## Апгрейд, взятый позже, достаётся только следующим наложениям.
## "original" — эффект оружия, с которого снят снимок: по нему ключ стака и лимит.
func _make_effect_entry(effect: StatusEffectData, owner_actor: Actor, carrier: Node) -> Dictionary:
	return {
		"effect": effect.duplicate(),
		"original": effect,
		"time_left": effect.duration,
		"time_since_tick": 0.0,
		"owner_actor": owner_actor,
		"tick_interval": effect.tick_interval / (carrier.attack_speed_mult if carrier else 1.0),
		"crit_chance": carrier.crit_chance if carrier else 0.05,
		"crit_mult": carrier.crit_mult if carrier else 2.0,
		"weapon_bonuses": carrier.weapon_bonuses if carrier else {},
	}

func apply_status_effect(effect: StatusEffectData, owner_actor: Actor = null, carrier: Node = null) -> void:
	# На убитого не ложатся ни стаки, ни реакции: он только ждёт удаления.
	if is_dead:
		return
	# Реакция стихий съедает входящий эффект: стаком он уже не ложится.
	var reaction := Reactions.find(effect, active_effects)
	if reaction != null:
		reaction.react(self, _make_effect_entry(effect, owner_actor, carrier))
		return
	var new_key = _get_stack_key(effect)
	var existing_count := 0
	var oldest_index := -1
	var oldest_time_left := INF
		
	for i in range(active_effects.size()):
		# Сравниваем оригиналы: у каждого снимка свой объект, ключ по нему не совпал бы никогда.		
		var existing_effect: StatusEffectData = active_effects[i]["original"]
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
		active_effects.append(_make_effect_entry(effect, owner_actor, carrier))
	elif oldest_index != -1:
		# Лимит набран: старейший стек заменяется свежим наложением — новые статы и полная длительность.
		# Фаза тика сохраняется: иначе частые попадания не дадут стаку тикнуть ни разу.
		var entry := _make_effect_entry(effect, owner_actor, carrier)
		entry["time_since_tick"] = active_effects[oldest_index]["time_since_tick"]
		active_effects[oldest_index] = entry

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
			# Остаток переносится (закон 62): обнуление теряло до шага физики на каждый тик.
			effect_data["time_since_tick"] -= effect_data["tick_interval"]
		effect_data["time_left"] -= delta
		if effect_data["time_left"] <= 0:
			active_effects.remove_at(i)
	_upgrade_visual_feedback(delta)

## Итоговый множитель скорости от активных эффектов. Не хранится, а считается
## каждый раз: истечение, обновление стака и апгрейд скорости не требуют "вернуть
## как было". Из нескольких замедлений действует сильнейшее, они не перемножаются.
func get_status_speed_mult() -> float:
	var mult := 1.0
	for entry in active_effects:
		mult = minf(mult, entry["effect"].get_move_speed_mult())
	return mult

## ЕДИНСТВЕННЫЙ путь урона для обеих сущностей: прямое попадание, тик зоны
## и тик статус-эффекта приходят сюда. Поэтому сторож is_dead стоит один раз
## на всех: queue_free() отложен до конца кадра, и узел продолжает принимать
## удары, поставленные в очередь в этом же кадре.
## source_effect — эффект, чей тик нанёс урон: вспышка его цветом. Прямой удар — null.
func take_damage(amount:float, source_effect: StatusEffectData = null) -> void:
	if is_dead:
		return
	flash_hit(source_effect.tint_color if source_effect != null else hit_flash_color)
	current_health = maxf(current_health - amount * damage_taken_mult, 0.0)
	_on_health_changed()
	if current_health <= 0.0:
		is_dead = true
		_die()


## Реакция вида на изменение здоровья. У врага вида нет — заглушка пуста.
func  _on_health_changed() -> void:
	pass

## Смерть — событие, а не состояние здоровья. Флаг поднимается в take_damage
## ДО вызова: сигналы синхронны, и подписчик увидит уже мёртвого актора.
func _die() -> void:
	pass
