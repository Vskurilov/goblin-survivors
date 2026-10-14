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
		# Иконки апгрейдов бывают любого размера — кнопка сама ужимает до 64 px.
		buttons[i].add_theme_constant_override("icon_max_width", 64)
		# Курсор — это фокус кнопки: мышь переносит его на карточку под собой.
		buttons[i].mouse_entered.connect(buttons[i].grab_focus)
		buttons[i].add_theme_stylebox_override("focus", _make_cursor_style())
	_validate_upgrade_pool()

## Рамка карточки под курсором. Рисуется поверх кнопки, фон не трогает.
func _make_cursor_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.741, 1.0, 1.0)
	style.set_expand_margin_all(2)
	return style

## Передвигает курсор для выбора апгрейда
func _move_cursor(step: int) -> void:
	var shown: Array[Button] = []
	for button in buttons:
		if button.visible:
			shown.append(button)
	if shown.is_empty():
		return
	var index := shown.find(get_viewport().gui_get_focus_owner())
	if index == -1:
		index = 0
	else:
		index = clampi(index + step, 0, shown.size() - 1)
	shown[index].grab_focus()

## Стрелки и Enter/Space кнопки обрабатывают сами (ui_left/ui_right/ui_accept).
## A/D (move_left/move_right) двигаем курсор вручную.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_left"):
		_move_cursor(-1)
	elif event.is_action_pressed("move_right"):
		_move_cursor(1)
	else:
		return
	get_viewport().set_input_as_handled()

## Окно стави паузу само и само её снимает в _on_button_pressed.
func _on_player_leveled_up(player: Player) -> void:
	if not has_upgrades(player):
		return
	get_tree().paused = true
	show_choices(player)

func show_choices(player:Node) -> void:
	_current_player = player
	var available_pool: Array[UpgradeData] = [] 
	available_pool.assign(upgrade_pool.filter(func(upgrade: UpgradeData): return upgrade.is_available(player)))
	# Запись пула может дать несколько карточек: бафф с one_weapon — по одной на оружие.
	var offers: Array[UpgradeData] = []
	for upgrade in available_pool:
		offers.append_array(upgrade.make_offers(player))
	current_choices = _pick_random(offers, buttons.size())
	for i in buttons.size():
		if i < current_choices.size():
			buttons[i].visible = true
			buttons[i].text = current_choices[i].get_card_text(player)
			buttons[i].icon = current_choices[i].icon
		else:
			buttons[i].visible = false
	visible = true
	# Каждое новое окно начинает с первой карточки.
	if not current_choices.is_empty():
		buttons[0].grab_focus()

func _pick_random(pool:Array[UpgradeData], count:int) -> Array[UpgradeData]:
	var shuffled = pool.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, min(count, pool.size()))

func _on_button_pressed(index:int) -> void:
	_current_player.apply_upgrade(current_choices[index])
	get_tree().paused = false
	visible = false

func has_upgrades(player:Node) -> bool:
	return upgrade_pool.any(func(upgrade: UpgradeData): return upgrade.is_available(player))
	
## Имена всех скриптовых полей оружия, эффектов и тела — пространство,
## в котором stat_name апгрейда обязан существовать.
func _collect_known_stats() -> Dictionary:
	var registry:= {}
	for entry in ProjectSettings.get_global_class_list():
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
	for property in object.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	return names
	
## Дефекты контента в пуле. Object.set() на отсутствующее поле МОЛЧИТ —
## без этой проверки апгрейд в опечатку "применяется" в никуда.
func _validate_upgrade_pool() -> void:
	if not Tags.hints_match():
		push_error("Tags: массив имён и строка-подсказка разошлись - инспектор предлагает не тот набор")
	# Реакции — общий контент забега, как и теги: проверяем здесь же, на старте.
	Reactions.validate()
	var known:= _collect_known_stats()
	for upgrade in upgrade_pool:
		_validate_filter_names(upgrade)
		if "granted_tags" in upgrade and upgrade.granted_tags.is_empty():
			push_error("upgrade_pool: у апгрейда '%s' пуст granted_tags - выдавать нечего." % upgrade.upgrade_name)
		if "granted_effect" in upgrade and upgrade.granted_effect != null:
			if not upgrade.granted_tags.any(func(tag): return upgrade.granted_effect.has_tag(tag)):
				push_error("upgrade_pool: эффект гранта '%s' не несёт ни одного из его тегов '%s' - апгрейды стихий до эффекта не дойдут." % [upgrade.upgrade_name, upgrade.granted_tags])
		# Апгрейды без стата (выдача тегов) — не наше дело.
		if not "stat_name" in upgrade:
			continue
		if upgrade.stat_name.is_empty():
			push_error("upgrade_pool: у апгрейда '%s' не заполнен stat_name." % upgrade.upgrade_name)
			continue
		if upgrade.stat_name in TaggedStatUpgradeData.FORBIDDEN_STATS:
			push_error("upgrade_pool: апгрейд '%s' целится в запрещенный стат '%s'." % [upgrade.upgrade_name, upgrade.stat_name])
			continue
		if not known.has(upgrade.stat_name):
			push_error("upgrade_pool: апгрейд '%s' целится в несуществующий стат '%s'." % [upgrade.upgrade_name, upgrade.stat_name])

func _validate_filter_names(upgrade: UpgradeData) -> void:
	if "required_tags" in upgrade:
		for tag in upgrade.required_tags:
			if not tag in Tags.ELEMENTS:
				push_error("upgrade_pool: у апгрейда '%s' тег '%s' отсутствует в Tags.ELEMENTS." % [upgrade.upgrade_name, tag])
	if "granted_tags" in upgrade:
		for tag in upgrade.granted_tags:
			if not tag in Tags.ELEMENTS:
				push_error("upgrade_pool: у апгрейда '%s' выдаваемый тег '%s' отсутствует в Tags.ELEMENTS." % [upgrade.upgrade_name, tag])
	if "required_identity" in upgrade:
		for identity_name in upgrade.required_identity:
			if not identity_name in Tags.IDENTITIES:
				push_error("upgrade_pool: у апгрейда '%s' identity '%s' отсутствует в Tags.IDENTITIES." % [upgrade.upgrade_name, identity_name])
