package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

faction_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine faction create <name> <description>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine faction create <name> <description>")
		}
		return 1
	}
	name := args[1]
	desc := args[2]

	sql := fmt.tprintf("INSERT INTO factions (name,description) VALUES('%s','%s')", escape_sql(name), escape_sql(desc))

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create faction"}`)
		} else {
			fmt.eprintln("Failed to create faction")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created faction: %s"}}\n`, name)
	} else {
		fmt.println("Created faction:", name)
	}
	return 0
}

faction_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,description FROM factions ORDER BY name"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list factions"}`)
		} else {
			fmt.eprintln("Failed to list factions")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		builder := strings.builder_make()
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","description":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s - %s\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
	}
	return 0
}

faction_join :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine faction join <char|npc> <id> <faction_id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine faction join <char|npc> <id> <faction_id>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])
	faction_id := strconv.atoi(args[3])

	sql := ""
	if target_type == "char" {
		sql = fmt.tprintf("UPDATE characters SET faction_id=%d WHERE id=%d", faction_id, id)
	} else if target_type == "npc" {
		sql = fmt.tprintf("UPDATE npcs SET faction_id=%d WHERE id=%d", faction_id, id)
	} else {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Target type must be 'char' or 'npc'"}`)
		} else {
			fmt.eprintln("Target type must be 'char' or 'npc'")
		}
		return 1
	}

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to join faction"}`)
		} else {
			fmt.eprintln("Failed to join faction")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"%s %d joined faction %d","id":%d,"faction_id":%d}}\n`,
			target_type, id, faction_id, id, faction_id,
		)
	} else {
		fmt.printf("%s %d joined faction %d\n", target_type, id, faction_id)
	}
	return 0
}

print_faction_standings :: proc(stmt: ^sqlite.Statement, is_json: bool) {
	if is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			fmt.sbprintf(&builder, `{{"faction_id":{},"faction_name":"{}","standing":{},"notes":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("  %s (ID: %d): standing %d (%s)\n",
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 0),
				sqlite.column_int(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
	}
}

faction_set_standing :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine faction set-standing <character_id> <faction_id> <standing> [notes]"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine faction set-standing <character_id> <faction_id> <standing> [notes]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	faction_id := strconv.atoi(args[2])
	standing := strconv.atoi(args[3])
	notes := len(args) >= 5 ? args[4] : ""

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO faction_standings (character_id,faction_id,standing,notes) VALUES(%d,%d,%d,'%s')",
		char_id, faction_id, standing, escape_sql(notes),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set faction standing"}`)
		} else {
			fmt.eprintln("Failed to set faction standing")
		}
		return 1
	}

	// Touch last_interaction_day for decay tracking

	touch_faction_decay_day(db, char_id, faction_id)
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Standing set for character %d in faction %d","character_id":%d,"faction_id":%d,"standing":%d}}\n`, char_id, faction_id, char_id, faction_id, standing)
	} else {
		fmt.printf("Standing set for character %d in faction %d to %d\n", char_id, faction_id, standing)
	}
	return 0
}

