package cmd

import "core:fmt"
import "core:math"
import "core:strconv"
import lib "../lib"
import sqlite "ext:sqlite3"

TierInfo :: struct {
	tier:     int,
	label:    string,
	behavior: string,
}

heat_to_tier :: proc(heat: int) -> TierInfo {
	if heat <= 0 {
		return {0, "Clean", "Ignore"}
	} else if heat <= 15 {
		return {1, "Suspicious", "Question"}
	} else if heat <= 35 {
		return {2, "Wanted", "Detain"}
	} else if heat <= 60 {
		return {3, "Hunted", "Attack on sight"}
	} else if heat <= 85 {
		return {4, "Infamous", "Mobilize guards"}
	}
	return {5, "Legendary Fugitive", "Scry & strike"}
}

// Exponential decay in hours. lambda = 0.05/24 preserves ~14-day half-life.
compute_decay_hours :: proc(current_heat: int, last_decay_hour: int, current_total_hours: int) -> int {
	if last_decay_hour <= 0 do return current_heat
	hours_elapsed := current_total_hours - last_decay_hour
	if hours_elapsed <= 0 do return current_heat
	if current_heat == 0 do return 0
	decayed := f64(current_heat) * math.exp(-0.05 / 24.0 * f64(hours_elapsed))
	return int(decayed)
}

get_parent_location_id :: proc(db: ^lib.Db, location_id: int) -> int {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT parent_id FROM locations WHERE id=%d", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0))
	}
	return 0
}

query_wanted_heat :: proc(db: ^lib.Db, actor_type: string, actor_id: int, faction_id: int, location_id: int) -> (heat: int, last_hour: int, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT heat_points, last_decay_hour FROM wanted_heat WHERE actor_type='%s' AND actor_id=%d AND faction_id=%d AND location_id=%d",
		actor_type,
		actor_id,
		faction_id,
		location_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0, 0, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0)), int(sqlite.column_int(stmt, 1)), true
	}
	return 0, 0, false
}

// Returns total_elapsed_hours from the actor's campaign, or 0 if unassigned.
get_current_hours_for_actor :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> (int, bool) {
	table: string
	if actor_type == "character" {
		table = "characters"
	} else if actor_type == "npc" {
		table = "npcs"
	} else {
		return 0, false
	}

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT c.total_elapsed_hours FROM %s a JOIN campaigns c ON a.campaign_id=c.id WHERE a.id=%d",
		table,
		actor_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0)), true
	}
	return 0, false
}

// Walk the location parent chain to resolve effective wanted heat.
// An explicit row at a child location takes precedence over inherited parent heat.
get_effective_heat :: proc(db: ^lib.Db, actor_type: string, actor_id: int, faction_id: int, location_id: int) -> (raw_heat: int, decayed: int, source_loc_id: int, tier: TierInfo, found: bool) {
	current_loc := location_id
	for current_loc > 0 {
		raw, last_hour, ok := query_wanted_heat(db, actor_type, actor_id, faction_id, current_loc)
		if ok {
			decayed_heat := raw
			current_hours, hours_ok := get_current_hours_for_actor(db, actor_type, actor_id)
			if hours_ok && last_hour > 0 {
				decayed_heat = compute_decay_hours(raw, last_hour, current_hours)
			}
			return raw, decayed_heat, current_loc, heat_to_tier(decayed_heat), true
		}
		current_loc = get_parent_location_id(db, current_loc)
	}
	return 0, 0, 0, heat_to_tier(0), false
}

validate_wanted_actor :: proc(actor_type: string) -> (string, bool) {
	if actor_type == "char" || actor_type == "character" {
		return "character", true
	}
	if actor_type == "npc" {
		return "npc", true
	}
	return "", false
}

// --- CLI entry points ---

