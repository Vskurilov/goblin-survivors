#include "shots_core.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>
#include <utility>

using namespace godot;

namespace {

// Нет цели и игрок как цель — те же числа, что Horde.NOBODY и Horde.PLAYER.
constexpr int32_t NOBODY = -2;
constexpr int32_t PLAYER = -1;
// Чисел на снаряд в events и на экземпляр в буфере MultiMesh (базис и позиция).
constexpr int64_t EVENT = 5;
constexpr int64_t STRIDE = 8;

// Указатель на данные массива. У пустого массива его нет: движок на ptr() пустого
// массива пишет ошибку, поэтому nullptr.
template <typename T>
auto data_of(const T &p_array) -> decltype(p_array.ptr()) {
	return p_array.size() > 0 ? p_array.ptr() : nullptr;
}

void to_packed(const std::vector<int32_t> &p_from, PackedInt32Array &r_to) {
	r_to.resize(int64_t(p_from.size()));
	if (!p_from.empty()) {
		std::memcpy(r_to.ptrw(), p_from.data(), p_from.size() * sizeof(int32_t));
	}
}

} // namespace

void ShotsCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_targets", "snap", "hit_radius", "dead", "gen", "cell_count", "cell_start",
								 "sorted", "origin", "grid_w", "grid_h", "inv_cell", "max_hit_radius", "grid",
								 "player", "player_pos", "player_radius", "unit_circle"),
			&ShotsCore::set_targets);
	ClassDB::bind_method(D_METHOD("query", "order", "count", "frame", "born", "pos", "flags", "limit",
								 "owner_row", "owner_gen", "radius", "bound", "basis", "shape", "shapes", "move"),
			&ShotsCore::query);
	ClassDB::bind_method(D_METHOD("move", "order", "stop", "frame", "born", "done", "move", "direction", "side",
								 "speed", "amplitude", "frequency", "phase", "lifetime", "pos", "travel_time",
								 "age", "delta"),
			&ShotsCore::move);
	ClassDB::bind_method(D_METHOD("draw", "order", "kind", "view", "pos", "capacity"), &ShotsCore::draw);

	ClassDB::bind_method(D_METHOD("get_events"), &ShotsCore::get_events);
	ClassDB::bind_method(D_METHOD("get_targets"), &ShotsCore::get_targets);
	ClassDB::bind_method(D_METHOD("get_order"), &ShotsCore::get_order);
	ClassDB::bind_method(D_METHOD("get_pos"), &ShotsCore::get_pos);
	ClassDB::bind_method(D_METHOD("get_travel_time"), &ShotsCore::get_travel_time);
	ClassDB::bind_method(D_METHOD("get_age"), &ShotsCore::get_age);
	ClassDB::bind_method(D_METHOD("get_expired"), &ShotsCore::get_expired);
	ClassDB::bind_method(D_METHOD("get_counts"), &ShotsCore::get_counts);
	ClassDB::bind_method(D_METHOD("get_buffers"), &ShotsCore::get_buffers);

	// Только для чтения: Shots берёт их через get().
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "events"), "", "get_events");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "targets"), "", "get_targets");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "order"), "", "get_order");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_VECTOR2_ARRAY, "pos"), "", "get_pos");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT64_ARRAY, "travel_time"), "", "get_travel_time");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT64_ARRAY, "age"), "", "get_age");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "expired"), "", "get_expired");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY, "counts"), "", "get_counts");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "buffers"), "", "get_buffers");
}

void ShotsCore::set_targets(const PackedVector2Array &p_snap, const PackedFloat32Array &p_hit_radius,
		const PackedByteArray &p_dead, const PackedInt32Array &p_gen,
		const PackedInt32Array &p_cell_count, const PackedInt32Array &p_cell_start,
		const PackedInt32Array &p_sorted, const Vector2 &p_origin, int64_t p_grid_w, int64_t p_grid_h,
		double p_inv_cell, double p_max_hit_radius, bool p_grid, bool p_player,
		const Vector2 &p_player_pos, double p_player_radius, const Ref<Shape2D> &p_unit_circle) {
	has_targets = true;
	snap = p_snap;
	hit_radius = p_hit_radius;
	dead = p_dead;
	gen = p_gen;
	cell_count = p_cell_count;
	cell_start = p_cell_start;
	sorted = p_sorted;
	origin = p_origin;
	grid_w = p_grid_w;
	grid_h = p_grid_h;
	inv_cell = p_inv_cell;
	max_hit_radius = p_max_hit_radius;
	grid = p_grid;
	player = p_player;
	player_pos = p_player_pos;
	player_radius = p_player_radius;
	unit_circle = p_unit_circle;
}

