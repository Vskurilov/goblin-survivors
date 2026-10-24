extends Node2D
## Стресс-сцена (шаг 0): нагружает игру как есть и пишет отчёт в CSV.
## Запуск: открыть scenes/debug/stress_test.tscn, выбрать сценарий в инспекторе корня, F6.
## Игру не меняет: берёт Main.tscn, выключает спавнер и окно уровня,
## держит игрока бессмертным и создаёт нагрузку сама.
## Отчёт: user://stress/ (в редакторе: Проект → Открыть папку данных проекта).

## Конец кадра: всё посчитано, окно замера можно открыть или закрыть.
signal frame_ended

enum Scenario { SUITE, RAMP, PROJECTILES, MASS_DEATH, LOW_FPS, LONG_FIGHT }

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
## Стрела лучника: летит сквозь толпу, никого не задевая (сценарий «снаряды»).
const ARROW_WEAPON: ProjectileWeaponData = preload("res://resources/enemy/archer/archer_weapon.tres")
const ZONE_SCRIPT: Script = preload("res://scripts/resource_classes/weapon/aoe_zone.gd")
const IMMORTAL_HP := 1.0e9
## Сюита — все сценарии, кроме долгого боя, подряд и в один файл.
const SUITE_ORDER: Array[int] = [Scenario.RAMP, Scenario.PROJECTILES, Scenario.MASS_DEATH, Scenario.LOW_FPS]
const NAMES: Array[String] = ["suite", "ramp", "projectiles", "death", "lowfps", "long"]
const TITLES: Array[String] = ["сюита", "лестница", "снаряды", "массовая смерть", "низкий FPS", "долгий бой"]
const COLUMNS: Array[String] = [
	"scenario", "window", "load", "enemies", "wall_s", "game_s", "game_speed",
	"frames", "tick_frames", "fps", "steps_per_frame",
	"frame_avg_ms", "frame_p99_ms", "frame_max_ms",
	"pre_ms", "phys_scripts_ms", "phys_step_ms", "process_ms", "late_ms", "render_ms", "delay_ms", "gpu_ms", "draw_calls",
	"phys_objects", "phys_pairs", "nodes", "orphans", "resources", "mem_static_mb",
	"projectiles", "arrows", "zones", "gems", "stacks_per_enemy", "stacks_max",
	"fires_per_s", "fires_expected_per_s", "fires_per_real_s", "shots_per_s",
	"targets_avg", "targets_max", "multi_share", "corpse_hits", "dead_shots",
	"deaths", "kills", "damage_per_s", "xp_dropped", "xp_picked", "xp_on_map", "xp_lost",
	"levels", "level_signals", "windows", "crowd_overlaps", "touching", "note",
]
## Части кадра в окне: до физики, скрипты физики, шаг физики, процесс, после процесса, отрисовка, искусственная задержка.
const PART_COUNT := 7

@export var scenario: Scenario = Scenario.SUITE

@export_group("Лестница")
## Сколько врагов держать на каждой ступени.
@export var ramp_steps: Array[int] = [100, 500, 1000, 2000, 3000]
## Ступень со средним кадром дольше этого — последняя.
@export var stop_frame_ms: float = 500.0

@export_group("Снаряды и смерть")
@export var crowd_size: int = 1000
## Сколько стрел держать в полёте сквозь толпу. 0 — замер без стрел для сравнения.
@export var arrow_counts: Array[int] = [0, 100, 1000]
@export var death_counts: Array[int] = [100, 500]
@export var frames_after_death: int = 60

@export_group("Низкий FPS")
@export var low_fps_crowd: int = 200
@export var low_fps_delays_ms: Array[int] = [0, 20, 50, 100]
## Шагов физики за кадр. 0 — как в настройках проекта.
@export var low_fps_steps: Array[int] = [0, 2, 1]
## Толпа для перегрузки без искусственной задержки. 0 — пропустить.
@export var overload_crowd: int = 1000
## Реальных секунд на одно окно.
@export var low_fps_seconds: float = 10.0

@export_group("Долгий бой")
@export var long_fight_minutes: float = 30.0
@export var long_fight_row_seconds: float = 10.0
## Кап спавнера. 0 — как в игре.
@export var long_fight_cap: int = 0
## Брать первую карточку в каждом окне уровня. Выключено — окна не появляются.
@export var long_fight_upgrades: bool = true
## Игрок ходит по кругу, как при кайтинге.
@export var long_fight_walk: bool = true

@export_group("Общее")
## Игровых секунд разгона перед замером: толпа сходится к игроку.
@export var warm_seconds: float = 10.0
## Игровых секунд одного окна замера.
@export var measure_seconds: float = 20.0
## Предел реального времени на окно замера; на разгон — половина.
@export var wall_limit_seconds: float = 60.0
@export var camera_zoom: float = 1.0
@export var stress_seed: int = 7
@export var quit_when_done: bool = false
## Толпу считает ядро на C++ (Horde.native_core). Выключи, чтобы сравнить с GDScript.
## Чем считали на самом деле, пишет заголовок CSV: core=C++ или core=GDScript.
@export var native_core: bool = true


