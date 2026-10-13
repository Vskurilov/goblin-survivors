extends Actor
class_name Player

## Сигнал сообщающий о здоровье игрока
signal health_changed(current: float, maximum: float)
## Уровень и опыт меняются вместе - один сигнал на три значения
signal xp_changed(level: int, current_xp: int, xp_to_next: int)
signal kills_changed(kills: int)
## Раз в секунду обновляем таймер времени жизни
signal survival_time_changed(seconds: float)
##Получен уровень. Передаёт себя: окно выбора нужно, к кому применять апгрейд
signal leveled_up(player: Player)
##Забег окончен. Итоги в аргументах, чтобы экрану не лезть в игрока.
signal run_ended(kills: int, survival_time: float, level: int)

const MIN_FIRE_PERIOD: float = 0.01

@export var speed: float = 200.0
@export var max_health: float = 100
@export var weapons:Array[WeaponData] = []
@export var mass: float = 8.0
@export var body_radius: float = 30.0
##Радиус притяжения гемов
@export var magnet_radius: float = 100.0:
	set(value):
		magnet_radius = value
		#При загрузке сцены сеттер срабатывает до появления детей
		if is_node_ready():
			_apply_magnet_radius()
 
var touching_enemies:Array = []
var current_xp:int = 0
var level:int = 1
var xp_to_next_lv:int = 10
var survival_time:float = 0.0
var kills:int = 0
var weapon_timers: Array[Timer] = []

func get_target_group() -> StringName:
	return &"enemies"

func _ready():
	# Начальное состояние объявляется так же, как любое изменение.
	heal_to_full()
	xp_changed.emit(level, current_xp, xp_to_next_lv)
	kills_changed.emit(kills)
	survival_time_changed.emit(survival_time)
	_apply_magnet_radius()
	_setup_weapons()

func _physics_process(delta):
	_process_status_effects(delta)
	var direction = Input.get_vector("move_left", "move_right", "move_up","move_down")
	velocity = direction * speed * get_status_speed_mult()
	move_and_slide()
	if not is_dead:
		var whole_seconds := int(survival_time)
		survival_time = survival_time + delta
		if int(survival_time) != whole_seconds:
			survival_time_changed.emit(survival_time)
	if not touching_enemies.is_empty():
		var total_damage = 0.0
		for i in range(touching_enemies.size() - 1, -1, -1):
			var enemy = touching_enemies[i]
			if not is_instance_valid(enemy):
				touching_enemies.remove_at(i)
				continue
			if enemy.enemy_data == null:
				continue
			total_damage += enemy.enemy_data.contact_damage
		if total_damage > 0.0:
			take_damage(total_damage * delta)

func _on_health_changed() -> void:
	health_changed.emit(current_health, max_health)
	
## static: состояния игрока не трогает, поэтому ей пользуется и UI.
static func format_time(seconds_value: float) -> String:
	var total_seconds = int(seconds_value)
	# Целочисленное деление намеренно: нужны полные минуты, остаток берётся ниже через %.
	@warning_ignore("integer_division")
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	if total_seconds >= 60:
		return str(minutes) + " мин " + str(seconds) + " сек"
	else:
		return str(seconds) + " сек"

func gain_xp(amount):
	current_xp += amount
	var did_level_up = false
	while current_xp >= xp_to_next_lv:
		level += 1
		xp_to_next_lv = xp_to_next_lv + int(xp_to_next_lv * ((1.1**2)/2))
		did_level_up = true
	if did_level_up:
		heal_to_full()
		leveled_up.emit(self)
	xp_changed.emit(level, current_xp,xp_to_next_lv)

func add_kill():
	kills = kills + 1
	kills_changed.emit(kills)

func _die() -> void:
	print("Game Over")
	set_physics_process(false)
	run_ended.emit(kills, survival_time, level)

## Единственный путь лечения. Присваивает ровно максимум, поэтому верхняя
## граница здоровья держится ПО ПОСТРОЕНИЮ, а не клампом. Появится ЧАСТИЧНОЕ
## лечение — делать его методом с clampf(…, 0.0, max_health) здесь же, поле
## напрямую не увеличивать: бар молча обрежет значение, а лейбл покажет
## "130/100". Для врагов границы нет вовсе — max_health живёт только у игрока;
## понадобится лекарь-враг — виртуальный get_max_health() (у врага → enemy_data.health).
func heal_to_full() -> void:
	current_health = max_health
	_on_health_changed()

## Единственная точка применения апгрейда. Последствия (таймеры, лечение под новым максимум) - 
## - забота игрока, а не окна выбора
func apply_upgrade(upgrade: UpgradeData) -> void:
	upgrade.apply(self)
	refresh_weapon_timers()
	heal_to_full()

func refresh_weapon_timers() -> void:
	for i in weapon_timers.size():
		weapon_timers[i].wait_time = maxf(weapons[i].fire_rate / weapons[i].attack_speed_mult, MIN_FIRE_PERIOD)

func _setup_weapons():
	for i in weapons.size():
		weapons[i] = weapons[i].duplicate()
		# duplicate() не копирует массивы: без этого грант-тег запишется в сам .tres
		# и переживёт рестарт забега (проверено на 4.6).
		weapons[i].tags = weapons[i].tags.duplicate()
		# Свои копии эффектов: апгрейд эффекта не должен попасть в .tres.
		# Типизированный массив собираем циклом: map() вернул бы нетипизированный.
		var effects: Array[StatusEffectData] = []
		for effect in weapons[i].on_hit_effects:
			if effect != null:
				effects.append(effect.duplicate())
		weapons[i].on_hit_effects = effects
		weapons[i].validate_grant_effects()
		var bonuses = weapons[i].get("weapon_bonuses")
		if bonuses != null:
			weapons[i].set("weapon_bonuses", bonuses.duplicate())
		var trajectory = weapons[i].get("base_trajectory")
		if trajectory != null:
			weapons[i].set("base_trajectory", trajectory.duplicate())
	for weapon in weapons:
		var timer = Timer.new()
		timer.wait_time = maxf(weapon.fire_rate / weapon.attack_speed_mult, MIN_FIRE_PERIOD)
		timer.timeout.connect(weapon.fire.bind(self))
		add_child(timer)
		weapon_timers.append(timer)
		timer.start()

func _on_hurt_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		touching_enemies.append(body)

func _on_hurt_box_body_exited(body: Node2D) -> void:
	if body in touching_enemies:
		touching_enemies.erase(body)

func _apply_magnet_radius() -> void:
	($MagnetArea/CollisionShape2D.shape as CircleShape2D).radius = magnet_radius

func _on_magnet_area_area_entered(area: Area2D) -> void:
	if area is Gem:
		area.attract_to(self)

func _on_pickup_area_area_entered(area: Area2D) -> void:
	
	if area is Gem:
		area.queue_free()
		gain_xp(area.xp_value)
