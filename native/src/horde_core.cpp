#include "horde_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

void HordeCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "inv_cell", "max_cells"), &HordeCore::configure);
	ClassDB::bind_method(D_METHOD("step", "reg", "pos", "snap", "sep_vel", "radius", "mass", "response",
								 "max_push", "contact_r2", "contact_damage", "dead", "player_pos",
								 "player_radius", "player_mass"),
			&HordeCore::step);
	ClassDB::bind_method(D_METHOD("ensure_grid", "reg", "snap"), &HordeCore::ensure_grid);

	ClassDB::bind_method(D_METHOD("get_snap"), &HordeCore::get_snap);
	ClassDB::bind_method(D_METHOD("get_sep_vel"), &HordeCore::get_sep_vel);
	ClassDB::bind_method(D_METHOD("get_cell_of"), &HordeCore::get_cell_of);
	ClassDB::bind_method(D_METHOD("get_sorted"), &HordeCore::get_sorted);
	ClassDB::bind_method(D_METHOD("get_cell_count"), &HordeCore::get_cell_count);
	ClassDB::bind_method(D_METHOD("get_cell_start"), &HordeCore::get_cell_start);
	ClassDB::bind_method(D_METHOD("get_origin"), &HordeCore::get_origin);
	ClassDB::bind_method(D_METHOD("get_grid_w"), &HordeCore::get_grid_w);
	ClassDB::bind_method(D_METHOD("get_grid_h"), &HordeCore::get_grid_h);
	ClassDB::bind_method(D_METHOD("get_overlaps"), &HordeCore::get_overlaps);
	ClassDB::bind_method(D_METHOD("get_touching"), &HordeCore::get_touching);
	ClassDB::bind_method(D_METHOD("get_contact_total"), &HordeCore::get_contact_total);

	// Только для чтения: Horde берёт их через get().
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "snap"), "", "get_snap");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "sep_vel"), "", "get_sep_vel");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "cell_of"), "", "get_cell_of");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "sorted"), "", "get_sorted");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "cell_count"), "", "get_cell_count");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "cell_start"), "", "get_cell_start");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "origin"), "", "get_origin");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "grid_w"), "", "get_grid_w");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "grid_h"), "", "get_grid_h");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "overlaps"), "", "get_overlaps");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "touching"), "", "get_touching");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "contact_total"), "", "get_contact_total");
}

void HordeCore::configure(double p_inv_cell, int64_t p_max_cells) {
	inv_cell = p_inv_cell;
	max_cells = p_max_cells;
	const int64_t cells = max_cells * max_cells;
	cell_count.resize(cells);
	cell_start.resize(cells);
	cell_fill.resize(cells);
}

void HordeCore::step(const PackedInt32Array &p_reg, const PackedVector2Array &p_pos,
		const PackedVector2Array &p_snap, const PackedVector2Array &p_sep_vel,
		const PackedFloat32Array &p_radius, const PackedFloat32Array &p_mass,
		const PackedFloat32Array &p_response, const PackedFloat32Array &p_max_push,
		const PackedFloat32Array &p_contact_r2, const PackedFloat32Array &p_contact_damage,
		const PackedByteArray &p_dead, const Vector2 &p_player_pos,
		double p_player_radius, double p_player_mass) {
	const int64_t count = p_reg.size();
	const int32_t *reg = p_reg.ptr();
	// Копии массивов Horde: первая запись ниже даёт ядру свой буфер с теми же числами.
	snap = p_snap;
	sep_vel = p_sep_vel;

	// _read_positions: позиции начала шага, все толкаются по одному снимку.
	Vector2 *s = snap.ptrw();
	const Vector2 *pos = p_pos.ptr();
	Vector2 lo(INFINITY, INFINITY);
	Vector2 hi(-INFINITY, -INFINITY);
	for (int64_t i = 0; i < count; i++) {
		const int32_t t = reg[i];
		const Vector2 p = pos[t];
		s[t] = p;
		lo = lo.min(p);
		hi = hi.max(p);
	}
	_fit_grid(lo, hi);
	_build_grid(reg, count, s, snap.size());
	_push_apart(reg, count, p_radius.ptr(), p_mass.ptr(), p_response.ptr(), p_max_push.ptr(),
			p_player_pos, p_player_radius, p_player_mass);
	_touch_player(reg, count, p_contact_r2.ptr(), p_contact_damage.ptr(), p_dead.ptr(), p_player_pos);
}

void HordeCore::ensure_grid(const PackedInt32Array &p_reg, const PackedVector2Array &p_snap) {
	const int64_t count = p_reg.size();
	const int32_t *reg = p_reg.ptr();
	const Vector2 *s = p_snap.ptr();
	Vector2 lo(INFINITY, INFINITY);
	Vector2 hi(-INFINITY, -INFINITY);
	for (int64_t i = 0; i < count; i++) {
		const Vector2 p = s[reg[i]];
		lo = lo.min(p);
		hi = hi.max(p);
	}
	_fit_grid(lo, hi);
	_build_grid(reg, count, s, p_snap.size());
}

void HordeCore::_fit_grid(const Vector2 &p_lo, const Vector2 &p_hi) {
	origin = p_lo;
	// В GDScript hi.x - lo.x — уже double, а int() отбрасывает дробь, как приведение к int64_t.
	grid_w = CLAMP(int64_t((double(p_hi.x) - double(p_lo.x)) * inv_cell) + 1, int64_t(1), max_cells);
	grid_h = CLAMP(int64_t((double(p_hi.y) - double(p_lo.y)) * inv_cell) + 1, int64_t(1), max_cells);
}

