class_name Gem
extends Node2D

## Вид и размер гема опыта. Сцена с этим скриптом в игру не попадает: гемы — строки
## в узле Gems, он один раз читает отсюда спрайт, радиус и вид копилки.

## Радиус гема. Подбор — когда центр гема ближе к игроку, чем Player.pickup_radius
## плюс этот радиус; магнит — Player.magnet_radius плюс этот радиус.
@export var radius: float = 10.0
## Вид копилки. Пусто — выглядит как обычный гем.
@export var overflow_texture: Texture2D
## Во сколько раз копилка крупнее обычного гема, вместе с радиусом.
@export var overflow_scale: float = 1.5
