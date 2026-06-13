package cmd

import "core:fmt"
import "core:math"
import lib "../lib"
import sqlite "ext:sqlite3"

// Exponential decay toward zero. lambda=0.05 gives ~14-day half-life.
// Returns 0 if standing is already zero or would decay past zero.
compute_decay :: proc(current_standing: int, last_interaction_day: int, current_day: int, lambda: f64 = 0.05) -> int {
	if last_interaction_day <= 0 do return current_standing
	days_elapsed := current_day - last_interaction_day
	if days_elapsed <= 0 do return current_standing
	if current_standing == 0 do return 0

	decayed := f64(current_standing) * math.exp(-lambda * f64(days_elapsed))
	return int(decayed)
}

// O(1) read of the current in-game day from a campaign's total_elapsed_hours.
get_current_day :: proc(db: ^lib.Db, campaign_id: int) -> (int, bool) {
	stmt: ^sqlite.Statement
	day_sql := fmt.tprintf("SELECT total_elapsed_hours FROM campaigns WHERE id=%d", campaign_id)
	day_sql_c := cstring(raw_data(day_sql))
	if sqlite.prepare(db.ptr, day_sql_c, i32(len(day_sql)), &stmt, nil) != .Ok {
		return 0, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0)) / 24, true
	}
	return 0, false
}