faction_get_standing :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine faction get-standing <character_id> [faction_id]"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine faction get-standing <character_id> [faction_id]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	faction_id := 0
	if len(args) >= 3 do faction_id = strconv.atoi(args[2])

	// Compute current day for decay
	current_day := 0
	day_stmt: ^sqlite.Statement
	day_sql := fmt.tprintf("SELECT c.total_elapsed_hours/24 FROM characters ch JOIN campaigns c ON ch.campaign_id=c.id WHERE ch.id=%d", char_id)
	day_sql_c := cstring(raw_data(day_sql))
	if sqlite.prepare(db.ptr, day_sql_c, i32(len(day_sql)), &day_stmt, nil) == .Ok {
		if sqlite.step(day_stmt) == .Row {
			current_day = int(sqlite.column_int(day_stmt, 0))
		}
		sqlite.finalize(day_stmt)
	}

	stmt: ^sqlite.Statement
	sql := ""
	if faction_id > 0 {
		sql = fmt.tprintf("SELECT fs.faction_id, f.name, fs.standing, fs.notes, fs.last_interaction_day FROM faction_standings fs JOIN factions f ON fs.faction_id=f.id WHERE fs.character_id=%d AND fs.faction_id=%d", char_id, faction_id)
	} else {
		sql = fmt.tprintf("SELECT fs.faction_id, f.name, fs.standing, fs.notes, fs.last_interaction_day FROM faction_standings fs JOIN factions f ON fs.faction_id=f.id WHERE fs.character_id=%d", char_id)
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to get standings"}`)
		} else {
			fmt.eprintln("Failed to get standings")
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
			raw := int(sqlite.column_int(stmt, 2))
			last_day := int(sqlite.column_int(stmt, 4))
			decayed := compute_decay(raw, last_day, current_day)
			fmt.printf(`{{"faction_id":%d,"faction_name":"%s","standing":%d,"decayed":%d,"notes":"%s"}}`,
				sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), raw, decayed, column_text_safe(stmt, 3))
		}
		fmt.println("]")
	} else {
		fmt.printf("Faction standings for character %d:\n", char_id)
		for sqlite.step(stmt) == .Row {
			raw := int(sqlite.column_int(stmt, 2))
			last_day := int(sqlite.column_int(stmt, 4))
			decayed := compute_decay(raw, last_day, current_day)
			decay_note := ""
			if decayed != raw do decay_note = fmt.tprintf(" (decayed to %d)", decayed)
			fmt.printf("  %s (ID: %d): standing %d%s\n",
				column_text_safe(stmt, 1), sqlite.column_int(stmt, 0), raw, decay_note)
		}
	}
	return 0
}

print_party_faction_standings :: proc(stmt: ^sqlite.Statement, is_json: bool) {
	if is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			fmt.sbprintf(&builder, `{{"campaign_id":{},"faction_id":{},"faction_name":"{}","standing":{},"notes":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_text(stmt, 4),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("  Campaign %d — %s (ID: %d): standing %+d (%s)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 1),
				sqlite.column_int(stmt, 3),
				sqlite.column_text(stmt, 4),
			)
		}
	}
}

faction_set_party_standing :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		return print_error(db, "Usage: ttrpg-engine faction set-party-standing <campaign_id> <faction_id> <standing> [notes]")
	}
	campaign_id := strconv.atoi(args[1])
	faction_id := strconv.atoi(args[2])
	standing := strconv.atoi(args[3])
	notes := len(args) >= 5 ? args[4] : ""

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO party_faction_standings (campaign_id,faction_id,standing,notes) VALUES(%d,%d,%d,'%s')",
		campaign_id, faction_id, standing, escape_sql(notes),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		return print_error(db, "Failed to set party faction standing")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Party standing set for campaign %d in faction %d","campaign_id":%d,"faction_id":%d,"standing":%d}}` + "\n", campaign_id, faction_id, campaign_id, faction_id, standing)
	} else {
		fmt.printf("Party standing set for campaign %d in faction %d to %+d\n", campaign_id, faction_id, standing)
	}
	return 0
}

faction_get_party_standing :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine faction get-party-standing <campaign_id> [faction_id]")
	}
	campaign_id := strconv.atoi(args[1])
	faction_id := 0
	if len(args) >= 3 do faction_id = strconv.atoi(args[2])

	stmt: ^sqlite.Statement
	sql := ""
	if faction_id > 0 {
		sql = fmt.tprintf("SELECT ps.campaign_id, ps.faction_id, f.name, ps.standing, ps.notes FROM party_faction_standings ps JOIN factions f ON ps.faction_id=f.id WHERE ps.campaign_id=%d AND ps.faction_id=%d", campaign_id, faction_id)
	} else {
		sql = fmt.tprintf("SELECT ps.campaign_id, ps.faction_id, f.name, ps.standing, ps.notes FROM party_faction_standings ps JOIN factions f ON ps.faction_id=f.id WHERE ps.campaign_id=%d", campaign_id)
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to get party standings")
	}
	defer sqlite.finalize(stmt)

	if !db.is_json {
		fmt.printf("Party faction standings for campaign %d:\n", campaign_id)
	}
	print_party_faction_standings(stmt, db.is_json)
	return 0
}