wanted_crime :: proc(db: ^lib.Db, args: []string) -> int {
	// args: <char|npc> <actor_id> <faction_id> <location_id> <severity> <description>
	if len(args) < 7 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine wanted crime <char|npc> <actor_id> <faction_id> <location_id> <severity> <description>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine wanted crime <char|npc> <actor_id> <faction_id> <location_id> <severity> <description>")
		}
		return 1
	}

	actor_type, ok := validate_wanted_actor(args[1])
	if !ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Invalid actor type. Use 'char' or 'npc'."}`)
		} else {
			fmt.eprintln("Invalid actor type. Use 'char' or 'npc'.")
		}
		return 1
	}

	actor_id := strconv.atoi(args[2])
	faction_id := strconv.atoi(args[3])
	location_id := strconv.atoi(args[4])
	severity := strconv.atoi(args[5])
	description := args[6]

	current_hours, _ := get_current_hours_for_actor(db, actor_type, actor_id)
	current_day := 0
	if current_hours > 0 {
		current_day = current_hours / 24
	}

	// Log the crime
	crime_sql := fmt.tprintf(
		"INSERT INTO crime_log (actor_type, actor_id, faction_id, location_id, description, severity, in_game_day) VALUES('%s',%d,%d,%d,'%s',%d,%d)",
		actor_type,
		actor_id,
		faction_id,
		location_id,
		escape_sql(description),
		severity,
		current_day,
	)
	if lib.db_exec(db, crime_sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to log crime."}`)
		} else {
			fmt.eprintln("Failed to log crime.")
		}
		return 1
	}

	// Upsert wanted_heat
	existing_heat, _, exists := query_wanted_heat(db, actor_type, actor_id, faction_id, location_id)
	new_heat := existing_heat + severity
	if exists {
		update_sql := fmt.tprintf(
			"UPDATE wanted_heat SET heat_points=%d, last_decay_hour=%d WHERE actor_type='%s' AND actor_id=%d AND faction_id=%d AND location_id=%d",
			new_heat,
			current_hours,
			actor_type,
			actor_id,
			faction_id,
			location_id,
		)
		if lib.db_exec(db, update_sql) != lib.Error.None {
			if db.is_json {
				fmt.println(`{"success":false,"error":"Failed to update wanted heat."}`)
			} else {
				fmt.eprintln("Failed to update wanted heat.")
			}
			return 1
		}
	} else {
		insert_sql := fmt.tprintf(
			"INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('%s',%d,%d,%d,%d,%d)",
			actor_type,
			actor_id,
			faction_id,
			location_id,
			severity,
			current_hours,
		)
		if lib.db_exec(db, insert_sql) != lib.Error.None {
			if db.is_json {
				fmt.println(`{"success":false,"error":"Failed to create wanted heat."}`)
			} else {
				fmt.eprintln("Failed to create wanted heat.")
			}
			return 1
		}
	}

	tier_info := heat_to_tier(new_heat)
	actor_name := get_actor_name(db, actor_type, actor_id)

	if db.is_json {
		fmt.printf(
			`{{"success":true,"message":"Crime logged.","actor_type":"%s","actor_id":%d,"actor_name":"%s","faction_id":%d,"location_id":%d,"heat_points":%d,"raw_heat":%d,"tier":%d,"tier_label":"%s","severity_added":%d}}` + "\n",
			actor_type,
			actor_id,
			escape_json_string(actor_name),
			faction_id,
			location_id,
			new_heat,
			new_heat,
			tier_info.tier,
			escape_json_string(tier_info.label),
			severity,
		)
	} else {
		fmt.printf("Crime logged: %s\n", description)
		fmt.printf("  Actor: %s (%s #%d)\n", actor_name, actor_type, actor_id)
		fmt.printf("  Heat: %d (+%d) [Tier %d: %s]\n", new_heat, severity, tier_info.tier, tier_info.label)
		fmt.printf("  Location: #%d | Faction: #%d | Day: %d\n", location_id, faction_id, current_day)
	}
	return 0
}

// Display wanted status for a single location, walking the parent chain.
wanted_get_single :: proc(db: ^lib.Db, actor_type: string, actor_id: int, faction_id: int, location_id: int) -> int {
	actor_name := get_actor_name(db, actor_type, actor_id)
	raw_heat, decayed, source_loc, tier_info, found := get_effective_heat(db, actor_type, actor_id, faction_id, location_id)
	inherited := found && source_loc != location_id

	if db.is_json {
		fmt.printf(
			`{{"success":true,"actor_type":"%s","actor_id":%d,"actor_name":"%s","faction_id":%d,"location_id":%d,"source_location_id":%d,"inherited":%t,"raw_heat":%d,"decayed_heat":%d,"tier":%d,"tier_label":"%s","guard_behavior":"%s"}}` + "\n",
			actor_type,
			actor_id,
			escape_json_string(actor_name),
			faction_id,
			location_id,
			source_loc,
			inherited,
			raw_heat,
			decayed,
			tier_info.tier,
			escape_json_string(tier_info.label),
			escape_json_string(tier_info.behavior),
		)
	} else {
		if found {
			if inherited {
				fmt.printf("Wanted status for %s (Faction #%d):\n", actor_name, faction_id)
				fmt.printf("  Effective heat: %d (raw: %d) [Tier %d: %s]\n", decayed, raw_heat, tier_info.tier, tier_info.label)
				fmt.printf("  Inherited from location #%d (queried #%d)\n", source_loc, location_id)
				fmt.printf("  Guard behavior: %s\n", tier_info.behavior)
			} else {
				fmt.printf("Wanted status for %s (Faction #%d):\n", actor_name, faction_id)
				fmt.printf("  Heat: %d (raw: %d) [Tier %d: %s]\n", decayed, raw_heat, tier_info.tier, tier_info.label)
				fmt.printf("  Location: #%d | Guard behavior: %s\n", location_id, tier_info.behavior)
			}
		} else {
			fmt.printf("Wanted status for %s (Faction #%d):\n", actor_name, faction_id)
			fmt.printf("  Clean — no wanted record at location #%d or its parents.\n", location_id)
		}
	}
	return 0
}

