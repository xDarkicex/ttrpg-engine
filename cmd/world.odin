package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math"
import lib "../lib"
import sqlite "ext:sqlite3"

// v15: sub-locations, sub-things (houses/shops/encounters/setpieces),
// relationship decay. See docs/planning/world-and-entities.md.
//
// Design notes:
// - All commands are O(1) per query (single row lookups, no matrix math).
// - Decay is computed at query time, not stored.
// - "Inventory" is a freeform text description; the AI generates items.
// - "open_hours" and "chapter_event" are plain text the LLM reads.

// ----- locations: sub-locations, restricted flags -----

// Set a location's parent_id (sub-location). Pass 0 to make it a root location.
location_set_parent :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine location set-parent <id> <parent_id|0>") }
		else { fmt.eprintln("Usage: ttrpg-engine location set-parent <id> <parent_id|0>") }
		return 1
	}
	id := strconv.atoi(args[1])
	parent := strconv.atoi(args[2])

	if parent != 0 {
		// Prevent making a cycle: parent must not be the same as id
		// (or any descendant of id). O(1) check: parent must be different from id.
		if parent == id {
			if db.is_json { usage_error(db, "A location cannot be its own parent") }
			else { fmt.eprintln("A location cannot be its own parent") }
			return 1
		}
	}

	sql: string
	if parent == 0 {
		sql = fmt.tprintf("UPDATE locations SET parent_id=NULL WHERE id=%d", id)
	} else {
		sql = fmt.tprintf("UPDATE locations SET parent_id=%d WHERE id=%d", parent, id)
	}
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to set parent") }
		else { fmt.eprintln("Failed to set parent") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Parent set","id":%d,"parent_id":%d}` + "\n", id, parent) }
	else { fmt.printf("Parent set to %d for location %d\n", parent, id) }
	return 0
}

location_set_restricted :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine location set-restricted <id> <0|1> <until>") }
		else { fmt.eprintln("Usage: ttrpg-engine location set-restricted <id> <0|1> <until>") }
		return 1
	}
	id := strconv.atoi(args[1])
	flag := strconv.atoi(args[2])
	if flag != 0 && flag != 1 {
		if db.is_json { usage_error(db, "Flag must be 0 or 1") }
		else { fmt.eprintln("Flag must be 0 or 1") }
		return 1
	}
	until := args[3]

	sql := fmt.tprintf("UPDATE locations SET restricted=%d, restricted_until='%s' WHERE id=%d", flag, escape_sql(until), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to set restricted") }
		else { fmt.eprintln("Failed to set restricted") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Restricted set","id":%d,"restricted":%d,"restricted_until":"%s"}` + "\n", id, flag, escape_json_string(until)) }
	else { fmt.printf("Restricted=%d (until %s) for location %d\n", flag, until, id) }
	return 0
}

// Walk the parent chain to produce a breadcrumb like "Ashwick > Blacksmith District > The Anvil & Flame".
// O(1) since location chains are short in practice (a few levels).
location_breadcrumb :: proc(db: ^lib.Db, location_id: int) -> string {
	if location_id <= 0 do return ""

	parts := make([dynamic]string, context.temp_allocator)
	curr_id := location_id
	max_depth := 10  // safety: prevent infinite loops on bad data
	for i := 0; i < max_depth && curr_id > 0; i += 1 {
		stmt: ^sqlite.Statement
		sql := fmt.tprintf("SELECT name, parent_id FROM locations WHERE id=%d", curr_id)
		sql_c := cstring(raw_data(sql))
		if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { break }
		if sqlite.step(stmt) == .Row {
			name := column_text_safe(stmt, 0)
			parent_id := int(sqlite.column_int(stmt, 1))
			append(&parts, fmt.tprintf("%s", name))
			sqlite.finalize(stmt)
			curr_id = parent_id
		} else {
			sqlite.finalize(stmt)
			break
		}
	}

	// Reverse so root is first
	rev := make([dynamic]string, context.temp_allocator)
	for i := len(parts) - 1; i >= 0; i -= 1 {
		append(&rev, parts[i])
	}
	return strings.join(rev[:], " > ", context.temp_allocator)
}

// ----- houses -----

// Add a house to a location. The npc_id is the resident.
house_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house add <location_id> <name> [description] [npc_id] [scale]") }
		else { fmt.eprintln("Usage: ttrpg-engine house add <location_id> <name> [description] [npc_id] [scale]") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	name := args[2]
	description := len(args) > 3 ? args[3] : ""
	npc_id := len(args) > 4 ? strconv.atoi(args[4]) : 0
	scale := len(args) > 5 ? args[5] : "mid"

	npc_val: string
	if npc_id <= 0 {
		npc_val = "NULL"
	} else {
		npc_val = fmt.tprintf("%d", npc_id)
	}
	sql := fmt.tprintf(
		"INSERT INTO houses (location_id, name, description, npc_id, scale) VALUES (%d, '%s', '%s', %s, '%s')",
		location_id, escape_sql(name), escape_sql(description), npc_val, escape_sql(scale),
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to add house") }
		else { fmt.eprintln("Failed to add house") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Added house: %s"}` + "\n", name) }
	else { fmt.printf("Added house: %s\n", name) }
	return 0
}

house_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house list <location_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine house list <location_id>") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, npc_id, scale, restricted, restricted_until, inventory FROM houses WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to list houses") }
		else { fmt.eprintln("Failed to list houses") }
		return 1
	}
	defer sqlite.finalize(stmt)
	if db.is_json {
		first := true
		fmt.print("[")
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			fmt.printf(`{"id":%d,"name":"%s","description":"%s","npc_id":%d,"scale":"%s","restricted":%d,"restricted_until":"%s","inventory":"%s"}`,
				sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2),
				sqlite.column_int(stmt, 3), column_text_safe(stmt, 4), sqlite.column_int(stmt, 5),
				column_text_safe(stmt, 6), column_text_safe(stmt, 7))
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			name := column_text_safe(stmt, 1)
			scale := column_text_safe(stmt, 4)
			restr := int(sqlite.column_int(stmt, 5))
			fmt.printf("  [%d] %s (scale: %s, restricted: %s)\n", sqlite.column_int(stmt, 0), name, scale, restr == 1 ? "yes" : "no")
		}
		if !has_any do fmt.println("  No houses in this location.")
	}
	return 0
}

