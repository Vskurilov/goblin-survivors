extends Sprite2D

## Фон забега: повторяющаяся текстура (region + texture_repeat) под камерой. Кусок ходит за
## камерой и растёт с отдалением, а узор стоит на месте мира, где его положили в сцене:
## фона хватает при любом отдалении и как далеко ни уйди. Спрайт — с centered (как в сцене).

## Запас за краем кадра, px мира: на кадр запаздывания за камерой и на поворот фона.
const MARGIN := 256.0

# Как фон лежал в сцене: к этому месту привязан узор.
var _origin: Transform2D
var _region0: Rect2


func _ready() -> void:
	_origin = global_transform
	_region0 = region_rect


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# Диагональ кадра — сторона куска: кадр влезает при любом повороте фона.
	var side := (get_viewport().get_visible_rect().size / camera.zoom).length() + MARGIN
	var unit := _origin.get_scale().abs()
	var size := Vector2(maxf(_region0.size.x, side / unit.x), maxf(_region0.size.y, side / unit.y))
	# Середина кадра в осях фона из сцены. Середина куска встаёт туда, начало узора
	# сдвигается на столько же — и узор остаётся на месте мира.
	var center := _origin.affine_inverse() * camera.get_screen_center_position()
	global_position = _origin * center
	region_rect = Rect2(_region0.position + center + (_region0.size - size) / 2.0, size)