## Метка конца скриптов: последний узел в физике и в процессе.
class EdgeNode extends Node:
	var on_physics_end: Callable
	var on_process_end: Callable

	func _physics_process(_delta: float) -> void:
		on_physics_end.call()

	func _process(_delta: float) -> void:
		on_process_end.call()


## Стрелок без тела и без цели: его снаряды летят сквозь всех.
class StressShooter extends Actor:
	func get_target_group() -> StringName:
		return &"stress_nobody"


## Одно окно замера: целые кадры от границы до границы.
class Span extends RefCounted:
	var kind := ""
	var load_desc := ""
	var note := ""
	var wall0_us := 0
	var frames := 0
	var tick_frames := 0
	var ticks := 0
	var frame_ms := PackedFloat64Array()
	var parts := PackedFloat64Array()
	var gpu_ms := 0.0
	var draws := 0.0
	var phys_objects := 0.0
	var phys_pairs := 0.0
	var overlaps := 0.0
	var touching := 0.0
	var counters := {}
	var damage0 := 0.0
	var kills0 := 0
	var targets_max := 0


var _current: int = Scenario.RAMP
var _csv_path := ""
var _suite_left: Array = []
var _project_max_steps := 8
var _draw_signals := false
var _viewport_rid: RID

var _main: Node
var _player: Player
# У спавнера и окна уровня нет class_name: поля берутся по имени.
var _spawner
var _horde: Horde
var _effects: EffectTable
var _gem_field: Gems
var _level_ui
var _spawn_timer: Timer
var _edge: EdgeNode
var _label: Label
var _shooter: StressShooter
var _arrow_weapon: ProjectileWeaponData

# Нагрузка, которую держит _physics_process.
var _arrow_target := 0
var _walking := false
var _walk_angle := 0.0
var _delay_ms := 0

# Счётчики с начала сценария; окно берёт разницу.
var _c := {
	"fires": 0, "shots": 0, "deaths": 0, "corpse_hits": 0, "dead_shots": 0,
	"proj_hit": 0, "proj_multi": 0, "proj_targets": 0,
	"xp_dropped": 0, "level_signals": 0, "windows": 0,
}
var _game_ticks := 0
var _projectiles_alive := 0
var _arrows_alive := 0
var _zones_alive := 0
var _proj_kind := {}   # id снаряда -> 1 игрок, 2 стрела стрелка, 0 прочие
var _proj_hits := {}   # id снаряда игрока -> сколько целей задел
var _xp0 := 0
var _level0 := 1
var _spawn_index := 0
var _span: Span = null
var _last_frames := PackedFloat64Array()
var _abort := ""

# Кадр по частям: метки времени в микросекундах.
var _f_start := 0
var _f_first := 0
var _tick_start := 0
var _tick_end := 0
var _f_scripts := 0
var _f_step := 0
var _f_ticks := 0
var _f_proc_start := 0
var _f_proc_end := 0
var _f_draw_start := 0
var _f_delay := 0

# Экран: скользящие средние и счётчики за последнюю четверть секунды.
var _phase := ""
var _ema_frame := 0.0
var _ema_parts := PackedFloat64Array()
var _ui_frames := 0
var _ui_ticks := 0
var _ui_t0 := 0
var _ui_fps := 0.0
var _ui_speed := 0.0
var _ui_max := 0.0
var _done_text := ""


func _ready() -> void:
	_apply_cmdline()
	_pick_scenario()
	seed(stress_seed)
	_project_max_steps = ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)
	Engine.max_physics_steps_per_frame = _project_max_steps
	_main = MAIN_SCENE.instantiate()
	# До add_child: Horde выбирает ядро в своём _ready.
	(_main.get_node("Horde") as Horde).native_core = native_core
	add_child(_main)
	_player = _main.get_node("Scene/Player")
	_spawner = _main.get_node("Spawner")
	_horde = _main.get_node("Horde")
	_effects = _main.get_node("EffectTable")
	_gem_field = _main.get_node("Gems")
	_spawn_timer = _spawner.get_node("Timer")
	_level_ui = _main.get_node("LevelUpUI")
	_ema_parts.resize(PART_COUNT)
	_setup_game()
	_setup_probes()
	_setup_overlay()
	_run()


## Сюита идёт сценарий за сценарием через перезагрузку сцены; очередь и файл ждут в Engine.
func _pick_scenario() -> void:
	if scenario != Scenario.SUITE:
		_current = scenario
		_csv_path = _new_csv_path(NAMES[_current])
		return
	if not Engine.has_meta(&"stress_suite_left"):
		Engine.set_meta(&"stress_suite_left", SUITE_ORDER.duplicate())
		Engine.set_meta(&"stress_suite_csv", _new_csv_path("suite"))
	_suite_left = Engine.get_meta(&"stress_suite_left")
	_csv_path = Engine.get_meta(&"stress_suite_csv")
	_current = _suite_left.pop_front() if not _suite_left.is_empty() else Scenario.RAMP
	Engine.set_meta(&"stress_suite_left", _suite_left)


