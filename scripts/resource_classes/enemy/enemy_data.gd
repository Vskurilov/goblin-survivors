class_name EnemyData
extends  Resource

@export var enemy_name: String = 'Goblin'
@export var health: int = 3
@export var speed: float = 60.0
@export var contact_damage: float = 20.0
@export var gem_scene: PackedScene
@export var texture: Texture2D
@export var visual_scale: float = 1.0
@export var behavior: EnemyBehaviorData
@export var mass: float = 1.0
@export var body_radius: float = 20.0
@export var collision_shape: Shape2D