// Цели отпущены: массивы Horde ядро не держит между шагами, иначе запись в них из GDScript
// копировала бы массив целиком.
void ShotsCore::_release_targets() {
	has_targets = false;
	snap = PackedVector2Array();
	hit_radius = PackedFloat32Array();
	dead = PackedByteArray();
	gen = PackedInt32Array();
	cell_count = PackedInt32Array();
	cell_start = PackedInt32Array();
	sorted = PackedInt32Array();
	grid = false;
	player = false;
}

// Horde.query_hits строка в строку, для каждого снаряда порядка.
int64_t ShotsCore::query(const PackedInt32Array &p_order, int64_t p_count, int64_t p_frame,
		const PackedInt64Array &p_born, const PackedVector2Array &p_pos, const PackedByteArray &p_flags,
		const PackedInt32Array &p_limit, const PackedInt32Array &p_owner_row,
		const PackedInt32Array &p_owner_gen, const PackedFloat64Array &p_radius,
		const PackedFloat64Array &p_bound, const PackedVector2Array &p_basis,
		const PackedInt32Array &p_shape, const Array &p_shapes, const PackedByteArray &p_move) {
	event_list.clear();
	target_list.clear();
	const int64_t count = MIN(p_count, p_order.size());
	const int32_t *order_at = data_of(p_order);
	const int64_t *born = data_of(p_born);
	const Vector2 *at_of = data_of(p_pos);
	const uint8_t *flags = data_of(p_flags);
	const int32_t *limit = data_of(p_limit);
	const int32_t *owner_row = data_of(p_owner_row);
	const int32_t *owner_gen = data_of(p_owner_gen);
	const double *radius = data_of(p_radius);
	const double *bound_of = data_of(p_bound);
	const Vector2 *basis = data_of(p_basis);
	const int32_t *shape_of = data_of(p_shape);
	const uint8_t *move_of = data_of(p_move);
	shapes.resize(size_t(p_shapes.size()));
	for (int64_t i = 0; i < p_shapes.size(); i++) {
		shapes[size_t(i)] = Object::cast_to<Shape2D>(p_shapes[i]);
	}
	const Vector2 *s = data_of(snap);
	const float *body_radius = data_of(hit_radius);
	const uint8_t *is_dead = data_of(dead);
	const int32_t *generation = data_of(gen);
	const int32_t *cnt = data_of(cell_count);
	const int32_t *start = data_of(cell_start);
	const int32_t *in_cells = data_of(sorted);
	// Сетка есть, только если её разложил Horde (есть кому бить врагов и есть враги).
	const bool enemies = has_targets && grid && s != nullptr && cnt != nullptr && start != nullptr &&
			in_cells != nullptr && is_dead != nullptr && body_radius != nullptr && generation != nullptr;
	const bool target_player = has_targets && player;
	const int64_t w = grid_w;
	const int64_t h = grid_h;
	const double ox = origin.x;
	const double oy = origin.y;
	for (int64_t k = 0; k < count; k++) {
		const int32_t shot = order_at[k];
		// Выпущен в этом шаге: летит со следующего, как новый узел.
		if (born[shot] == p_frame) {
			continue;
		}
		const uint8_t f = flags[shot];
		found.clear();
		found_d2.clear();
		const Vector2 at = at_of[shot];
		const double bound = bound_of[shot];
		// У круга расстояние и есть точная проверка, collide() не нужен.
		const bool exact = radius[shot] >= 0.0;
		const int32_t shape_id = shape_of[shot];
		Shape2D *shape = (!exact && shape_id >= 0 && size_t(shape_id) < shapes.size()) ? shapes[size_t(shape_id)] : nullptr;
		const Vector2 bx = basis[shot * 2];
		const Vector2 by = basis[shot * 2 + 1];
		if ((f & HITS_ENEMIES) && enemies) {
			// Враг-стрелок своим снарядом себя не бьёт, пока он тот же (Horde.is_same).
			const int32_t row = owner_row[shot];
			const int32_t exclude = (row >= 0 && generation[row] == owner_gen[shot]) ? row : NOBODY;
			const double reach = bound + max_hit_radius;
			// В GDScript at.x - reach - _origin.x — double, int() отбрасывает дробь.
			const int64_t x0 = CLAMP(int64_t((double(at.x) - reach - ox) * inv_cell), int64_t(0), w - 1);
			const int64_t x1 = CLAMP(int64_t((double(at.x) + reach - ox) * inv_cell), int64_t(0), w - 1);
			const int64_t y0 = CLAMP(int64_t((double(at.y) - reach - oy) * inv_cell), int64_t(0), h - 1);
			const int64_t y1 = CLAMP(int64_t((double(at.y) + reach - oy) * inv_cell), int64_t(0), h - 1);
			for (int64_t gy = y0; gy <= y1; gy++) {
				const int64_t grid_row = gy * w;
				for (int64_t gx = x0; gx <= x1; gx++) {
					const int64_t first = start[grid_row + gx];
					const int64_t last = first + cnt[grid_row + gx];
					for (int64_t c = first; c < last; c++) {
						const int32_t j = in_cells[c];
						const Vector2 p = s[j];
						const double r = body_radius[j];
						const double d2 = at.distance_squared_to(p);
						const double lim = bound + r;
						if (d2 >= lim * lim) {
							continue;
						}
						// Убитый в этом шаге ждёт уборки, но уже не цель.
						if (is_dead[j] || j == exclude) {
							continue;
						}
						if (!exact && !_collide(shape, bx, by, at, p, r)) {
							continue;
						}
						found.push_back(j);
						found_d2.push_back(d2);
					}
				}
			}
		}
		if ((f & HITS_PLAYER) && target_player) {
			// HitShape.touches с центром игрока: у круга — расстояние, иначе collide().
			const double d2 = at.distance_squared_to(player_pos);
			bool touch;
			if (exact) {
				const double reach = radius[shot] + player_radius;
				touch = d2 < reach * reach;
			} else {
				const double lim = bound + player_radius;
				touch = !(d2 >= lim * lim) && _collide(shape, bx, by, at, player_pos, player_radius);
			}
			if (touch) {
				found.push_back(PLAYER);
				found_d2.push_back(d2);
			}
		}
		int64_t n = int64_t(found.size());
		bool cut = false;
		const int64_t limit_n = limit[shot];
		if (limit_n > 0 && n > limit_n) {
			_keep_nearest(limit_n);
			n = limit_n;
			cut = true;
		}
		if (n > 0 || move_of[shot] == MOVE_SCRIPT) {
			event_list.push_back(int32_t(k));
			event_list.push_back(shot);
			event_list.push_back(int32_t(target_list.size()));
			event_list.push_back(int32_t(n));
			event_list.push_back(cut ? 1 : 0);
			target_list.insert(target_list.end(), found.begin(), found.begin() + n);
		}
	}
	_release_targets();
	to_packed(event_list, events);
	to_packed(target_list, targets);
	return int64_t(event_list.size()) / EVENT;
}