func _setup_game() -> void:
	_spawn_timer.stop()
	_player.max_health = IMMORTAL_HP
	_player.heal_to_full()
	_player.run_ended.connect(func(_k: int, _t: float, _l: int) -> void: _abort = "игрок погиб")
	_player.leveled_up.connect(func(_p: Player) -> void: _c["level_signals"] += 1)
	for timer in _player.weapon_timers:
		timer.timeout.connect(func() -> void: _c["fires"] += 1)
	# Окно уровня ставит паузу посреди замера: выключаем, кроме долгого боя с апгрейдами.
	if not (_current == Scenario.LONG_FIGHT and long_fight_upgrades):
		_level_ui.upgrade_pool.clear()
	var camera: Camera2D = _player.get_node_or_null("Camera2D")
	if camera != null:
		camera.zoom = Vector2.ONE * camera_zoom
	_xp0 = _player.current_xp
	_level0 = _player.level
	_arrow_weapon = ARROW_WEAPON.duplicate()
	_arrow_weapon.lifetime = 1.5
	_shooter = StressShooter.new()
	var shooter_sprite := Sprite2D.new()
	shooter_sprite.name = "Sprite2D"
	_shooter.add_child(shooter_sprite)
	add_child(_shooter)


func _setup_probes() -> void:
	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	_horde.died.connect(_on_enemy_died)
	tree.physics_frame.connect(_on_physics_frame)
	tree.process_frame.connect(_on_process_frame)
	_draw_signals = DisplayServer.get_name() != "headless"
	if not _draw_signals:
		# Без окна движок спит между кадрами, как в режиме экономии: сон попал бы в кадр.
		OS.low_processor_usage_mode_sleep_usec = 0
	else:
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
		RenderingServer.frame_post_draw.connect(_on_post_draw)
		# Без вертикальной синхронизации и лимита: кадр показывает работу, а не ожидание экрана.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_viewport_rid = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_edge = EdgeNode.new()
	_edge.name = "StressEdge"
	_edge.process_mode = Node.PROCESS_MODE_ALWAYS
	_edge.process_priority = 1000000
	_edge.process_physics_priority = 1000000
	_edge.on_physics_end = _on_physics_end
	_edge.on_process_end = _on_process_end
	add_child(_edge)


func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_label = Label.new()
	_label.position = Vector2(8, 28)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_label)
	add_child(layer)


# ---------------------------------------------------------------- сценарии

func _run() -> void:
	await get_tree().process_frame
	_write_header()
	match _current:
		Scenario.RAMP:
			await _run_ramp()
		Scenario.PROJECTILES:
			await _run_projectiles()
		Scenario.MASS_DEATH:
			await _run_mass_death()
		Scenario.LOW_FPS:
			await _run_low_fps()
		Scenario.LONG_FIGHT:
			await _run_long_fight()
	_finish()


## Лестница: толпа растёт ступенями, оружие стреляет как в игре, враги бессмертны.
## Один шаг физики за кадр: время кадра — цена одного игрового кадра.
func _run_ramp() -> void:
	Engine.max_physics_steps_per_frame = 1
	for count in ramp_steps:
		_set_crowd(count)
		await _warm("%d врагов" % count, warm_seconds)
		var row := await _measure("ramp", "enemies=%d" % count, measure_seconds, wall_limit_seconds)
		var stop: bool = row["frame_avg_ms"] > stop_frame_ms
		if stop:
			row["note"] = _join_note(row["note"], "дальше не идём: кадр %.0f мс > %.0f" % [row["frame_avg_ms"], stop_frame_ms])
		_write_row(row)
		if stop or _abort != "":
			break


## Снаряды: толпа и N стрел в полёте сквозь неё. Стрелы ни в кого не попадают.
func _run_projectiles() -> void:
	Engine.max_physics_steps_per_frame = 1
	_set_crowd(crowd_size)
	await _warm("%d врагов" % crowd_size, warm_seconds)
	for count in arrow_counts:
		_arrow_target = count
		await _warm("%d стрел" % count, 3.0)
		_write_row(await _measure("projectiles", "arrows=%d" % count, measure_seconds, wall_limit_seconds))
		if _abort != "":
			break
	_arrow_target = 0


