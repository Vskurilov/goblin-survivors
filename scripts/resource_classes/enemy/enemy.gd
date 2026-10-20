extends Actor
class_name Enemy

signal died

@export var enemy_data: EnemyData

var behavior_state: Dictionary = {}
var speed: float
var player: Actor
## Номер в реестре Horde: по нему враг берёт свой толчок расталкивания. -1 — не в реестре.
var horde_index: int = -1
var _horde: Horde

## Враги рисуются над фоном (у него -200), но под игроком, снарядами и гемами (у них 0).
## Внутри — группами по типу, см. EnemyData.draw_order.
const DRAW_Z: int = -100
## Масштаб тела из прежней сцены врага (у CollisionShape2D был scale 3):
## радиусы в *_hitbox.tres заданы без него.
const HITBOX_SCALE: float = 3.0

func get_target_group() -> StringName:
	return &"player"

func _ready():
	if enemy_data == null:
		push_warning("EnemyData не задан для: " + name)
		queue_free()
		return
	if enemy_data.behavior == null:
		push_warning("EnemyDataBehavior не задан для: " + enemy_data.enemy_name)
		queue_free()
		return
	current_health = enemy_data.health
	speed = enemy_data.speed
	$Sprite2D.scale = Vector2(enemy_data.visual_scale, enemy_data.visual_scale)
	if enemy_data.texture:
		$Sprite2D.texture = enemy_data.texture
	$Sprite2D.z_index = DRAW_Z + enemy_data.draw_order
	player = get_tree().get_first_node_in_group("player")
	_horde = get_tree().get_first_node_in_group(&"horde") as Horde
	if _horde == null:
		push_warning("В сцене нет узла Horde: врагу некому считать расталкивание.")
		queue_free()
		return
	_horde.register(self)
	
# Узел покидает дерево в конце кадра, когда queue_free() доходит до дела.
func _exit_tree() -> void:
	if horde_index >= 0 and is_instance_valid(_horde):
		_horde.unregister(self)
	_clear_status_effects()

## Тело врага для попаданий и касания игрока — круг. Радиус — у фигуры
## enemy_data.collision_shape (у круга его радиус, у других фигур половина ширины),
## умноженный на HITBOX_SCALE. Попадания и касания считает Horde.
func get_hit_radius() -> float:
	# Без фигуры — круг радиусом 10, как фигура по умолчанию в прежней сцене врага.
	var half_width := 10.0
	if enemy_data.collision_shape != null:
		half_width = enemy_data.collision_shape.get_rect().size.x * 0.5
	return half_width * HITBOX_SCALE

func _physics_process(delta: float) -> void:
	# Убитый ждёт удаления до конца шага физики: ход и атака ему уже не положены.
	# Тики эффектов прошли раньше, в EffectTable: убитый тиком сюда уже мёртвым.
	if is_dead:
		return
	if _tint_pending:
		_update_tint(delta)
	if not is_instance_valid(player):
		return
	if player.is_dead:
		return
	if enemy_data.behavior == null:
		return
	velocity = enemy_data.behavior.get_velocity(self, player, delta) + _horde.sep_vel[horde_index]
	global_position += velocity * delta
	enemy_data.behavior.try_attack(self, player, delta)
	
func _die() -> void:
	died.emit()
	drop_gem()
	queue_free()
	
	
func drop_gem():
	if enemy_data == null or enemy_data.gem_scene == null:
		return
	Gem.drop(enemy_data.gem_scene, enemy_data.xp_reward, global_position, get_tree().current_scene)