house_set_inventory :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house set-inventory <id> <text>") }
		else { fmt.eprintln("Usage: ttrpg-engine house set-inventory <id> <text>") }
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]
	sql := fmt.tprintf("UPDATE houses SET inventory='%s' WHERE id=%d", escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to set inventory") }
		else { fmt.eprintln("Failed to set inventory") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Inventory set","id":%d}` + "\n", id) }
	else { fmt.printf("Inventory set for house %d\n", id) }
	return 0
}

house_set_restricted :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house set-restricted <id> <0|1> <until>") }
		else { fmt.eprintln("Usage: ttrpg-engine house set-restricted <id> <0|1> <until>") }
		return 1
	}
	id := strconv.atoi(args[1])
	flag := strconv.atoi(args[2])
	until := args[3]
	sql := fmt.tprintf("UPDATE houses SET restricted=%d, restricted_until='%s' WHERE id=%d", flag, escape_sql(until), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to set restricted") }
		else { fmt.eprintln("Failed to set restricted") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Restricted set"}` + "\n") }
	else { fmt.printf("Restricted=%d for house %d\n", flag, id) }
	return 0
}

// ----- shops -----

shop_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine shop add <location_id> <name> [description] [npc_id] [scale] [open_hours]") }
		else { fmt.eprintln("Usage: ttrpg-engine shop add <location_id> <name> [description] [npc_id] [scale] [open_hours]") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	name := args[2]
	description := len(args) > 3 ? args[3] : ""
	npc_id := len(args) > 4 ? strconv.atoi(args[4]) : 0
	scale := len(args) > 5 ? args[5] : "mid"
	open_hours := len(args) > 6 ? args[6] : "06:00-22:00"

	npc_val: string
	if npc_id <= 0 {
		npc_val = "NULL"
	} else {
		npc_val = fmt.tprintf("%d", npc_id)
	}
	treasury, _, _ := shop_scale_params(scale)
	sql := fmt.tprintf(
		"INSERT INTO shops (location_id, name, description, npc_id, scale, open_hours, gold) VALUES (%d, '%s', '%s', %s, '%s', '%s', %d)",
		location_id, escape_sql(name), escape_sql(description), npc_val, escape_sql(scale), escape_sql(open_hours), treasury,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to add shop") }
		else { fmt.eprintln("Failed to add shop") }
		return 1
	}
	if db.is_json { fmt.printf(`{{"success":true,"message":"Added shop","name":"%s","scale":"%s","treasury_gp":%d}}` + "\n", name, scale, treasury) }
	else { fmt.printf("Added shop: %s (scale: %s, treasury: %d gp)\n", name, scale, treasury) }
	return 0
}

shop_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine shop list <location_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine shop list <location_id>") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, npc_id, scale, open_hours, restricted, inventory FROM shops WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to list shops") }
		else { fmt.eprintln("Failed to list shops") }
		return 1
	}
	defer sqlite.finalize(stmt)
	if db.is_json {
		first := true
		fmt.print("[")
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			fmt.printf(`{"id":%d,"name":"%s","description":"%s","npc_id":%d,"scale":"%s","open_hours":"%s","restricted":%d,"inventory":"%s"}`,
				sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2),
				sqlite.column_int(stmt, 3), column_text_safe(stmt, 4), column_text_safe(stmt, 5),
				sqlite.column_int(stmt, 6), column_text_safe(stmt, 7))
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			name := column_text_safe(stmt, 1)
			scale := column_text_safe(stmt, 4)
			hours := column_text_safe(stmt, 5)
			fmt.printf("  [%d] %s (scale: %s, hours: %s)\n", sqlite.column_int(stmt, 0), name, scale, hours)
		}
		if !has_any do fmt.println("  No shops in this location.")
	}
	return 0
}