## Массовая смерть: в одном шаге физики гибнут N врагов из толпы, замер кадра смерти и следующих.
func _run_mass_death() -> void:
	Engine.max_physics_steps_per_frame = 1
	for count in death_counts:
		_set_crowd(crowd_size)
		await _warm("%d врагов" % crowd_size, warm_seconds)
		_write_row(await _measure("death_before", "deaths=0", 0.0, wall_limit_seconds, frames_after_death))
		_phase = "гибнут %d" % count
		await frame_ended
		_open_span("death", "deaths=%d" % count)
		await get_tree().physics_frame
		var victims := Array(_horde.alive_rows())
		victims.shuffle()
		victims.resize(mini(count, victims.size()))
		# Наше убийство не урон оружия: здоровье бессмертных, снятое циклом, в урон не идёт.
		# Счётчик возвращаем, а не вычитаем: миллиарды в сумме съели бы точность урона.
		var dealt := _horde.damage_dealt
		var kill_start := Time.get_ticks_usec()
		for t: int in victims:
			_horde.hurt(t, IMMORTAL_HP * 1000.0)
		var kill_ms := (Time.get_ticks_usec() - kill_start) / 1000.0
		_horde.damage_dealt = dealt
		while _span.tick_frames < 1 + frames_after_death and _abort == "":
			await frame_ended
		var row := _close_span()
		await get_tree().process_frame
		var first: PackedStringArray = []
		for i in mini(3, _last_frames.size()):
			first.append("%.1f" % _last_frames[i])
		row["note"] = _join_note(row["note"], "цикл убийств %.1f мс; первые кадры %s мс" % [kill_ms, " / ".join(first)])
		_write_row(row)
		if _abort != "":
			break


## Низкий FPS: искусственная задержка в кадре и разные лимиты шагов физики,
## потом перегрузка настоящей толпой. Окна — по реальному времени.
func _run_low_fps() -> void:
	Engine.max_physics_steps_per_frame = 1
	_set_crowd(low_fps_crowd)
	await _warm("%d врагов" % low_fps_crowd, warm_seconds)
	for steps in low_fps_steps:
		for delay in low_fps_delays_ms:
			await _low_fps_window("lowfps", low_fps_crowd, delay, steps)
	if overload_crowd > 0 and _abort == "":
		Engine.max_physics_steps_per_frame = 1
		_set_crowd(overload_crowd)
		await _warm("%d врагов" % overload_crowd, warm_seconds)
		for steps in low_fps_steps:
			await _low_fps_window("overload", overload_crowd, 0, steps)
	_delay_ms = 0
	Engine.max_physics_steps_per_frame = _project_max_steps


func _low_fps_window(kind: String, crowd: int, delay: int, steps: int) -> void:
	if _abort != "":
		return
	var real_steps := steps if steps > 0 else _project_max_steps
	Engine.max_physics_steps_per_frame = real_steps
	_delay_ms = delay
	var load_desc := "enemies=%d delay=%dms steps=%d" % [crowd, delay, real_steps]
	_phase = load_desc
	await _wait_wall(1.0)
	_write_row(await _measure(kind, load_desc, 0.0, low_fps_seconds))


## Долгий бой: обычный спавн и смерти, строка раз в long_fight_row_seconds игрового времени.
func _run_long_fight() -> void:
	if long_fight_cap > 0 and "max_alive" in _spawner:
		_spawner.max_alive = long_fight_cap
	_spawn_timer.start()
	_walking = long_fight_walk
	var rows := ceili(long_fight_minutes * 60.0 / long_fight_row_seconds)
	for i in rows:
		var row_time := (i + 1) * long_fight_row_seconds
		_write_row(await _measure("long", "t=%ds" % int(row_time), long_fight_row_seconds, 1.0e6))
		if _abort != "":
			break
	_walking = false
	_press_direction(Vector2.ZERO)
	_spawn_timer.stop()


func _finish() -> void:
	_arrow_target = 0
	_delay_ms = 0
	Engine.max_physics_steps_per_frame = _project_max_steps
	if _abort != "":
		_append_line("# прервано: " + _abort)
	if scenario == Scenario.SUITE and not _suite_left.is_empty() and _abort == "":
		get_tree().reload_current_scene()
		return
	Engine.remove_meta(&"stress_suite_left")
	Engine.remove_meta(&"stress_suite_csv")
	var path := ProjectSettings.globalize_path(_csv_path)
	_done_text = "Готово. Отчёт: " + path
	print("[stress] готово: ", path)
	_update_overlay()
	if quit_when_done:
		get_tree().quit()
	else:
		get_tree().paused = true


# ---------------------------------------------------------------- нагрузка

## Добирает бессмертных врагов до count на кольце 150–900 px вокруг игрока.
## Убийства идут в счёт игрока через спавнер: он подписан на Horde.died.
func _set_crowd(count: int) -> void:
	var pool: Array = _spawner.enemy_pool.filter(func(data: EnemyData) -> bool: return data != null)
	var missing := count - _horde.alive_count()
	for i in missing:
		var data: EnemyData = pool[_spawn_index % pool.size()]
		_spawn_index += 1
		var t := _horde.spawn(data, _player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(150.0, 900.0))
		_horde.set_health(t, IMMORTAL_HP)


