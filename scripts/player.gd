extends  Actor

const MIN_FIRE_PERIOD: float = 0.01

@export var speed: float = 200.0
@export var max_health: float = 100
@export var weapons:Array[WeaponData] = []
@export var mass: float = 8.0
@export var body_radius: float = 30.0

var current_health: float 
var is_dead:bool = false
var touching_enemies:Array = []
var current_xp:int = 0
var level:int = 1
var xp_to_next_lv:int = 10
var survival_time:float = 0.0
var kills:int = 0
var weapon_timers: Array[Timer] = []
 
@onready var levelupui = get_tree().get_first_node_in_group("levelup_ui")
@onready var healhbar = get_tree().get_first_node_in_group("health_bar")
@onready var healthlabel = get_tree().get_first_node_in_group("health_label")
@onready var timerlabel = get_tree().get_first_node_in_group("timer_label")
@onready var levellabel = get_tree().get_first_node_in_group("level_label")
@onready var killcountlabel = get_tree().get_first_node_in_group("kill_count_label")
@onready var gameoverui = get_tree().get_first_node_in_group("game_over_ui")
@onready var gameoverstatlabel = get_tree().get_first_node_in_group("game_over_stat_label")

func get_target_group() -> StringName:
	return &"enemies"

func  _ready():
	current_health = max_health
	healhbar.max_value = max_health
	update_health(current_health)
	update_level_xp()
	killcountlabel.text = "убито: " + str(kills)
	_setup_weapons()

func _physics_process(delta):
	_process_status_effects(delta)
	var direction = Input.get_vector("move_left", "move_right", "move_up","move_down")
	velocity = direction * speed
	move_and_slide()
	if not is_dead:
		survival_time = survival_time + delta		
		timerlabel.text = "мочишь гоблинов уже " + format_time(survival_time)
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

func  update_health(current_health):
	healhbar.max_value = max_health
	healhbar.value = current_health
	healthlabel.text = str(int(current_health)) + "/" + str(int(max_health))

func  update_level_xp():
	levellabel.text = "уровень: " + str(level) + " | XP: " + str(current_xp) + " | нужно до уровня: " + str(xp_to_next_lv)

func format_time(seconds_value: float) -> String:
	var total_seconds = int(seconds_value)
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	if total_seconds >= 60:
		return str(minutes) + " мин " + str(seconds) + " сек"
	else:
		return str(seconds) + " сек"

func take_damage(amount:float, is_dot_tick:bool = false):
	if is_dead:
		return
	flash_hit(dot_tint_color if is_dot_tick else hit_flash_color)
	current_health -= amount * damage_taken_mult
	update_health(current_health)
	if current_health <= 0:
		die()
		update_health(0)

func gain_xp(amount):
	current_xp += amount
	var leveled_up = false
	
	while current_xp >= xp_to_next_lv:  
		level += 1
		xp_to_next_lv =  xp_to_next_lv + int(xp_to_next_lv * ((1.1**2)/2))
		leveled_up = true
		
	if leveled_up:
		current_health = max_health
		update_health(current_health)
		if levelupui.has_upgrades(self):
			get_tree().paused = true
			levelupui.show_choices(self)
	update_level_xp()

func add_kill():
	kills = kills + 1
	killcountlabel.text = "убито: " + str(kills)

func die():
	is_dead = true
	print("Game Over")
	set_physics_process(false)
	get_tree().paused = true
	gameoverui.visible = true
	gameoverstatlabel.text = "Ты завалил " + str(kills) + " гоблинов. Время их мучений " + format_time(survival_time) + ". Левел: " + str(level)

func refresh_weapon_timers() -> void:
	for i in weapon_timers.size():
		weapon_timers[i].wait_time = maxf(weapons[i].fire_rate / weapons[i].attack_speed_mult, MIN_FIRE_PERIOD)

func _setup_weapons():
	for i in weapons.size():
		weapons[i] = weapons[i].duplicate()
		var effect = weapons[i].get("on_hit_effect")
		if effect != null:
			weapons[i].set("on_hit_effect", effect.duplicate())
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

func get_enemies_sorted(criteria:Callable) -> Array:
	var enemies = get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(criteria)
	return enemies

func get_enemy(criteria: Callable):
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return null
	var best = enemies[0]
	for enemy in enemies:
		if criteria.call(enemy, best):
			best = enemy
	return best
	
func nearest_criteria(candidate:Node2D, current_best:Node2D) -> bool:
	return global_position.distance_to(candidate.global_position) < global_position.distance_to(current_best.global_position)

func  fartest_criteria(candidate:Node2D, current_best:Node2D) -> bool:
	return global_position.distance_to(candidate.global_position) > global_position.distance_to(current_best.global_position)
	
func  get_random_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return null
	return enemies[randi() % enemies.size()]
	
func  is_valid_target(body:Node) -> bool:
	return body.is_in_group("enemies")
	
	
func _on_hurt_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		touching_enemies.append(body)

func _on_hurt_box_body_exited(body: Node2D) -> void:
	if body in touching_enemies:
		touching_enemies.erase(body)

func _on_pickup_area_area_entered(area: Area2D) -> void:
	if area.is_in_group("gem"):
		area.queue_free()
		gain_xp(5)

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