shop_set_inventory :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine shop set-inventory <id> <text>") }
		else { fmt.eprintln("Usage: ttrpg-engine shop set-inventory <id> <text>") }
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]
	sql := fmt.tprintf("UPDATE shops SET inventory='%s' WHERE id=%d", escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to set inventory") }
		else { fmt.eprintln("Failed to set inventory") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Inventory set","id":%d}` + "\n", id) }
	else { fmt.printf("Inventory set for shop %d\n", id) }
	return 0
}

// ----- encounters -----

encounter_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine encounter add <location_id> <type> [description] [npc_id]") }
		else { fmt.eprintln("Usage: ttrpg-engine encounter add <location_id> <type> [description] [npc_id]") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	type_str := args[2]
	description := len(args) > 3 ? args[3] : ""
	npc_id := len(args) > 4 ? strconv.atoi(args[4]) : 0

	npc_val: string
	if npc_id <= 0 {
		npc_val = "NULL"
	} else {
		npc_val = fmt.tprintf("%d", npc_id)
	}
	sql := fmt.tprintf(
		"INSERT INTO encounters (location_id, type, description, npc_id) VALUES (%d, '%s', '%s', %s)",
		location_id, escape_sql(type_str), escape_sql(description), npc_val,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to add encounter") }
		else { fmt.eprintln("Failed to add encounter") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Added encounter"}` + "\n") }
	else { fmt.printf("Added encounter (type: %s) to location %d\n", type_str, location_id) }
	return 0
}

encounter_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine encounter list <location_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine encounter list <location_id>") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, type, description, npc_id FROM encounters WHERE location_id=%d ORDER BY id", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to list encounters") }
		else { fmt.eprintln("Failed to list encounters") }
		return 1
	}
	defer sqlite.finalize(stmt)
	if db.is_json {
		first := true
		fmt.print("[")
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			fmt.printf(`{"id":%d,"type":"%s","description":"%s","npc_id":%d}`,
				sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2), sqlite.column_int(stmt, 3))
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			fmt.printf("  [%d] (%s) %s\n", sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2))
		}
		if !has_any do fmt.println("  No encounters in this location.")
	}
	return 0
}

// ----- setpieces -----