func _physics_process(delta: float) -> void:
	_shooter.global_position = _player.global_position
	for i in _arrow_target - _arrows_alive:
		_arrow_weapon.spawn_projectile(_shooter, Vector2.from_angle(randf() * TAU))
	if _walking:
		# Круг радиусом около 400 px при скорости игрока 200.
		_walk_angle += delta * 0.5
		_press_direction(Vector2.from_angle(_walk_angle + PI * 0.5))


func _press_direction(direction: Vector2) -> void:
	_press(&"move_right", direction.x)
	_press(&"move_left", -direction.x)
	_press(&"move_down", direction.y)
	_press(&"move_up", -direction.y)


func _press(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


# ---------------------------------------------------------------- ожидание и окна

func _warm(what: String, seconds: float) -> void:
	_phase = "%s · разгон" % what
	await _wait_game(seconds, wall_limit_seconds * 0.5)


func _wait_game(seconds: float, wall_cap: float) -> void:
	var target := _game_ticks + int(seconds * Engine.physics_ticks_per_second)
	var deadline := Time.get_ticks_msec() + int(wall_cap * 1000.0)
	while _game_ticks < target and Time.get_ticks_msec() < deadline and _abort == "":
		await get_tree().process_frame


func _wait_wall(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and _abort == "":
		await get_tree().process_frame


## Окно замера из целых кадров. Конец — что наступит раньше: game_seconds игрового
## времени (0 — без предела), tick_frames кадров с шагом физики (0 — без предела)
## или wall_seconds реального времени.
func _measure(kind: String, load_desc: String, game_seconds: float, wall_seconds: float, tick_frames := 0) -> Dictionary:
	_phase = load_desc
	await frame_ended
	_open_span(kind, load_desc)
	var target_ticks := int(game_seconds * Engine.physics_ticks_per_second)
	var deadline := Time.get_ticks_msec() + int(wall_seconds * 1000.0)
	var limited := game_seconds > 0.0 or tick_frames > 0
	while _abort == "":
		await frame_ended
		if tick_frames > 0 and _span.tick_frames >= tick_frames:
			break
		if game_seconds > 0.0 and _span.ticks >= target_ticks:
			break
		if Time.get_ticks_msec() >= deadline:
			if limited:
				_span.note = "предел времени %.0f с" % wall_seconds
			break
	var row := _close_span()
	# Дальше сценарий меняет мир: не из сигнала отрисовки, а в обычном кадре.
	await get_tree().process_frame
	return row


func _open_span(kind: String, load_desc: String) -> void:
	_span = Span.new()
	_span.kind = kind
	_span.load_desc = load_desc
	_span.wall0_us = Time.get_ticks_usec()
	_span.parts.resize(PART_COUNT)
	_span.counters = _c.duplicate()
	_span.damage0 = _damage_total()
	_span.kills0 = _player.kills


func _close_span() -> Dictionary:
	var s := _span
	_span = null
	_last_frames = s.frame_ms
	var tps := float(Engine.physics_ticks_per_second)
	var wall_s := (Time.get_ticks_usec() - s.wall0_us) / 1.0e6
	var game_s := s.ticks / tps
	var tick_frames := maxi(s.tick_frames, 1)
	var sorted := s.frame_ms.duplicate()
	sorted.sort()
	var frame_sum := 0.0
	for value in sorted:
		frame_sum += value
	var enemies := _horde.alive_rows()
	var stacks := 0
	var stacks_max := 0
	for t in enemies:
		var count := _effects.stack_count(t)
		stacks += count
		stacks_max = maxi(stacks_max, count)
	var diff := {}
	for key in _c:
		diff[key] = _c[key] - s.counters[key]
	var hit: int = diff["proj_hit"]
	var xp_on_map := _gem_field.xp_on_map()
	var xp_picked := _player.current_xp - _xp0
	var fires_expected := 0.0
	for timer in _player.weapon_timers:
		fires_expected += 1.0 / timer.wait_time
	var row := {
		"scenario": NAMES[_current], "window": s.kind, "load": s.load_desc,
		"enemies": enemies.size(), "wall_s": wall_s, "game_s": game_s, "game_speed": game_s / maxf(wall_s, 0.001),
		"frames": s.frames, "tick_frames": s.tick_frames, "fps": s.frames / maxf(wall_s, 0.001),
		"steps_per_frame": s.ticks / float(maxi(s.frames, 1)),
		"frame_avg_ms": frame_sum / tick_frames,
		"frame_p99_ms": sorted[int(0.99 * (sorted.size() - 1))] if sorted.size() > 0 else 0.0,
		"frame_max_ms": sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0,
		"pre_ms": s.parts[0] / tick_frames, "phys_scripts_ms": s.parts[1] / tick_frames,
		"phys_step_ms": s.parts[2] / tick_frames, "process_ms": s.parts[3] / tick_frames,
		"late_ms": s.parts[4] / tick_frames, "render_ms": s.parts[5] / tick_frames, "delay_ms": s.parts[6] / tick_frames,
		"gpu_ms": s.gpu_ms / tick_frames, "draw_calls": s.draws / tick_frames,
		"phys_objects": s.phys_objects / tick_frames, "phys_pairs": s.phys_pairs / tick_frames,
				"crowd_overlaps": s.overlaps / tick_frames, "touching": s.touching / tick_frames,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"projectiles": _projectiles_alive, "arrows": _arrows_alive, "zones": _zones_alive, "gems": _gem_field.count(),
		"stacks_per_enemy": stacks / float(maxi(enemies.size(), 1)), "stacks_max": stacks_max,
		"fires_per_s": diff["fires"] / maxf(game_s, 0.001), "fires_expected_per_s": fires_expected,
		"fires_per_real_s": diff["fires"] / maxf(wall_s, 0.001), "shots_per_s": diff["shots"] / maxf(game_s, 0.001),
		"targets_avg": diff["proj_targets"] / float(maxi(hit, 1)), "targets_max": s.targets_max,
		"multi_share": diff["proj_multi"] / float(maxi(hit, 1)),
		"corpse_hits": diff["corpse_hits"], "dead_shots": diff["dead_shots"],
		"deaths": diff["deaths"], "kills": _player.kills - s.kills0,
		"damage_per_s": (_damage_total() - s.damage0) / maxf(game_s, 0.001),
		"xp_dropped": _c["xp_dropped"], "xp_picked": xp_picked, "xp_on_map": xp_on_map,
		"xp_lost": _c["xp_dropped"] - xp_picked - xp_on_map,
		"levels": _player.level - _level0, "level_signals": _c["level_signals"], "windows": _c["windows"],
		"note": _join_note(s.note, _abort),
	}
	return row


## Урон врагам с начала сценария: потерянное здоровье живых и ушедших (Horde.damage_dealt).
## Наше убийство в массовой смерти в него не входит, перебор при смерти тоже.
func _damage_total() -> float:
	return _horde.damage_dealt


# ---------------------------------------------------------------- кадр по частям

func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	if _tick_end > 0:
		_f_step += now - _tick_end
		_tick_end = 0
	if _f_first == 0:
		_f_first = now
	_tick_start = now


func _on_physics_end() -> void:
	var now := Time.get_ticks_usec()
	if _tick_start > 0:
		_f_scripts += now - _tick_start
		_tick_start = 0
		if not get_tree().paused:
			_f_ticks += 1
			_game_ticks += 1
	_tick_end = now


func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	if _tick_end > 0:
		_f_step += now - _tick_end
		_tick_end = 0
	if _f_first == 0:
		_f_first = now
	_f_proc_start = now


func _on_process_end() -> void:
	_f_proc_end = Time.get_ticks_usec()
	_auto_pick_upgrade()
	if Time.get_ticks_msec() - _ui_t0 >= 250:
		_update_overlay()
	if not _draw_signals:
		_end_frame(_f_proc_end)
	if _delay_ms > 0:
		var delay_start := Time.get_ticks_usec()
		OS.delay_usec(_delay_ms * 1000)
		_f_delay += Time.get_ticks_usec() - delay_start


func _on_pre_draw() -> void:
	_f_draw_start = Time.get_ticks_usec()


func _on_post_draw() -> void:
	_end_frame(Time.get_ticks_usec())


## Граница кадра: от прошлой границы до этой ровно один кадр.
## Части: до физики (сигналы физики, ввод), скрипты физики, шаг физики сервера,
## процесс (_process и таймеры-узлы: выстрелы оружия), после процесса (таймеры дерева,
## удаление узлов), отрисовка. Без окна (headless) отрисовка и «после» уходят в «до физики».
func _end_frame(now: int) -> void:
	if _f_start > 0:
		var frame_us := now - _f_start
		var first := _f_first if _f_first > 0 else now
		var late_us := 0
		var render_us := 0
		if _draw_signals and _f_draw_start > _f_proc_end:
			late_us = _f_draw_start - _f_proc_end - _f_delay
			render_us = now - _f_draw_start
		var parts := PackedFloat64Array([
			(first - _f_start) / 1000.0, _f_scripts / 1000.0, _f_step / 1000.0,
			(_f_proc_end - _f_proc_start) / 1000.0, late_us / 1000.0, render_us / 1000.0, _f_delay / 1000.0,
		])
		if not _draw_signals:
			parts[0] -= parts[6]
		_account_frame(frame_us / 1000.0, parts)
	_f_start = now
	_f_first = 0
	_f_scripts = 0
	_f_step = 0
	_f_ticks = 0
	_f_delay = 0
	frame_ended.emit()


func _account_frame(frame_ms: float, parts: PackedFloat64Array) -> void:
	_ui_frames += 1
	_ui_ticks += _f_ticks
	if _f_ticks > 0:
		_ema_frame = lerpf(_ema_frame, frame_ms, 0.1)
		for i in PART_COUNT:
			_ema_parts[i] = lerpf(_ema_parts[i], parts[i], 0.1)
		_ui_max = maxf(_ui_max, frame_ms)
	if _span == null:
		return
	_span.frames += 1
	_span.ticks += _f_ticks
	if _f_ticks == 0:
		return
	_span.tick_frames += 1
	_span.frame_ms.append(frame_ms)
	for i in PART_COUNT:
		_span.parts[i] += parts[i]
	if _draw_signals:
		_span.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
		_span.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_span.phys_objects += Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	_span.phys_pairs += Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	_span.overlaps += _horde.overlaps / float(maxi(_horde.registry_size(), 1))
	_span.touching += _horde.touching_player


# ---------------------------------------------------------------- счётчики корректности

func _on_node_added(node: Node) -> void:
	if node is Projectile:
		_on_projectile_added(node)
	elif node.get_script() == ZONE_SCRIPT:
		_zones_alive += 1
		if node.owner_actor == _player:
			_c["shots"] += 1
		node.tree_exiting.connect(func() -> void: _zones_alive -= 1, CONNECT_ONE_SHOT)


func _on_projectile_added(projectile: Projectile) -> void:
	var id := projectile.get_instance_id()
	var kind := 0
	if projectile.owner_actor == _player:
		kind = 1
		_c["shots"] += 1
		_proj_hits[id] = 0
		# Снаряд сам сообщает о каждом ударе, до урона (шаг 1).
		projectile.hit.connect(_on_player_projectile_hit.bind(projectile))
	elif projectile.owner_actor == _shooter:
		kind = 2
		_arrows_alive += 1
	elif projectile.owner_row >= 0 and _horde.is_dead(projectile.owner_row):
		_c["dead_shots"] += 1
	_proj_kind[id] = kind
	_projectiles_alive += 1
	projectile.tree_exiting.connect(_on_projectile_exiting.bind(id), CONNECT_ONE_SHOT)


func _on_player_projectile_hit(target: int, projectile: Projectile) -> void:
	_proj_hits[projectile.get_instance_id()] += 1
	if _horde.is_dead(target):
		_c["corpse_hits"] += 1


func _on_projectile_exiting(id: int) -> void:
	_projectiles_alive -= 1
	var kind: int = _proj_kind.get(id, 0)
	_proj_kind.erase(id)
	if kind == 2:
		_arrows_alive -= 1
	elif kind == 1:
		var hits: int = _proj_hits.get(id, 0)
		_proj_hits.erase(id)
		if hits > 0:
			_c["proj_hit"] += 1
			_c["proj_targets"] += hits
			if hits > 1:
				_c["proj_multi"] += 1
			if _span != null:
				_span.targets_max = maxi(_span.targets_max, hits)


func _on_enemy_died(target: int) -> void:
	_c["deaths"] += 1
	var data := _horde.data_of(target)
	if data.gem_scene != null:
		_c["xp_dropped"] += data.xp_reward


## Долгий бой с апгрейдами: окно уровня сразу берёт первую карточку.
func _auto_pick_upgrade() -> void:
	if not get_tree().paused or not _level_ui.visible or _done_text != "":
		return
	for button: Button in _level_ui.find_children("*", "Button", true, false):
		if button.visible:
			button.pressed.emit()
			_c["windows"] += 1
			return


# ---------------------------------------------------------------- экран

func _update_overlay() -> void:
	var now := Time.get_ticks_msec()
	var elapsed := (now - _ui_t0) / 1000.0
	if elapsed > 0.0 and _ui_t0 > 0:
		_ui_fps = _ui_frames / elapsed
		_ui_speed = _ui_ticks / (elapsed * Engine.physics_ticks_per_second)
	_ui_t0 = now
	_ui_frames = 0
	_ui_ticks = 0
	var lines: PackedStringArray = []
	lines.append("СТРЕСС · %s · %s" % [TITLES[_current], _phase])
	lines.append("кадр %.1f мс (макс %.1f) · %.0f к/с · скорость игры %.2f" % [_ema_frame, _ui_max, _ui_fps, _ui_speed])
	lines.append("до физики %.1f · скрипты физики %.1f · шаг физики %.1f · процесс %.1f · после %.1f · отрисовка %.1f" % [
		_ema_parts[0], _ema_parts[1], _ema_parts[2], _ema_parts[3], _ema_parts[4], _ema_parts[5]])
	lines.append("врагов %d · снарядов %d (стрел %d) · зон %d · гемов %d" % [
		_horde.alive_count(), _projectiles_alive, _arrows_alive, _zones_alive, _gem_field.count()])
	var hit: int = _c["proj_hit"]
	lines.append("целей на снаряд %.2f · по мёртвым %d · выстрелов мёртвых %d" % [
		_c["proj_targets"] / float(maxi(hit, 1)), _c["corpse_hits"], _c["dead_shots"]])
	if _done_text != "":
		lines.append(_done_text)
	_label.text = "\n".join(lines)
	_ui_max = 0.0


# ---------------------------------------------------------------- отчёт

func _new_csv_path(prefix: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://stress")
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	return "user://stress/%s_%s.csv" % [prefix, stamp]


func _write_header() -> void:
	if FileAccess.file_exists(_csv_path):
		return
	var version: Dictionary = Engine.get_version_info()
	var window := DisplayServer.window_get_size()
	var view := get_viewport().get_visible_rect().size
	var build := "editor" if OS.has_feature("editor") else ("debug" if OS.is_debug_build() else "release")
	var file := FileAccess.open(_csv_path, FileAccess.WRITE)
	file.store_line("# stress_test | %s | scenario=%s | seed=%d | core=%s" % [
		Time.get_datetime_string_from_system(false, true), NAMES[scenario], stress_seed,
		"C++" if _horde.uses_native_core() else "GDScript"])
	file.store_line("# godot=%s | build=%s | os=%s %s | cpu=%s | cores=%d" % [
		version["string"], build, OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count()])
	file.store_line("# gpu=%s | vendor=%s | api=%s | renderer=%s | driver=%s | window=%dx%d | view=%dx%d | zoom=%.2f" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), window.x, window.y, view.x, view.y, camera_zoom])
	file.store_line("# physics_tps=%d | max_steps_project=%d | vsync=%s | ramp/projectiles/death: 1 шаг физики за кадр" % [
		Engine.physics_ticks_per_second, _project_max_steps, "off" if _draw_signals else "headless"])
	file.store_line(",".join(COLUMNS))
	file.close()


func _write_row(row: Dictionary) -> void:
	var cells: PackedStringArray = []
	for column in COLUMNS:
		var value: Variant = row.get(column, "")
		if value is float:
			cells.append("%.3f" % value)
		elif value is String:
			cells.append("\"%s\"" % value.replace("\"", "'") if value.contains(",") else value)
		else:
			cells.append(str(value))
	_append_line(",".join(cells))
	print("[stress] %s %s | кадр %.1f мс (p99 %.1f, макс %.1f) | до физики %.1f, скрипты физики %.1f, шаг %.1f, процесс %.1f, после %.1f, отрисовка %.1f | скорость игры %.2f | целей на снаряд %.2f (макс %d) | по мёртвым %d | %s" % [
		row["window"], row["load"], row["frame_avg_ms"], row["frame_p99_ms"], row["frame_max_ms"],
		row["pre_ms"], row["phys_scripts_ms"], row["phys_step_ms"], row["process_ms"], row["late_ms"], row["render_ms"],
		row["game_speed"], row["targets_avg"], row["targets_max"], row["corpse_hits"], row["note"]])


func _append_line(line: String) -> void:
	var file := FileAccess.open(_csv_path, FileAccess.READ_WRITE)
	if file == null:
		push_error("stress: не открыть %s" % _csv_path)
		return
	file.seek_end()
	file.store_line(line)
	file.close()


func _join_note(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a + "; " + b


# ---------------------------------------------------------------- запуск из командной строки

## Для запуска без редактора: godot --path . res://scenes/debug/stress_test.tscn -- scenario=ramp steps=100,500
func _apply_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		var value := pair[1]
		match pair[0]:
			"scenario": scenario = maxi(NAMES.find(value), 0) as Scenario
			"steps": ramp_steps = _ints(value)
			"stop": stop_frame_ms = value.to_float()
			"crowd": crowd_size = value.to_int()
			"arrows": arrow_counts = _ints(value)
			"deaths": death_counts = _ints(value)
			"after": frames_after_death = value.to_int()
			"lowcrowd": low_fps_crowd = value.to_int()
			"delays": low_fps_delays_ms = _ints(value)
			"lowsteps": low_fps_steps = _ints(value)
			"overload": overload_crowd = value.to_int()
			"lowsecs": low_fps_seconds = value.to_float()
			"minutes": long_fight_minutes = value.to_float()
			"row": long_fight_row_seconds = value.to_float()
			"cap": long_fight_cap = value.to_int()
			"upgrades": long_fight_upgrades = value == "1"
			"walk": long_fight_walk = value == "1"
			"warm": warm_seconds = value.to_float()
			"measure": measure_seconds = value.to_float()
			"wall": wall_limit_seconds = value.to_float()
			"zoom": camera_zoom = value.to_float()
			"seed": stress_seed = value.to_int()
			"quit": quit_when_done = value == "1"
			"native": native_core = value == "1"


func _ints(text: String) -> Array[int]:
	var out: Array[int] = []
	for part in text.split(",", false):
		out.append(part.to_int())
	return out
