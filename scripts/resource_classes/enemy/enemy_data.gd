class_name EnemyData
extends Resource

@export var enemy_name: String = 'Goblin'
@export var health: int = 3
@export var speed: float = 60.0
@export var contact_damage: float = 20.0
@export var gem_scene: PackedScene
@export var texture: Texture2D
## Порядок наложения типа: больше — рисуется поверх других типов. Враги одного типа
## рисуются подряд, и Godot склеивает их спрайты в один вызов отрисовки.
## У типов с разными текстурами значения должны быть разными, иначе спрайты снова перемешаются.
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