// List wanted entries across all locations for an actor+faction pair.
wanted_get_all :: proc(db: ^lib.Db, actor_type: string, actor_id: int, faction_id: int) -> int {
	actor_name := get_actor_name(db, actor_type, actor_id)

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT location_id, heat_points, last_decay_hour FROM wanted_heat WHERE actor_type='%s' AND actor_id=%d AND faction_id=%d",
		actor_type,
		actor_id,
		faction_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to query wanted heat."}`)
		} else {
			fmt.eprintln("Failed to query wanted heat.")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	current_hours, hours_ok := get_current_hours_for_actor(db, actor_type, actor_id)

	if db.is_json {
		fmt.print("[")
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			loc := int(sqlite.column_int(stmt, 0))
			raw := int(sqlite.column_int(stmt, 1))
			last_hour := int(sqlite.column_int(stmt, 2))
			decayed_heat := raw
			if hours_ok && last_hour > 0 {
				decayed_heat = compute_decay_hours(raw, last_hour, current_hours)
			}
			ti := heat_to_tier(decayed_heat)
			fmt.printf(
				`{{"location_id":%d,"raw_heat":%d,"decayed_heat":%d,"tier":%d,"tier_label":"%s"}}`,
				loc,
				raw,
				decayed_heat,
				ti.tier,
				escape_json_string(ti.label),
			)
		}
		fmt.println("]")
	} else {
		fmt.printf("Wanted status for %s across all locations (Faction #%d):\n", actor_name, faction_id)
		row_count := 0
		for sqlite.step(stmt) == .Row {
			loc := int(sqlite.column_int(stmt, 0))
			raw := int(sqlite.column_int(stmt, 1))
			last_hour := int(sqlite.column_int(stmt, 2))
			decayed_heat := raw
			if hours_ok && last_hour > 0 {
				decayed_heat = compute_decay_hours(raw, last_hour, current_hours)
			}
			ti := heat_to_tier(decayed_heat)
			fmt.printf("  Location #%d: heat %d (raw: %d) [Tier %d: %s]\n", loc, decayed_heat, raw, ti.tier, ti.label)
			row_count += 1
		}
		if row_count == 0 {
			fmt.println("  Clean — no wanted records.")
		}
	}
	return 0
}

wanted_get :: proc(db: ^lib.Db, args: []string) -> int {
	// args: <char|npc> <actor_id> <faction_id> [location_id]
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine wanted get <char|npc> <actor_id> <faction_id> [location_id]"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine wanted get <char|npc> <actor_id> <faction_id> [location_id]")
		}
		return 1
	}

	actor_type, ok := validate_wanted_actor(args[1])
	if !ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Invalid actor type. Use 'char' or 'npc'."}`)
		} else {
			fmt.eprintln("Invalid actor type. Use 'char' or 'npc'.")
		}
		return 1
	}

	actor_id := strconv.atoi(args[2])
	faction_id := strconv.atoi(args[3])
	location_id := len(args) >= 5 ? strconv.atoi(args[4]) : 0

	if location_id > 0 {
		return wanted_get_single(db, actor_type, actor_id, faction_id, location_id)
	}
	return wanted_get_all(db, actor_type, actor_id, faction_id)
}

wanted_set :: proc(db: ^lib.Db, args: []string) -> int {
	// args: <char|npc> <actor_id> <faction_id> <location_id> <heat>
	if len(args) < 6 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine wanted set <char|npc> <actor_id> <faction_id> <location_id> <heat>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine wanted set <char|npc> <actor_id> <faction_id> <location_id> <heat>")
		}
		return 1
	}

	actor_type, ok := validate_wanted_actor(args[1])
	if !ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Invalid actor type. Use 'char' or 'npc'."}`)
		} else {
			fmt.eprintln("Invalid actor type. Use 'char' or 'npc'.")
		}
		return 1
	}

	actor_id := strconv.atoi(args[2])
	faction_id := strconv.atoi(args[3])
	location_id := strconv.atoi(args[4])
	heat := strconv.atoi(args[5])

	current_hours, _ := get_current_hours_for_actor(db, actor_type, actor_id)

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('%s',%d,%d,%d,%d,%d)",
		actor_type,
		actor_id,
		faction_id,
		location_id,
		heat,
		current_hours,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set wanted heat."}`)
		} else {
			fmt.eprintln("Failed to set wanted heat.")
		}
		return 1
	}

	tier_info := heat_to_tier(heat)
	if db.is_json {
		fmt.printf(
			`{{"success":true,"message":"Wanted heat set.","actor_type":"%s","actor_id":%d,"faction_id":%d,"location_id":%d,"heat_points":%d,"tier":%d,"tier_label":"%s"}}` + "\n",
			actor_type,
			actor_id,
			faction_id,
			location_id,
			heat,
			tier_info.tier,
			escape_json_string(tier_info.label),
		)
	} else {
		fmt.printf("Wanted heat set: actor=%s #%d, faction=#%d, location=#%d, heat=%d [Tier %d: %s]\n",
			actor_type, actor_id, faction_id, location_id, heat, tier_info.tier, tier_info.label)
	}
	return 0
}