faction_effective_standing :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine faction effective-standing <campaign_id> <faction_id>")
	}
	campaign_id := strconv.atoi(args[1])
	faction_id := strconv.atoi(args[2])

	party_standing := 0
	party_notes := ""
	stmt: ^sqlite.Statement
	party_sql := fmt.tprintf("SELECT standing, notes FROM party_faction_standings WHERE campaign_id=%d AND faction_id=%d", campaign_id, faction_id)
	party_c := cstring(raw_data(party_sql))
	if sqlite.prepare(db.ptr, party_c, i32(len(party_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row {
			party_standing = int(sqlite.column_int(stmt, 0))
			party_notes = strings.clone(column_text_safe(stmt, 1), context.temp_allocator)
		}
		sqlite.finalize(stmt)
	}

	char_count := 0
	char_sum := 0
	char_sql := fmt.tprintf("SELECT fs.standing FROM faction_standings fs JOIN characters c ON fs.character_id=c.id WHERE c.campaign_id=%d AND fs.faction_id=%d", campaign_id, faction_id)
	char_c := cstring(raw_data(char_sql))
	if sqlite.prepare(db.ptr, char_c, i32(len(char_sql)), &stmt, nil) == .Ok {
		for sqlite.step(stmt) == .Row {
			char_count += 1
			char_sum += int(sqlite.column_int(stmt, 0))
		}
		sqlite.finalize(stmt)
	}

	char_avg: f64 = 0.0
	if char_count > 0 do char_avg = f64(char_sum) / f64(char_count)
	effective := int(char_avg) + party_standing

	if db.is_json {
		fmt.printf(`{{"success":true,"faction_id":%d,"party_standing":%d,"party_notes":"%s","character_count":%d,"character_average":%.1f,"effective_standing":%d}}` + "\n",
			faction_id, party_standing, escape_json_string(party_notes), char_count, char_avg, effective)
	} else {
		fmt.printf("Effective faction %d standing for campaign %d:\n", faction_id, campaign_id)
		fmt.printf("  Party standing:    %+d", party_standing)
		if len(party_notes) > 0 do fmt.printf(" (%s)", party_notes)
		fmt.println()
		if char_count > 0 {
			fmt.printf("  Avg character rep: %.1f (over %d characters)\n", char_avg, char_count)
		} else {
			fmt.println("  Avg character rep: n/a (no character standings)")
		}
		fmt.printf("  Effective:         %+d  [canonical state is party standing; avg is display-only]\n", effective)
	}
	return 0
}

touch_faction_decay_day :: proc(db: ^lib.Db, char_id: int, faction_id: int) {
	stmt: ^sqlite.Statement
	camp_sql := fmt.tprintf("SELECT campaign_id FROM characters WHERE id=%d", char_id)
	camp_sql_c := cstring(raw_data(camp_sql))
	if sqlite.prepare(db.ptr, camp_sql_c, i32(len(camp_sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) != .Row {
		return
	}
	campaign_id := int(sqlite.column_int(stmt, 0))
	if campaign_id <= 0 {
		return
	}
	day, ok := get_current_day(db, campaign_id)
	if !ok {
		return
	}
	lib.db_exec(db, fmt.tprintf("UPDATE faction_standings SET last_interaction_day=%d WHERE character_id=%d AND faction_id=%d", day, char_id, faction_id))
}
