#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shape2d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// Ядро снарядов Shots (срез С5): поиск целей, полёт и буферы отрисовки, каждое за один вызов.
// Это Horde.query_hits и Shots._fly, переписанные строка в строку: те же формулы, те же типы
// чисел, тот же порядок. Удары (урон, крит, эффекты, реакции) остаются в Shots на GDScript:
// query отдаёт им список попаданий.
//
// Числа как в GDScript и в HordeCore: Vector2 — float (32 бита), отдельное число — double.
// Косинус волны (UtilityFunctions::cos) и проверку фигуры (Shape2D::collide) ядро зовёт
// из движка: они те же до бита, что у GDScript, на любой ОС.
//
// Массивы Shots и Horde приходят на вызов и только читаются. Полёт считает pos, travel_time,
// age и порядок в свои копии, Shots забирает их себе (get() отдаёт ссылку, без копирования).
class ShotsCore : public RefCounted {
	GDCLASS(ShotsCore, RefCounted)

public:
	// Режимы полёта и биты «кого бьёт» — те же числа, что TrajectoryData.Move и Shots._flags.
	enum {
		MOVE_STRAIGHT = 0,
		MOVE_WAVE = 1,
		MOVE_SCRIPT = 2,
	};
	enum {
		HITS_ENEMIES = 1,
		HITS_PLAYER = 2,
	};

	// Цели поиска — всё, по чему ищет Horde.query_hits: снимок позиций, радиусы попаданий,
	// убитые, generation, сетка (если grid), игрок (если player) и круг радиусом 1 для
	// collide(). Даёт Horde.lend_targets; ядро держит их до конца ближайшего query.
	void set_targets(const PackedVector2Array &p_snap, const PackedFloat32Array &p_hit_radius,
			const PackedByteArray &p_dead, const PackedInt32Array &p_gen,
			const PackedInt32Array &p_cell_count, const PackedInt32Array &p_cell_start,
			const PackedInt32Array &p_sorted, const Vector2 &p_origin, int64_t p_grid_w, int64_t p_grid_h,
			double p_inv_cell, double p_max_hit_radius, bool p_grid, bool p_player,
			const Vector2 &p_player_pos, double p_player_radius, const Ref<Shape2D> &p_unit_circle);

	// Кого задевает каждый снаряд из order[0 .. count), кроме выпущенных в шаге frame:
	// Horde.query_hits для всех разом. Ответ — сколько снарядов в списке events: по пять
	// чисел на снаряд (место в порядке, номер, начало его целей в targets, их число,
	// 1 — список обрезан пределом целей). Туда же попадают снаряды режима SCRIPT без целей:
	// их полёт ведёт Shots в их черёд.
	int64_t query(const PackedInt32Array &p_order, int64_t p_count, int64_t p_frame,
			const PackedInt64Array &p_born, const PackedVector2Array &p_pos, const PackedByteArray &p_flags,
			const PackedInt32Array &p_limit, const PackedInt32Array &p_owner_row,
			const PackedInt32Array &p_owner_gen, const PackedFloat64Array &p_radius,
			const PackedFloat64Array &p_bound, const PackedVector2Array &p_basis,
			const PackedInt32Array &p_shape, const Array &p_shapes, const PackedByteArray &p_move);

	// Полёт снарядов порядка до места stop, кроме ушедших (done), выпущенных в шаге frame
	// и режима SCRIPT: шаг по траектории, потом возраст (Shots._fly). order — порядок
	// без ушедших и без тех, чья жизнь кончилась (они — в expired).
	void move(const PackedInt32Array &p_order, int64_t p_stop, int64_t p_frame, const PackedInt64Array &p_born,
			const PackedByteArray &p_done, const PackedByteArray &p_move, const PackedVector2Array &p_direction,
			const PackedVector2Array &p_side, const PackedFloat64Array &p_speed,
			const PackedFloat64Array &p_amplitude, const PackedFloat64Array &p_frequency,
			const PackedFloat64Array &p_phase, const PackedFloat64Array &p_lifetime,
			const PackedVector2Array &p_pos, const PackedFloat64Array &p_travel_time,
			const PackedFloat64Array &p_age, double p_delta);

	// Буферы MultiMesh по видам (Shots._fill_buffers): снаряды в порядке появления, базис
	// картинки и позиция. capacity — сколько экземпляров у MultiMesh каждого вида.
	void draw(const PackedInt32Array &p_order, const PackedInt32Array &p_kind, const PackedVector2Array &p_view,
			const PackedVector2Array &p_pos, const PackedInt32Array &p_capacity);

	PackedInt32Array get_events() const { return events; }
	PackedInt32Array get_targets() const { return targets; }
	PackedInt32Array get_order() const { return order; }
	PackedVector2Array get_pos() const { return pos; }
	PackedFloat64Array get_travel_time() const { return travel_time; }
	PackedFloat64Array get_age() const { return age; }
	PackedInt32Array get_expired() const { return expired; }
	PackedInt32Array get_counts() const { return counts; }
	Array get_buffers() const { return buffers; }

protected:
	static void _bind_methods();

private:
	// Цели поиска (set_targets).
	bool has_targets = false;
	PackedVector2Array snap;
	PackedFloat32Array hit_radius;
	PackedByteArray dead;
	PackedInt32Array gen;
	PackedInt32Array cell_count;
	PackedInt32Array cell_start;
	PackedInt32Array sorted;
	Vector2 origin;
	int64_t grid_w = 0;
	int64_t grid_h = 0;
	double inv_cell = 0.01;
	double max_hit_radius = 0.0;
	bool grid = false;
	bool player = false;
	Vector2 player_pos;
	double player_radius = 0.0;
	Ref<Shape2D> unit_circle;

	// Итоги вызовов.
	PackedInt32Array events;
	PackedInt32Array targets;
	PackedInt32Array order;
	PackedVector2Array pos;
	PackedFloat64Array travel_time;
	PackedFloat64Array age;
	PackedInt32Array expired;
	PackedInt32Array counts;
	Array buffers;
	std::vector<PackedFloat32Array> kind_buffers;

	// Рабочие списки: цели одного снаряда и квадраты расстояний до них.
	std::vector<int32_t> found;
	std::vector<double> found_d2;
	std::vector<int32_t> event_list;
	std::vector<int32_t> target_list;
	std::vector<int32_t> expired_list;
	std::vector<Shape2D *> shapes;

	void _release_targets();
	void _keep_nearest(int64_t p_limit);
	bool _collide(Shape2D *p_shape, const Vector2 &p_x, const Vector2 &p_y, const Vector2 &p_at,
			const Vector2 &p_center, double p_radius) const;
};

} // namespace godot