wanted_clear :: proc(db: ^lib.Db, args: []string) -> int {
	// args: <char|npc> <actor_id> <faction_id> <location_id>
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine wanted clear <char|npc> <actor_id> <faction_id> <location_id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine wanted clear <char|npc> <actor_id> <faction_id> <location_id>")
		}
		return 1
	}

	actor_type, ok := validate_wanted_actor(args[1])
	if !ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Invalid actor type. Use 'char' or 'npc'."}`)
		} else {
			fmt.eprintln("Invalid actor type. Use 'char' or 'npc'.")
		}
		return 1
	}

	actor_id := strconv.atoi(args[2])
	faction_id := strconv.atoi(args[3])
	location_id := strconv.atoi(args[4])

	sql := fmt.tprintf(
		"DELETE FROM wanted_heat WHERE actor_type='%s' AND actor_id=%d AND faction_id=%d AND location_id=%d",
		actor_type,
		actor_id,
		faction_id,
		location_id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to clear wanted heat."}`)
		} else {
			fmt.eprintln("Failed to clear wanted heat.")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"success":true,"message":"Wanted heat cleared.","actor_type":"%s","actor_id":%d,"faction_id":%d,"location_id":%d}}` + "\n",
			actor_type,
			actor_id,
			faction_id,
			location_id,
		)
	} else {
		fmt.printf("Wanted heat cleared: actor=%s #%d, faction=#%d, location=#%d\n",
			actor_type, actor_id, faction_id, location_id)
	}
	return 0
}

wanted_list :: proc(db: ^lib.Db, args: []string) -> int {
	// args: <faction_id> <location_id>
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine wanted list <faction_id> <location_id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine wanted list <faction_id> <location_id>")
		}
		return 1
	}

	faction_id := strconv.atoi(args[1])
	location_id := strconv.atoi(args[2])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT actor_type, actor_id, heat_points, last_decay_hour FROM wanted_heat WHERE faction_id=%d AND location_id=%d",
		faction_id,
		location_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to query wanted list."}`)
		} else {
			fmt.eprintln("Failed to query wanted list.")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		fmt.print("[")
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			at := column_text_safe(stmt, 0)
			aid := int(sqlite.column_int(stmt, 1))
			raw := int(sqlite.column_int(stmt, 2))
			last_hour := int(sqlite.column_int(stmt, 3))
			name := get_actor_name(db, at, aid)
			current_hours, hours_ok := get_current_hours_for_actor(db, at, aid)
			decayed_heat := raw
			if hours_ok && last_hour > 0 {
				decayed_heat = compute_decay_hours(raw, last_hour, current_hours)
			}
			ti := heat_to_tier(decayed_heat)
			fmt.printf(
				`{{"actor_type":"%s","actor_id":%d,"actor_name":"%s","raw_heat":%d,"decayed_heat":%d,"tier":%d,"tier_label":"%s","guard_behavior":"%s"}}`,
				at,
				aid,
				escape_json_string(name),
				raw,
				decayed_heat,
				ti.tier,
				escape_json_string(ti.label),
				escape_json_string(ti.behavior),
			)
		}
		fmt.println("]")
	} else {
		fmt.printf("Wanted list for Faction #%d at Location #%d:\n", faction_id, location_id)
		row_count := 0
		for sqlite.step(stmt) == .Row {
			at := column_text_safe(stmt, 0)
			aid := int(sqlite.column_int(stmt, 1))
			raw := int(sqlite.column_int(stmt, 2))
			last_hour := int(sqlite.column_int(stmt, 3))
			name := get_actor_name(db, at, aid)
			current_hours, hours_ok := get_current_hours_for_actor(db, at, aid)
			decayed_heat := raw
			if hours_ok && last_hour > 0 {
				decayed_heat = compute_decay_hours(raw, last_hour, current_hours)
			}
			ti := heat_to_tier(decayed_heat)
			fmt.printf("  %s (%s #%d): heat %d (raw: %d) [Tier %d: %s — %s]\n",
				name, at, aid, decayed_heat, raw, ti.tier, ti.label, ti.behavior)
			row_count += 1
		}
		if row_count == 0 {
			fmt.println("  No wanted entities at this location.")
		}
	}
	return 0
}