setpiece_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine setpiece add <location_id> <name> [description] [chapter_event]") }
		else { fmt.eprintln("Usage: ttrpg-engine setpiece add <location_id> <name> [description] [chapter_event]") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	name := args[2]
	description := len(args) > 3 ? args[3] : ""
	chapter_event := len(args) > 4 ? args[4] : ""

	sql := fmt.tprintf(
		"INSERT INTO setpieces (location_id, name, description, chapter_event) VALUES (%d, '%s', '%s', '%s')",
		location_id, escape_sql(name), escape_sql(description), escape_sql(chapter_event),
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to add setpiece") }
		else { fmt.eprintln("Failed to add setpiece") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Added setpiece: %s"}` + "\n", name) }
	else { fmt.printf("Added setpiece: %s\n", name) }
	return 0
}

setpiece_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine setpiece list <location_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine setpiece list <location_id>") }
		return 1
	}
	location_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter_event FROM setpieces WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to list setpieces") }
		else { fmt.eprintln("Failed to list setpieces") }
		return 1
	}
	defer sqlite.finalize(stmt)
	if db.is_json {
		first := true
		fmt.print("[")
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			fmt.printf(`{"id":%d,"name":"%s","description":"%s","chapter_event":"%s"}`,
				sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2), column_text_safe(stmt, 3))
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			name := column_text_safe(stmt, 1)
			event := column_text_safe(stmt, 3)
			event_str := ""
			if len(event) > 0 do event_str = fmt.tprintf(" [Event: %s]", event)
			fmt.printf("  [%d] %s%s\n", sqlite.column_int(stmt, 0), name, event_str)
		}
		if !has_any do fmt.println("  No setpieces in this location.")
	}
	return 0
}

// ----- relationship decay (O(1) per query) -----

// Compute the access score for a visitor trying to enter a property owned
// by owner_npc_id. Returns a normalized score in -1.0..1.0:
//   -1.0..-0.5  →  Hostile (denied)
//   -0.5..0.0   →  Wary
//    0.0..0.3   →  Neutral (allowed if not restricted)
//    0.3..0.7   →  Wary / Friendly
//    0.7..1.0   →  Trusted
// O(1) — single row lookup, one math.exp call.
compute_relationship_with_decay :: proc(
	db: ^lib.Db,
	visitor_npc_id: int,    // 0 if visitor is a character
	visitor_char_id: int,   // 0 if visitor is an NPC
	owner_npc_id: int,
	in_game_day: int,
) -> f32 {
	if owner_npc_id == 0 do return 0.0

	// O(1) single-row lookup: get the relationship between the visitor pair.
	stmt: ^sqlite.Statement
	sql: string
	if visitor_npc_id > 0 {
		sql = fmt.tprintf(
			"SELECT friendship_level, COALESCE(last_interaction_day, 0) FROM npc_relationships WHERE npc_id_1=%d AND npc_id_2=%d",
			visitor_npc_id, owner_npc_id,
		)
	} else if visitor_char_id > 0 {
		// Character → NPC. We use a convention: npc_id_1 = character_id (offset by 1_000_000
		// to disambiguate from NPC ids in the relationship table). For v15, just look up
		// the character's owner as the visitor. Future: separate character-npc relationship table.
		sql = fmt.tprintf(
			"SELECT friendship_level, COALESCE(last_interaction_day, 0) FROM npc_relationships WHERE npc_id_2=%d",
			owner_npc_id,
		)
	} else {
		return 0.0
	}
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return 0.0 }
	defer sqlite.finalize(stmt)

	level := 0
	last_interaction_day := 0
	if sqlite.step(stmt) == .Row {
		level = int(sqlite.column_int(stmt, 0))
		last_interaction_day = int(sqlite.column_int(stmt, 1))
	}

	effective := f32(level) / 10.0
	if last_interaction_day > 0 && in_game_day > 0 {
		decayed_level := compute_decay(level, last_interaction_day, in_game_day)
		effective = f32(decayed_level) / 10.0
	}
	return effective
}

