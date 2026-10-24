class_name EnemyData
extends Resource

@export var enemy_name: String = 'Goblin'
@export var health: int = 3
@export var speed: float = 60.0
@export var contact_damage: float = 20.0
@export var gem_scene: PackedScene
@export var texture: Texture2D
## Порядок наложения типа: больше — рисуется поверх других типов. Враги одного типа
## рисуются одним MultiMesh (Horde), одним вызовом отрисовки. У типов с одинаковым
## значением слой общий, и сверху тот тип, чей первый враг появился в забеге позже.
@export_range(0, 99) var draw_order: int = 0
@export var visual_scale: float = 1.0
@export var behavior: EnemyBehaviorData
@export var mass: float = 1.0
@export var body_radius: float = 20.0
@export var collision_shape: Shape2D
## Размер опыта, который дает гем, выпадающий из врага
@export var xp_reward: int = 5
## Цена в бюджете угрозы: сколько угрозы на экране занимает один такой враг.
## 0 — не задана: ошибка на старте, и спавнер его не выпускает.
@export var threat_cost: int = 0
## С какой секунды забега враг может появиться.
@export_range(0.0, 3600.0, 1.0, "or_greater", "suffix:s") var unlock_time: float = 0.0

## Масштаб тела из прежней сцены врага (у CollisionShape2D был scale 3):
## радиусы в *_hitbox.tres заданы без него.
const HITBOX_SCALE: float = 3.0

## Тело врага для попаданий и касания игрока — круг. Радиус — у фигуры collision_shape
## (у круга его радиус, у других фигур половина ширины), умноженный на HITBOX_SCALE.
## Попадания и касания считает Horde.
func get_hit_radius() -> float:
	# Без фигуры — круг радиусом 10, как фигура по умолчанию в прежней сцене врага.
	var half_width := 10.0
	if collision_shape != null:
		half_width = collision_shape.get_rect().size.x * 0.5
	return half_width * HITBOX_SCALE