// Horde._keep_nearest: оставляет limit ближайших, ближний первым — частичная сортировка
// выбором, при равных расстояниях выигрывает стоящий раньше.
void ShotsCore::_keep_nearest(int64_t p_limit) {
	const int64_t n = int64_t(found.size());
	for (int64_t a = 0; a < p_limit; a++) {
		int64_t best = a;
		for (int64_t b = a + 1; b < n; b++) {
			if (found_d2[b] < found_d2[best]) {
				best = b;
			}
		}
		if (best != a) {
			std::swap(found[a], found[best]);
			std::swap(found_d2[a], found_d2[best]);
		}
	}
	found.resize(size_t(p_limit));
	found_d2.resize(size_t(p_limit));
}

// HitShape.touches для фигуры не-круга: базис снаряда с центром удара против круга
// радиусом 1, растянутого до радиуса тела, — Transform2D(0.0, Vector2(r, r), 0.0, center).
// У такого Transform2D второй столбец (-0.0, r): минус нуля — как у конструктора движка.
bool ShotsCore::_collide(Shape2D *p_shape, const Vector2 &p_x, const Vector2 &p_y, const Vector2 &p_at,
		const Vector2 &p_center, double p_radius) const {
	if (p_shape == nullptr) {
		return false;
	}
	Transform2D xform;
	xform.columns[0] = p_x;
	xform.columns[1] = p_y;
	xform.columns[2] = p_at;
	const real_t r = real_t(p_radius);
	Transform2D body;
	body.columns[0] = Vector2(r, 0.0f);
	body.columns[1] = Vector2(-0.0f, r);
	body.columns[2] = p_center;
	return p_shape->collide(xform, unit_circle, body);
}

