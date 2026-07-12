extends Actor

signal  died

@export var enemy_data: EnemyData
@export var behavior_state: Dictionary = {}

var health: float
var speed: float
var player
var nearby_enemies:Array = []

func get_target_group() -> StringName:
	return &"player"

func _ready():
	if enemy_data == null:
		push_warning("EnemyData не задан для: " + name)
		return
	if enemy_data.behavior == null:
		push_warning("EnemyDataBehavior не задан для: " + enemy_data.enemy_name)
		return
	health = enemy_data.health
	speed = enemy_data.speed
	$Sprite2D.scale = Vector2(enemy_data.visual_scale, enemy_data.visual_scale)
	if enemy_data.texture:
		$Sprite2D.texture = enemy_data.texture
	if enemy_data.collision_shape:
		$CollisionShape2D.shape = enemy_data.collision_shape
	$SeparationArea/CollisionShape2D.shape = $SeparationArea/CollisionShape2D.shape.duplicate()
	$SeparationArea/CollisionShape2D.shape.radius = enemy_data.body_radius + 60.0
	$SeparationArea.body_entered.connect(_on_separation_area_body_entered)
	$SeparationArea.body_exited.connect(_on_separation_area_body_exited)
		
	player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	if player.is_dead:
		return

func _on_separation_area_body_entered(body:Node2D) -> void:
	if body == self:
		return
	if not body.is_in_group("enemies"):
		return
	nearby_enemies.append(body)
	
func _on_separation_area_body_exited(body:Node2D) -> void:
	if body in nearby_enemies:
		nearby_enemies.erase(body)

func _physics_process(delta: float) -> void:
	_process_status_effects(delta)
	
	if not is_instance_valid(player):
		return
	if player.is_dead:
		return
	if enemy_data.behavior == null:
		return
	
	velocity = enemy_data.behavior.get_velocity(self, player, delta)
	move_and_slide()
	enemy_data.behavior.try_attack(self, player, delta)
	
func take_damage(amount,is_dot_tick:bool = false):
	flash_hit(dot_tint_color if is_dot_tick else hit_flash_color)
	health -= amount
	if health <= 0:
		died.emit()
		drop_gem()
		queue_free()
	
func drop_gem():
	var gem = enemy_data.gem_scene.instantiate()
	gem.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(gem)

func  is_valid_target(body:Node) -> bool:
	return body.is_in_group("player")
