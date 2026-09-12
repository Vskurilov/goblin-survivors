extends CanvasLayer

@export var upgrade_pool: Array[UpgradeData] = []

@onready var buttons: Array[Button] = [
	$UpdateButtons/UpButtonOne,
	$UpdateButtons/UpButtonTwo,
	$UpdateButtons/UpButtonThree,
]

var current_choices: Array[UpgradeData] = []
var _current_player: Node

func _ready() -> void:
	for i in buttons.size():
		buttons[i].pressed.connect(_on_button_pressed.bind(i))
		pass
	_validate_upgrade_pool()
	

func show_choices(player:Node) -> void:
	_current_player = player
	var available_pool: Array[UpgradeData] = [] 
	available_pool.assign(upgrade_pool.filter(func(upgrade: UpgradeData): return upgrade.is_available(player)))
	current_choices = _pick_random(available_pool, buttons.size())
	for i in buttons.size():
		if i < current_choices.size():
			buttons[i].visible = true
			buttons[i].text = current_choices[i].upgrade_name
			buttons[i].icon = current_choices[i].icon
		else:
			buttons[i].visible = false
	visible = true

func _pick_random(pool:Array[UpgradeData], count:int) -> Array[UpgradeData]:
	var shuffled = pool.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, min(count, pool.size()))

func  _on_button_pressed(index:int) -> void:
	current_choices[index].apply(_current_player)
	_current_player.refresh_weapon_timers()
	_current_player.current_health = _current_player.max_health
	_current_player.update_health(_current_player.current_health)
	get_tree().paused = false
	visible = false

func  has_upgrades(player:Node) -> bool:
	return upgrade_pool.any(func(upgrade: UpgradeData): return upgrade.is_available(player))
	
## Имена всех скриптовых полей оружия, эффектов и тела — пространство,
## в котором stat_name апгрейда обязан существовать.
func  _collect_known_stats() -> Dictionary:
	var registry:= {}
	for  entry  in ProjectSettings.get_global_class_list():
		registry[String(entry["class"])] = entry
	var known:= {}
	for class_name_string in registry:
	# base хранит только прямого родителя — идём по цепочке вверх.
		var cursor: String = class_name_string
		var is_content:= false
		while registry.has(cursor):
			cursor = String(registry[cursor]["base"])
			if cursor == "WeaponData" or cursor == "StatusEffectData":
				is_content = true
				break
		if not is_content: 
			continue
		var instance = load(registry[class_name_string]["path"]).new()
		for stat in _script_stats(instance):
			known[stat] = true
	
	var player_probe = Player.new()
	for stat in _script_stats(player_probe):
		known[stat] = true 
	player_probe.free()
	return known
		
func _script_stats(object) -> Array:
	var names: Array = []
	for property in  object.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	return names
	
## Дефекты контента в пуле. Object.set() на отсутствующее поле МОЛЧИТ —
## без этой проверки апгрейд в опечатку "применяется" в никуда.
func _validate_upgrade_pool() -> void:
	var known:= _collect_known_stats()
	for upgrade in upgrade_pool:
		# Апгрейды без стата (будущая выдача тегов) — не наше дело.
		if not "stat_name" in upgrade:
			continue
		if upgrade.stat_name.is_empty():
			push_error("upgrade_pool: у апгрейда '%s' не заполнен stat_name." % upgrade.upgrade_name)
			continue
		if upgrade.stat_name in TaggedStatUpgradeData.FORBIDDEN_STATS:
			push_error("upgrade_pool: апгрейд '%s' целится в запрещенный стат '%s'." % [upgrade.upgrade_name, upgrade.stat_name])
			continue
		if not known.has(upgrade.stat_name):
			push_error("upgrade_pool: апгрейд '%s' целится в несущствующий стат '%s'." % [upgrade.upgrade_name, upgrade.stat_name])
			
			
	
