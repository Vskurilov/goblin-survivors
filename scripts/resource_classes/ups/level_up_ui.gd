extends CanvasLayer

@export var upgrade_pool: Array[UpgradeData] = []

@onready var buttons: Array[Button] = [
	$UpdateButtons/UpButtonOne,
	$UpdateButtons/UpButtonTwo,
	$UpdateButtons/UpButtonThree,
]

var current_choises: Array[UpgradeData] = []
var _current_player: Node

func _ready() -> void:
	for i in buttons.size():
		buttons[i].pressed.connect(_on_button_pressed.bind(i))
		pass

func show_choices(player:Node) -> void:
	_current_player = player
	var available_pool = upgrade_pool.filter(func(upgrade: UpgradeData): return upgrade.is_available(player))
	current_choises = _pick_random(available_pool, buttons.size())
	for i in buttons.size():
		if i < current_choises.size():
			buttons[i].visible = true
			buttons[i].text = current_choises[i].upgrade_name
			buttons[i].icon = current_choises[i].icon
		else:
			buttons[i].visible = false
	visible = true
	
func _pick_random(pool:Array[UpgradeData], count:int) -> Array[UpgradeData]:
	var shuffled = pool.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, min(count, pool.size()))

func  _on_button_pressed(index:int) -> void:
	current_choises[index].apply(_current_player)
	_current_player.current_health = _current_player.max_health
	_current_player.update_health(_current_player.current_health)
	get_tree().paused = false
	visible = false

func  has_upgrades(player:Node) -> bool:
	return upgrade_pool.any(func(upgrade: UpgradeData): return upgrade.is_available(player))
	
	
	
	