// Access band: returns "allowed" / "wary" / "denied" / "trusted" given
// a score from compute_relationship_with_decay and a restricted flag.
access_band :: proc(score: f32, restricted: bool) -> string {
	if !restricted do return "allowed"
	if score < 0.0 do return "denied"
	if score < 0.3 do return "wary"
	if score < 0.7 do return "wary"
	return "trusted"
}

// Convenience: check whether a visitor can enter a property now.
// O(1) — two lookups (relationship row + restricted flag).
can_enter :: proc(
	db: ^lib.Db,
	visitor_npc_id: int,
	visitor_char_id: int,
	property_kind: string,  // "house" | "shop" | "location"
	property_id: int,
	in_game_day: int,
) -> string {
	if property_id <= 0 do return "allowed"

	restricted := 0
	owner_npc_id := 0
	open_hours := ""
	restricted_until := ""

	stmt: ^sqlite.Statement
	sql: string
	switch property_kind {
	case "house":    sql = fmt.tprintf("SELECT restricted, COALESCE(npc_id, 0), COALESCE(restricted_until, '') FROM houses WHERE id=%d", property_id)
	case "shop":     sql = fmt.tprintf("SELECT restricted, COALESCE(npc_id, 0), '', COALESCE(restricted_until, '') FROM shops WHERE id=%d", property_id)
	case "location": sql = fmt.tprintf("SELECT restricted, 0, '', COALESCE(restricted_until, '') FROM locations WHERE id=%d", property_id)
	case: return "allowed"
	}
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return "allowed" }
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) == .Row {
		restricted = int(sqlite.column_int(stmt, 0))
		owner_npc_id = int(sqlite.column_int(stmt, 1))
		open_hours = column_text_safe(stmt, 2)
		restricted_until = column_text_safe(stmt, 3)
	}
	_ = open_hours
	_ = restricted_until

	if restricted == 0 do return "allowed"

	score := compute_relationship_with_decay(db, visitor_npc_id, visitor_char_id, owner_npc_id, in_game_day)
	return access_band(score, true)
}
// ----- house residents (v17 join table for multi-resident properties) -----

house_add_resident :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house add-resident <house_id> <npc_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine house add-resident <house_id> <npc_id>") }
		return 1
	}
	house_id := strconv.atoi(args[1])
	npc_id := strconv.atoi(args[2])

	sql := fmt.tprintf("INSERT OR IGNORE INTO house_residents (house_id, npc_id) VALUES(%d, %d)", house_id, npc_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to add resident") }
		else { fmt.eprintln("Failed to add resident") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Resident added","house_id":%d,"npc_id":%d}` + "\n", house_id, npc_id) }
	else { fmt.printf("NPC %d added as resident of house %d\n", npc_id, house_id) }
	return 0
}

house_remove_resident :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house remove-resident <house_id> <npc_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine house remove-resident <house_id> <npc_id>") }
		return 1
	}
	house_id := strconv.atoi(args[1])
	npc_id := strconv.atoi(args[2])

	sql := fmt.tprintf("DELETE FROM house_residents WHERE house_id=%d AND npc_id=%d", house_id, npc_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { usage_error(db, "Failed to remove resident") }
		else { fmt.eprintln("Failed to remove resident") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Resident removed","house_id":%d,"npc_id":%d}` + "\n", house_id, npc_id) }
	else { fmt.printf("NPC %d removed from house %d\n", npc_id, house_id) }
	return 0
}

house_list_residents :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine house list-residents <house_id>") }
		else { fmt.eprintln("Usage: ttrpg-engine house list-residents <house_id>") }
		return 1
	}
	house_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT hr.npc_id, n.name FROM house_residents hr JOIN npcs n ON hr.npc_id = n.id WHERE hr.house_id=%d ORDER BY n.name", house_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to list residents") }
		else { fmt.eprintln("Failed to list residents") }
		return 1
	}
	defer sqlite.finalize(stmt)
	if db.is_json {
		first := true
		fmt.print("[")
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			fmt.printf(`{"npc_id":%d,"name":"%s"}`, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1))
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			fmt.printf("  NPC %d: %s\n", sqlite.column_int(stmt, 0), column_text_safe(stmt, 1))
		}
		if !has_any do fmt.println("  No residents.")
	}
	return 0
}