void HordeCore::_build_grid(const int32_t *p_reg, int64_t p_count, const Vector2 *p_snap, int64_t p_rows) {
	const int64_t w = grid_w;
	const int64_t h = grid_h;
	const int64_t cells = w * h;
	// Длина как у колонок Horde (_grow): номер места в реестре меньше числа строк.
	if (cell_of.size() != p_rows) {
		cell_of.resize(p_rows);
		sorted.resize(p_rows);
	}
	cell_count.fill(0);
	int32_t *cnt = cell_count.ptrw();
	int32_t *cell_at = cell_of.ptrw();
	const double ox = origin.x;
	const double oy = origin.y;
	for (int64_t i = 0; i < p_count; i++) {
		const Vector2 p = p_snap[p_reg[i]];
		const int64_t c = MIN(int64_t((double(p.x) - ox) * inv_cell), w - 1) +
				MIN(int64_t((double(p.y) - oy) * inv_cell), h - 1) * w;
		cell_at[i] = int32_t(c);
		cnt[c] += 1;
	}
	int32_t *start = cell_start.ptrw();
	int32_t *fill = cell_fill.ptrw();
	int32_t acc = 0;
	for (int64_t c = 0; c < cells; c++) {
		start[c] = acc;
		fill[c] = acc;
		acc += cnt[c];
	}
	int32_t *in_cells = sorted.ptrw();
	for (int64_t i = 0; i < p_count; i++) {
		const int32_t c = cell_at[i];
		in_cells[fill[c]] = p_reg[i];
		fill[c] += 1;
	}
}

// Формула Horde._push_apart: каждый перекрытый сосед толкает на глубину перекрытия, доля
// толчка — масса соседа к сумме масс; плюс толчок от игрока; итог × separation_response,
// не больше предела. Порядок сложения тот же: клетки сетки по рядам, в клетке — по порядку.
void HordeCore::_push_apart(const int32_t *p_reg, int64_t p_count, const float *p_radius, const float *p_mass,
		const float *p_response, const float *p_max_push, const Vector2 &p_player_pos,
		double p_player_radius, double p_player_mass) {
	const Vector2 *s = snap.ptr();
	const int32_t *cell_at = cell_of.ptr();
	const int32_t *cnt = cell_count.ptr();
	const int32_t *start = cell_start.ptr();
	const int32_t *in_cells = sorted.ptr();
	Vector2 *out = sep_vel.ptrw();
	const int64_t w = grid_w;
	const int64_t h = grid_h;
	int64_t overlap_count = 0;
	for (int64_t i = 0; i < p_count; i++) {
		const int32_t t = p_reg[i];
		const Vector2 p = s[t];
		const double ri = p_radius[t];
		const double mi = p_mass[t];
		const int64_t c = cell_at[i];
		const int64_t cy = c / w;
		const int64_t cx = c - cy * w;
		Vector2 push;
		for (int64_t gy = MAX(cy - 1, int64_t(0)); gy < MIN(cy + 2, h); gy++) {
			const int64_t row = gy * w;
			for (int64_t gx = MAX(cx - 1, int64_t(0)); gx < MIN(cx + 2, w); gx++) {
				const int64_t cc = row + gx;
				const int64_t first = start[cc];
				const int64_t last = first + cnt[cc];
				for (int64_t k = first; k < last; k++) {
					const int32_t j = in_cells[k];
					if (j == t) {
						continue;
					}
					const Vector2 offset = p - s[j];
					const double reach = ri + double(p_radius[j]);
					const double d2 = offset.length_squared();
					if (d2 < reach * reach && d2 > 0.0) {
						const double d = std::sqrt(d2);
						const double mj = p_mass[j];
						// Vector2 * число: число сначала становится float, как в GDScript.
						push += offset * real_t((reach - d) / d * mj / (mi + mj));
						overlap_count += 1;
					}
				}
			}
		}
		const Vector2 to_me = p - p_player_pos;
		const double reach_p = ri + p_player_radius;
		const double dp2 = to_me.length_squared();
		if (dp2 < reach_p * reach_p && dp2 > 0.0) {
			const double dp = std::sqrt(dp2);
			push += to_me * real_t((reach_p - dp) / dp * p_player_mass / (mi + p_player_mass));
		}
		out[t] = (push * real_t(p_response[t])).limit_length(real_t(p_max_push[t]));
	}
	overlaps = overlap_count;
}

// Horde._touch_player: центры ближе, чем hurt_radius игрока плюс радиус тела врага.
// Урон всех касающихся складывается, Horde наносит его одним take_damage.
void HordeCore::_touch_player(const int32_t *p_reg, int64_t p_count, const float *p_contact_r2,
		const float *p_contact_damage, const uint8_t *p_dead, const Vector2 &p_player_pos) {
	const Vector2 *s = snap.ptr();
	double total = 0.0;
	int64_t touching_count = 0;
	for (int64_t i = 0; i < p_count; i++) {
		const int32_t t = p_reg[i];
		if (double(p_player_pos.distance_squared_to(s[t])) < double(p_contact_r2[t])) {
			// Убитый в этом шаге ждёт уборки, но уже не бьёт.
			if (p_dead[t]) {
				continue;
			}
			total += double(p_contact_damage[t]);
			touching_count += 1;
		}
	}
	touching = touching_count;
	contact_total = total;
}
