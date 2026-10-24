#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

// Ядро толпы: копия позиций, сетка, расталкивание и касание игрока за один вызов.
// Это функции Horde (_read_positions, _fit_grid, _build_grid, _push_apart, _touch_player),
// переписанные строка в строку: те же формулы, те же типы чисел, тот же порядок.
// Тогда толпа выходит та же до бита, что и на GDScript (horde.gd остаётся запасным путём).
//
// Числа как в GDScript: Vector2 — float (32 бита), отдельное число — double (так в GDScript
// любой float). Поэтому радиусы, массы и расстояния здесь double, а толчок — Vector2.
//
// Массивы строк приходят из Horde и только читаются. Снимок, толчок и сетка — свои массивы
// ядра: Horde забирает их после вызова (Godot отдаёт ссылку на тот же буфер, без копии).
class HordeCore : public RefCounted {
	GDCLASS(HordeCore, RefCounted)

public:
	// Те же числа, что у Horde: INV_CELL = 1.0 / CELL и MAX_CELLS. Зовётся один раз.
	void configure(double p_inv_cell, int64_t p_max_cells);

	// Шаг толпы в начале шага физики Horde. snap и sep_vel — массивы Horde: ядро копирует их
	// и переписывает строки реестра, остальные строки остаются как были.
	void step(const PackedInt32Array &p_reg, const PackedVector2Array &p_pos,
			const PackedVector2Array &p_snap, const PackedVector2Array &p_sep_vel,
			const PackedFloat32Array &p_radius, const PackedFloat32Array &p_mass,
			const PackedFloat32Array &p_response, const PackedFloat32Array &p_max_push,
			const PackedFloat32Array &p_contact_r2, const PackedFloat32Array &p_contact_damage,
			const PackedByteArray &p_dead, const Vector2 &p_player_pos,
			double p_player_radius, double p_player_mass);

	// Сетка для запроса вне шага (Horde._ensure_grid): по снимку Horde, без копии позиций.
	void ensure_grid(const PackedInt32Array &p_reg, const PackedVector2Array &p_snap);

	PackedVector2Array get_snap() const { return snap; }
	PackedVector2Array get_sep_vel() const { return sep_vel; }
	PackedInt32Array get_cell_of() const { return cell_of; }
	PackedInt32Array get_sorted() const { return sorted; }
	PackedInt32Array get_cell_count() const { return cell_count; }
	PackedInt32Array get_cell_start() const { return cell_start; }
	Vector2 get_origin() const { return origin; }
	int64_t get_grid_w() const { return grid_w; }
	int64_t get_grid_h() const { return grid_h; }
	int64_t get_overlaps() const { return overlaps; }
	int64_t get_touching() const { return touching; }
	double get_contact_total() const { return contact_total; }

protected:
	static void _bind_methods();

private:
	double inv_cell = 0.01;
	int64_t max_cells = 64;

	PackedVector2Array snap;
	PackedVector2Array sep_vel;
	// Сетка — сортировка подсчётом, как в Horde: в клетке c лежат
	// sorted[cell_start[c] .. + cell_count[c]]. cell_of — по месту в реестре.
	PackedInt32Array cell_of;
	PackedInt32Array sorted;
	PackedInt32Array cell_count;
	PackedInt32Array cell_start;
	PackedInt32Array cell_fill;
	Vector2 origin;
	int64_t grid_w = 0;
	int64_t grid_h = 0;
	int64_t overlaps = 0;
	int64_t touching = 0;
	double contact_total = 0.0;

	void _fit_grid(const Vector2 &p_lo, const Vector2 &p_hi);
	void _build_grid(const int32_t *p_reg, int64_t p_count, const Vector2 *p_snap, int64_t p_rows);
	void _push_apart(const int32_t *p_reg, int64_t p_count, const float *p_radius, const float *p_mass,
			const float *p_response, const float *p_max_push, const Vector2 &p_player_pos,
			double p_player_radius, double p_player_mass);
	void _touch_player(const int32_t *p_reg, int64_t p_count, const float *p_contact_r2,
			const float *p_contact_damage, const uint8_t *p_dead, const Vector2 &p_player_pos);
};

} // namespace godot