// Shots._fly строка в строку: шаг по траектории, потом возраст.
void ShotsCore::move(const PackedInt32Array &p_order, int64_t p_stop, int64_t p_frame, const PackedInt64Array &p_born,
		const PackedByteArray &p_done, const PackedByteArray &p_move, const PackedVector2Array &p_direction,
		const PackedVector2Array &p_side, const PackedFloat64Array &p_speed,
		const PackedFloat64Array &p_amplitude, const PackedFloat64Array &p_frequency,
		const PackedFloat64Array &p_phase, const PackedFloat64Array &p_lifetime,
		const PackedVector2Array &p_pos, const PackedFloat64Array &p_travel_time,
		const PackedFloat64Array &p_age, double p_delta) {
	expired_list.clear();
	// Копии массивов Shots: первая запись ниже даёт ядру свой буфер с теми же числами.
	pos = p_pos;
	travel_time = p_travel_time;
	age = p_age;
	const int64_t size = p_order.size();
	if (size == 0 || pos.size() == 0) {
		order = PackedInt32Array();
		to_packed(expired_list, expired);
		return;
	}
	Vector2 *at = pos.ptrw();
	double *travel = travel_time.ptrw();
	double *lived_of = age.ptrw();
	const int32_t *in = p_order.ptr();
	const int64_t *born = p_born.ptr();
	const uint8_t *done = p_done.ptr();
	const uint8_t *mode = p_move.ptr();
	const Vector2 *dir = p_direction.ptr();
	const Vector2 *side = p_side.ptr();
	const double *spd = p_speed.ptr();
	const double *amp = p_amplitude.ptr();
	const double *freq = p_frequency.ptr();
	const double *phase_of = p_phase.ptr();
	const double *lifetime_of = p_lifetime.ptr();
	std::vector<int32_t> kept;
	kept.reserve(size_t(size));
	// Vector2 * число: число сначала становится float, как в GDScript.
	const real_t step = real_t(p_delta);
	for (int64_t k = 0; k < size; k++) {
		const int32_t shot = in[k];
		if (done[shot]) {
			continue;
		}
		// Дальше места паузы, выпущенный в этом шаге и режим SCRIPT — без полёта ядром.
		if (k >= p_stop || born[shot] == p_frame || mode[shot] == MOVE_SCRIPT) {
			kept.push_back(shot);
			continue;
		}
		if (mode[shot] == MOVE_WAVE) {
			const double t = travel[shot] + p_delta;
			travel[shot] = t;
			const Vector2 forward = dir[shot] * real_t(spd[shot]);
			const double frequency = freq[shot];
			const double phase = t * frequency + phase_of[shot];
			const Vector2 lateral = side[shot] * real_t(amp[shot]) * real_t(frequency) *
					real_t(UtilityFunctions::cos(phase));
			at[shot] = at[shot] + (forward + lateral) * step;
		} else {
			at[shot] = at[shot] + dir[shot] * real_t(spd[shot]) * step;
		}
		const double lifetime = lifetime_of[shot];
		if (lifetime > 0.0) {
			const double lived = lived_of[shot] + p_delta;
			lived_of[shot] = lived;
			if (lived >= lifetime) {
				expired_list.push_back(shot);
				continue;
			}
		}
		kept.push_back(shot);
	}
	to_packed(kept, order);
	to_packed(expired_list, expired);
}

// Shots._fill_buffers: базис картинки и позиция каждого снаряда, по видам в порядке появления.
void ShotsCore::draw(const PackedInt32Array &p_order, const PackedInt32Array &p_kind, const PackedVector2Array &p_view,
		const PackedVector2Array &p_pos, const PackedInt32Array &p_capacity) {
	const int64_t kinds = p_capacity.size();
	// Буферы прошлого вызова отпущены: запись ниже не копирует их заново.
	buffers.clear();
	kind_buffers.resize(size_t(kinds));
	counts.resize(kinds);
	if (kinds == 0) {
		return;
	}
	int32_t *count = counts.ptrw();
	const int32_t *capacity = p_capacity.ptr();
	std::vector<float *> out(size_t(kinds), nullptr);
	for (int64_t kind = 0; kind < kinds; kind++) {
		count[kind] = 0;
		PackedFloat32Array &buffer = kind_buffers[size_t(kind)];
		const int64_t length = int64_t(capacity[kind]) * STRIDE;
		if (buffer.size() != length) {
			buffer.resize(length);
		}
		if (length > 0) {
			out[size_t(kind)] = buffer.ptrw();
		}
	}
	const int64_t size = p_order.size();
	if (size > 0) {
		const int32_t *in = p_order.ptr();
		const int32_t *kind_of = p_kind.ptr();
		const Vector2 *view = p_view.ptr();
		const Vector2 *at = p_pos.ptr();
		for (int64_t k = 0; k < size; k++) {
			const int32_t shot = in[k];
			const int32_t kind = kind_of[shot];
			const int32_t i = count[kind];
			if (i >= capacity[kind]) {
				continue;
			}
			count[kind] = i + 1;
			float *b = out[size_t(kind)] + int64_t(i) * STRIDE;
			const Vector2 x = view[shot * 2];
			const Vector2 y = view[shot * 2 + 1];
			const Vector2 p = at[shot];
			b[0] = x.x;
			b[1] = y.x;
			b[2] = 0.0f;
			b[3] = p.x;
			b[4] = x.y;
			b[5] = y.y;
			b[6] = 0.0f;
			b[7] = p.y;
		}
	}
	buffers.resize(kinds);
	for (int64_t kind = 0; kind < kinds; kind++) {
		buffers[kind] = kind_buffers[size_t(kind)];
	}
}
