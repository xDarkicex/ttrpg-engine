package cmd

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

campaign_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine campaign create <name>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine campaign create <name>")
		}
		return 1
	}
	sql := fmt.tprintf("INSERT INTO campaigns (name) VALUES('%s')", escape_sql(args[1]))

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create campaign"}`)
		} else {
			fmt.eprintln("Failed to create campaign")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created campaign: %s"}}\n`, args[1])
	} else {
		fmt.println("Created campaign:", args[1])
	}
	return 0
}

campaign_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,chapter,session_num FROM campaigns ORDER BY id"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list campaigns"}`)
		} else {
			fmt.eprintln("Failed to list campaigns")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","chapter":"{}","session_num":{}}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s | Ch:%s S:%d\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 3),
			)
		}
	}
	return 0
}

campaign_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine campaign get <id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine campaign get <id>")
		}
		return 1
	}
	id := parse_int(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id,name,chapter,session_num FROM campaigns WHERE id=%d", id)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Campaign not found"}`)
		} else {
			fmt.eprintln("Campaign not found")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Campaign not found"}`)
		} else {
			fmt.eprintln("Campaign not found")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"id":%d,"name":"%s","chapter":"%s","session_num":%d}}\n`,
			sqlite.column_int(stmt, 0),
			sqlite.column_text(stmt, 1),
			sqlite.column_text(stmt, 2),
			sqlite.column_int(stmt, 3),
		)
	} else {
		fmt.printf("[%d] %s\n  Chapter: %s\n  Session: %d\n",
			sqlite.column_int(stmt, 0),
			sqlite.column_text(stmt, 1),
			sqlite.column_text(stmt, 2),
			sqlite.column_int(stmt, 3),
		)
	}
	return 0
}

campaign_delete :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine campaign delete <id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine campaign delete <id>")
		}
		return 1
	}
	id := parse_int(args[1])
	sql := fmt.tprintf("DELETE FROM campaigns WHERE id=%d", id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to delete campaign"}`)
		} else {
			fmt.eprintln("Failed to delete campaign")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Deleted campaign %d"}}\n`, id)
	} else {
		fmt.println("Deleted campaign", id)
	}
	return 0
}

campaign_set_chapter :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine campaign set-chapter <id> <chapter>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine campaign set-chapter <id> <chapter>")
		}
		return 1
	}
	id := parse_int(args[1])
	sql := fmt.tprintf("UPDATE campaigns SET chapter='%s' WHERE id=%d", escape_sql(args[2]), id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set chapter"}`)
		} else {
			fmt.eprintln("Failed to set chapter")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Chapter set to: %s"}}\n`, args[2])
	} else {
		fmt.println("Chapter set to:", args[2])
	}
	return 0
}

campaign_next_session :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: ttrpg-engine campaign next-session <id>"}`)
		} else {
			fmt.eprintln("Usage: ttrpg-engine campaign next-session <id>")
		}
		return 1
	}
	id := parse_int(args[1])
	sql := fmt.tprintf("UPDATE campaigns SET session_num=session_num+1 WHERE id=%d", id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to advance session"}`)
		} else {
			fmt.eprintln("Failed to advance session")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Session advanced for campaign %d"}}\n`, id)
	} else {
		fmt.println("Session advanced for campaign", id)
	}
	return 0
}

column_text_safe :: proc(stmt: ^sqlite.Statement, col: i32) -> string {
	ptr := sqlite.column_text(stmt, col)
	if ptr == nil do return ""
	return string(ptr)
}

print_error :: proc(db: ^lib.Db, text_err: string, json_err: string = "") -> int {
	if db.is_json {
		msg := json_err != "" ? json_err : text_err
		fmt.printf(`{{"success":false,"error":"%s"}}\n`, msg)
	} else {
		fmt.eprintln(text_err)
	}
	return 1
}

parse_opt_id :: proc(args: []string, index: int) -> string {
	if len(args) > index && args[index] != "NULL" && args[index] != "" && args[index] != "0" {
		return fmt.tprintf("%d", strconv.atoi(args[index]))
	}
	return "NULL"
}

parse_opt_int :: proc(args: []string, index: int, default_val: int) -> int {
	if len(args) > index {
		return strconv.atoi(args[index])
	}
	return default_val
}

parse_opt_string :: proc(args: []string, index: int, default_val: string) -> string {
	if len(args) > index {
		return args[index]
	}
	return default_val
}

validate_actor_type :: proc(actor_type: string) -> (string, bool) {
	if actor_type == "char" || actor_type == "character" {
		return "character", true
	}
	if actor_type == "npc" {
		return "npc", true
	}
	return "", false
}

get_actor_name :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> string {
	stmt: ^sqlite.Statement
	sql := ""
	if actor_type == "character" {
		sql = fmt.tprintf("SELECT name FROM characters WHERE id = %d", actor_id)
	} else if actor_type == "npc" {
		sql = fmt.tprintf("SELECT name FROM npcs WHERE id = %d", actor_id)
	} else {
		return ""
	}
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return ""
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return fmt.tprintf("%s", column_text_safe(stmt, 0))
	}
	return ""
}

check_actor_exists :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> bool {
	stmt: ^sqlite.Statement
	sql := ""
	if actor_type == "character" {
		sql = fmt.tprintf("SELECT 1 FROM characters WHERE id=%d", actor_id)
	} else if actor_type == "npc" {
		sql = fmt.tprintf("SELECT 1 FROM npcs WHERE id=%d", actor_id)
	} else {
		return false
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return false
	}
	defer sqlite.finalize(stmt)
	return sqlite.step(stmt) == .Row
}

get_last_insert_id :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql := "SELECT last_insert_rowid()"
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

escape_json_string :: proc(s: string) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == '"' {
			strings.write_string(&builder, "\\\"")
		} else if c == '\\' {
			strings.write_string(&builder, "\\\\")
		} else if c == '\n' {
			strings.write_string(&builder, "\\n")
		} else if c == '\r' {
			strings.write_string(&builder, "\\r")
		} else if c == '\t' {
			strings.write_string(&builder, "\\t")
		} else {
			strings.write_byte(&builder, c)
		}
	}
	return strings.to_string(builder)
}

print_json_actors :: proc(builder: ^strings.Builder, actors_str: string) {
	strings.write_string(builder, "[")
	if actors_str != "" {
		parts := strings.split(actors_str, ",", context.temp_allocator)
		first := true
		for part in parts {
			subparts := strings.split(part, ":", context.temp_allocator)
			if len(subparts) == 2 {
				if !first do strings.write_string(builder, ",")
				first = false
				strings.write_string(builder, "{")
				fmt.sbprintf(builder, "\"type\":\"%s\",\"id\":%d", subparts[0], strconv.atoi(subparts[1]))
				strings.write_string(builder, "}")
			}
		}
	}
	strings.write_string(builder, "]")
}

format_text_actors :: proc(db: ^lib.Db, actors_str: string) -> string {
	if actors_str == "" do return "None"
	parts := strings.split(actors_str, ",", context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)
	first := true
	for part in parts {
		subparts := strings.split(part, ":", context.temp_allocator)
		if len(subparts) == 2 {
			if !first do strings.write_string(&builder, ", ")
			first = false
			type := subparts[0]
			id := strconv.atoi(subparts[1])
			name := get_actor_name(db, type, id)
			if name != "" {
				fmt.sbprintf(&builder, "%s #%d (%s)", type, id, name)
			} else {
				fmt.sbprintf(&builder, "%s #%d", type, id)
			}
		}
	}
	return strings.to_string(builder)
}

print_json_locations_stmt :: proc(stmt: ^sqlite.Statement) {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		is_curr := sqlite.column_int(stmt, 4) != 0 ? "true" : "false"
		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, "\"id\":%d,\"name\":\"%s\",\"description\":\"%s\",\"chapter\":\"%s\",\"is_current\":%s",
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			escape_json_string(column_text_safe(stmt, 3)),
			is_curr,
		)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.println(strings.to_string(builder))
}

print_text_locations_stmt :: proc(stmt: ^sqlite.Statement) {
	for sqlite.step(stmt) == .Row {
		is_curr := sqlite.column_int(stmt, 4) != 0
		active_str := is_curr ? "[ACTIVE] " : "         "
		fmt.printf("  %s%2d - %s: %s (Chapter: %s)\n",
			active_str,
			sqlite.column_int(stmt, 0),
			column_text_safe(stmt, 1),
			column_text_safe(stmt, 2),
			column_text_safe(stmt, 3),
		)
	}
}

print_json_actions_stmt :: proc(db: ^lib.Db, stmt: ^sqlite.Statement) {
	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false

		loc_id := sqlite.column_int(stmt, 2)
		loc_name := column_text_safe(stmt, 3)
		fac_id := sqlite.column_int(stmt, 4)
		fac_name := column_text_safe(stmt, 5)

		loc_id_str := loc_id > 0 ? fmt.tprintf("%d", loc_id) : "null"
		loc_name_str := loc_id > 0 ? fmt.tprintf(`"%s"`, escape_json_string(loc_name)) : "null"
		fac_id_str := fac_id > 0 ? fmt.tprintf("%d", fac_id) : "null"
		fac_name_str := fac_id > 0 ? fmt.tprintf(`"%s"`, escape_json_string(fac_name)) : "null"

		actors_str := column_text_safe(stmt, 10)

		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, "\"id\":%d,\"description\":\"%s\",\"location_id\":%s,\"location_name\":%s,\"standing_faction_id\":%s,\"standing_faction_name\":%s,\"standing_impact\":%d,\"story_progression\":%d,\"status\":\"%s\",\"created_at\":\"%s\",\"actors\":",
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			loc_id_str,
			loc_name_str,
			fac_id_str,
			fac_name_str,
			sqlite.column_int(stmt, 6),
			sqlite.column_int(stmt, 7),
			column_text_safe(stmt, 8),
			column_text_safe(stmt, 9),
		)
		print_json_actors(&builder, actors_str)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.println(strings.to_string(builder))
}

print_text_actions_stmt :: proc(db: ^lib.Db, stmt: ^sqlite.Statement) {
	for sqlite.step(stmt) == .Row {
		id := sqlite.column_int(stmt, 0)
		desc := column_text_safe(stmt, 1)
		loc_id := sqlite.column_int(stmt, 2)
		loc_name := column_text_safe(stmt, 3)
		fac_id := sqlite.column_int(stmt, 4)
		fac_name := column_text_safe(stmt, 5)
		impact := sqlite.column_int(stmt, 6)
		prog := sqlite.column_int(stmt, 7)
		status := column_text_safe(stmt, 8)
		created := column_text_safe(stmt, 9)
		actors_str := column_text_safe(stmt, 10)

		fmt.printf("  [Action #%d] [%s] - %s\n", id, status, desc)
		fmt.printf("    Created: %s\n", created)
		if loc_id > 0 {
			fmt.printf("    Location: %s (ID: %d)\n", loc_name, loc_id)
		}
		if fac_id > 0 {
			fmt.printf("    Faction Impact: %s (ID: %d) standing %+d\n", fac_name, fac_id, impact)
		}
		fmt.printf("    Story Progression: %+d\n", prog)
		actors_formatted := format_text_actors(db, actors_str)
		fmt.printf("    Actors: %s\n", actors_formatted)
	}
}

campaign_add_location :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		return print_error(db, "Usage: ttrpg-engine campaign add-location <campaign_id> <name> <description> [chapter]")
	}

	campaign_id := strconv.atoi(args[1])
	name := args[2]
	description := args[3]
	chapter := len(args) >= 5 ? args[4] : ""

	sql := fmt.tprintf(
		"INSERT INTO locations (campaign_id, name, description, chapter) VALUES (%d, '%s', '%s', '%s')",
		campaign_id, escape_sql(name), escape_sql(description), escape_sql(chapter),
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to add location")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added location: %s to campaign %d"}}\n`, name, campaign_id)
	} else {
		fmt.printf("Added location: %s (Campaign: %d)\n", name, campaign_id)
	}
	return 0
}

campaign_set_location :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine campaign set-location <campaign_id> <location_id>")
	}

	campaign_id := strconv.atoi(args[1])
	location_id := strconv.atoi(args[2])

	stmt: ^sqlite.Statement
	check_sql := fmt.tprintf("SELECT 1 FROM locations WHERE campaign_id=%d AND id=%d", campaign_id, location_id)
	check_c := cstring(raw_data(check_sql))
	if sqlite.prepare(db.ptr, check_c, i32(len(check_sql)), &stmt, nil) != .Ok {
		return print_error(db, "Database error checking location")
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		return print_error(db, "Location not found in campaign")
	}

	reset_sql := fmt.tprintf("UPDATE locations SET is_current=0 WHERE campaign_id=%d", campaign_id)
	lib.db_exec(db, reset_sql)

	set_sql := fmt.tprintf("UPDATE locations SET is_current=1 WHERE campaign_id=%d AND id=%d", campaign_id, location_id)
	if lib.db_exec(db, set_sql) != .None {
		return print_error(db, "Failed to set current location")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Current location set to %d for campaign %d"}}\n`, location_id, campaign_id)
	} else {
		fmt.printf("Current location set to ID %d for campaign %d\n", location_id, campaign_id)
	}
	return 0
}

campaign_list_locations :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine campaign list-locations <campaign_id>")
	}

	campaign_id := strconv.atoi(args[1])
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter, is_current FROM locations WHERE campaign_id=%d ORDER BY id", campaign_id)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to list locations")
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		print_json_locations_stmt(stmt)
	} else {
		fmt.printf("Locations for campaign %d:\n", campaign_id)
		print_text_locations_stmt(stmt)
	}
	return 0
}

campaign_add_action :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine campaign add-action <campaign_id> <description> [location_id] [faction_id] [standing_impact] [story_progression] [status]")
	}

	campaign_id := strconv.atoi(args[1])
	description := args[2]

	location_sql := parse_opt_id(args, 3)
	faction_sql := parse_opt_id(args, 4)
	standing_impact := parse_opt_int(args, 5, 0)
	story_progression := parse_opt_int(args, 6, 1)
	status := parse_opt_string(args, 7, "completed")

	sql := fmt.tprintf(
		"INSERT INTO story_actions (campaign_id, location_id, description, standing_faction_id, standing_impact, story_progression, status) VALUES (%d, %s, '%s', %s, %d, %d, '%s')",
		campaign_id, location_sql, escape_sql(description), faction_sql, standing_impact, story_progression, escape_sql(status),
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to add story action")
	}

	action_id := get_last_insert_id(db)

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Logged story action","action_id":%d}}\n`, action_id)
	} else {
		fmt.printf("Logged story action with ID %d\n", action_id)
	}
	return 0
}

campaign_link_actor :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		return print_error(db, "Usage: ttrpg-engine campaign link-actor <action_id> <char|npc> <actor_id>")
	}

	action_id := strconv.atoi(args[1])
	actor_id := strconv.atoi(args[3])
	actor_type, type_ok := validate_actor_type(args[2])
	if !type_ok {
		return print_error(db, "Actor type must be 'char' or 'npc'")
	}

	if !check_actor_exists(db, actor_type, actor_id) {
		err_msg := fmt.tprintf("%s with ID %d not found", actor_type, actor_id)
		return print_error(db, err_msg)
	}

	sql := fmt.tprintf(
		"INSERT OR IGNORE INTO story_action_actors (action_id, actor_type, actor_id) VALUES (%d, '%s', %d)",
		action_id, actor_type, actor_id,
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to link actor to story action")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Linked %s %d to action %d"}}\n`, actor_type, actor_id, action_id)
	} else {
		fmt.printf("Linked %s %d to action %d\n", actor_type, actor_id, action_id)
	}
	return 0
}

campaign_list_actions :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine campaign list-actions <campaign_id> [location_id]")
	}

	campaign_id := strconv.atoi(args[1])
	location_id := len(args) >= 3 ? strconv.atoi(args[2]) : 0

	stmt: ^sqlite.Statement
	sql := ""
	if location_id > 0 {
		sql = fmt.tprintf(
			"SELECT sa.id, sa.description, sa.location_id, l.name, sa.standing_faction_id, f.name, sa.standing_impact, sa.story_progression, sa.status, sa.created_at, (SELECT group_concat(saa.actor_type || ':' || saa.actor_id) FROM story_action_actors saa WHERE saa.action_id = sa.id) AS actors FROM story_actions sa LEFT JOIN locations l ON sa.location_id = l.id LEFT JOIN factions f ON sa.standing_faction_id = f.id WHERE sa.campaign_id = %d AND sa.location_id = %d ORDER BY sa.id",
			campaign_id, location_id,
		)
	} else {
		sql = fmt.tprintf(
			"SELECT sa.id, sa.description, sa.location_id, l.name, sa.standing_faction_id, f.name, sa.standing_impact, sa.story_progression, sa.status, sa.created_at, (SELECT group_concat(saa.actor_type || ':' || saa.actor_id) FROM story_action_actors saa WHERE saa.action_id = sa.id) AS actors FROM story_actions sa LEFT JOIN locations l ON sa.location_id = l.id LEFT JOIN factions f ON sa.standing_faction_id = f.id WHERE sa.campaign_id = %d ORDER BY sa.id",
			campaign_id,
		)
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to list story actions")
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		print_json_actions_stmt(db, stmt)
	} else {
		fmt.printf("Story actions for campaign %d:\n", campaign_id)
		print_text_actions_stmt(db, stmt)
	}
	return 0
}

print_json_campaign_details :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, chapter, session_num, dm_notes, in_game_day, in_game_time, current_season FROM campaigns WHERE id=%d", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("null")
		return
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) == .Row {
		fmt.print("{")
		fmt.printf("\"id\":%d,\"name\":\"%s\",\"chapter\":\"%s\",\"session_num\":%d,\"dm_notes\":\"%s\",\"in_game_day\":%d,\"in_game_time\":\"%s\",\"current_season\":\"%s\"",
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			column_text_safe(stmt, 2),
			sqlite.column_int(stmt, 3),
			escape_json_string(column_text_safe(stmt, 4)),
			sqlite.column_int(stmt, 5),
			column_text_safe(stmt, 6),
			column_text_safe(stmt, 7),
		)
		fmt.print("}")
	} else {
		fmt.print("null")
	}
}

print_json_locations_by_id :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter, is_current FROM locations WHERE campaign_id=%d ORDER BY id", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)
	print_json_locations_stmt(stmt)
}

print_json_standings_by_id :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT fs.character_id, c.name, fs.faction_id, f.name, fs.standing, fs.notes FROM faction_standings fs JOIN characters c ON fs.character_id = c.id JOIN factions f ON fs.faction_id = f.id WHERE c.campaign_id = %d ORDER BY c.name, f.name",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, "\"character_id\":%d,\"character_name\":\"%s\",\"faction_id\":%d,\"faction_name\":\"%s\",\"standing\":%d,\"notes\":\"%s\"",
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			sqlite.column_int(stmt, 2),
			escape_json_string(column_text_safe(stmt, 3)),
			sqlite.column_int(stmt, 4),
			escape_json_string(column_text_safe(stmt, 5)),
		)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_party_standings :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT ps.campaign_id, ps.faction_id, f.name, ps.standing, ps.notes FROM party_faction_standings ps JOIN factions f ON ps.faction_id = f.id WHERE ps.campaign_id = %d ORDER BY f.name",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, "\"campaign_id\":%d,\"faction_id\":%d,\"faction_name\":\"%s\",\"standing\":%d,\"notes\":\"%s\"",
			sqlite.column_int(stmt, 0),
			sqlite.column_int(stmt, 1),
			escape_json_string(column_text_safe(stmt, 2)),
			sqlite.column_int(stmt, 3),
			escape_json_string(column_text_safe(stmt, 4)),
		)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_npc_relationships :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT r.npc_id_1, n1.name, r.npc_id_2, n2.name, r.friendship_level, r.type, r.notes, r.last_interaction_at FROM npc_relationships r JOIN npcs n1 ON r.npc_id_1 = n1.id JOIN npcs n2 ON r.npc_id_2 = n2.id WHERE n1.campaign_id = %d ORDER BY r.friendship_level DESC",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		fmt.sbprintf(&builder, `{{"npc_id_1":{},"npc_name_1":"{}","npc_id_2":{},"npc_name_2":"{}","friendship_level":{},"type":"{}","notes":"{}","last_interaction_at":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			sqlite.column_int(stmt, 2),
			escape_json_string(column_text_safe(stmt, 3)),
			sqlite.column_int(stmt, 4),
			column_text_safe(stmt, 5),
			escape_json_string(column_text_safe(stmt, 6)),
			column_text_safe(stmt, 7),
		)
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_parties :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	parties_sql := fmt.tprintf("SELECT id, name, notes, COALESCE(location_id,0), treasury_gold, treasury_silver, treasury_copper FROM parties WHERE campaign_id=%d ORDER BY name", campaign_id)
	parties_c := cstring(raw_data(parties_sql))
	if sqlite.prepare(db.ptr, parties_c, i32(len(parties_sql)), &stmt, nil) != .Ok { fmt.print("[]"); return }
	defer sqlite.finalize(stmt)

	fmt.print("[")
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do fmt.print(",")
		first = false
		pid := int(sqlite.column_int(stmt, 0))
		pname := column_text_safe(stmt, 1)
		pnotes := column_text_safe(stmt, 2)
		ploc := int(sqlite.column_int(stmt, 3))
		pgold := int(sqlite.column_int(stmt, 4))
		psilver := int(sqlite.column_int(stmt, 5))
		pcopper := int(sqlite.column_int(stmt, 6))

		fmt.printf(`{"id":%d,"name":"%s","notes":"%s","location_id":%d,"treasury":{"gold":%d,"silver":%d,"copper":%d},"members":[`, pid, escape_json_string(pname), escape_json_string(pnotes), ploc, pgold, psilver, pcopper)

		mem_stmt: ^sqlite.Statement
		mem_sql := fmt.tprintf("SELECT id, name, current_hp, max_hp, ac FROM characters WHERE party_id=%d ORDER BY name", pid)
		mem_c := cstring(raw_data(mem_sql))
		if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) == .Ok {
			first_mem := true
			for sqlite.step(mem_stmt) == .Row {
				if !first_mem do fmt.print(",")
				first_mem = false
				fmt.printf(`{"id":%d,"name":"%s","hp":%d,"max_hp":%d,"ac":%d}`, int(sqlite.column_int(mem_stmt, 0)), escape_json_string(column_text_safe(mem_stmt, 1)), int(sqlite.column_int(mem_stmt, 2)), int(sqlite.column_int(mem_stmt, 3)), int(sqlite.column_int(mem_stmt, 4)))
			}
			sqlite.finalize(mem_stmt)
		}
		fmt.print("]}")
	}
	fmt.print("]")
}

print_json_factions :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id, name, description FROM factions ORDER BY id"
	sql_c := cstring(raw_data(sql_str))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		fmt.sbprintf(&builder, `{{"id":{},"name":"{}","description":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
		)
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_actions_by_id :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT sa.id, sa.description, sa.location_id, l.name, sa.standing_faction_id, f.name, sa.standing_impact, sa.story_progression, sa.status, sa.created_at, (SELECT group_concat(saa.actor_type || ':' || saa.actor_id) FROM story_action_actors saa WHERE saa.action_id = sa.id) AS actors FROM story_actions sa LEFT JOIN locations l ON sa.location_id = l.id LEFT JOIN factions f ON sa.standing_faction_id = f.id WHERE sa.campaign_id = %d ORDER BY sa.id",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)
	print_json_actions_stmt(db, stmt)
}

print_text_story_state :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT c.name, c.chapter, c.session_num, c.dm_notes, c.in_game_day, c.in_game_time, c.current_season, (SELECT name FROM locations WHERE campaign_id=c.id AND is_current=1 LIMIT 1) FROM campaigns c WHERE c.id=%d", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.eprintln("Failed to prepare campaign details query")
		return
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		fmt.eprintln("Campaign not found")
		return
	}

	camp_name := sqlite.column_text(stmt, 0)
	chapter := sqlite.column_text(stmt, 1)
	session_num := sqlite.column_int(stmt, 2)
	dm_notes := sqlite.column_text(stmt, 3)
	in_game_day := sqlite.column_int(stmt, 4)
	in_game_time := sqlite.column_text(stmt, 5)
	current_season := sqlite.column_text(stmt, 6)
	curr_loc := sqlite.column_text(stmt, 7)
	curr_loc_str := curr_loc != nil ? string(curr_loc) : "None"
	dm_notes_str := dm_notes != nil ? string(dm_notes) : ""

	fmt.println("================================================================================")
	fmt.printf("CAMPAIGN REPORT: %s (ID: %d)\n", camp_name, campaign_id)
	fmt.println("================================================================================")
	fmt.printf("Chapter: %s | Session: %d | Day: %d | %s, %s\n", chapter, session_num, in_game_day, in_game_time, current_season)
	fmt.printf("Current Active Location: %s\n\n", curr_loc_str)

	if len(dm_notes_str) > 0 {
		fmt.println("--------------------------------------------------------------------------------")
		fmt.println("DM NOTES")
		fmt.println("--------------------------------------------------------------------------------")
		fmt.println(dm_notes_str)
		fmt.println()
	}

	print_text_journal_entries(db, campaign_id, 10)
	print_text_quests(db, campaign_id)
	print_text_locations_tree(db, campaign_id)
	print_text_npc_relationships(db, campaign_id)
	print_text_story_state_standings(db, campaign_id)
		print_text_party_standings(db, campaign_id)
		print_text_combat(db, campaign_id)
	print_text_story_state_actions(db, campaign_id)
}

print_text_locations_tree :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("LOCATIONS")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter, is_current, COALESCE(parent_id,0), restricted, restricted_until FROM locations WHERE campaign_id=%d ORDER BY id", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.println("  No locations.")
		fmt.println()
		return
	}
	defer sqlite.finalize(stmt)

	has_any := false
	for sqlite.step(stmt) == .Row {
		has_any = true
		loc_id := int(sqlite.column_int(stmt, 0))
		name := column_text_safe(stmt, 1)
		desc := column_text_safe(stmt, 2)
		chapter := column_text_safe(stmt, 3)
		is_curr := sqlite.column_int(stmt, 4) != 0
		restricted := sqlite.column_int(stmt, 6) != 0

		active_str := is_curr ? "[ACTIVE] " : "         "
		restr_str := restricted ? " (restricted)" : ""
		fmt.printf("  %s[%d] %s%s: %s (Chapter: %s)\n", active_str, loc_id, name, restr_str, desc, chapter)

		print_text_sub_locations(db, loc_id, "    ")
		print_text_houses(db, loc_id, "    ")
		print_text_shops(db, loc_id, "    ")
		print_text_encounters(db, loc_id, "    ")
		print_text_setpieces(db, loc_id, "    ")
		print_text_npcs_at(db, loc_id, "    ")
		print_text_characters_at(db, loc_id, "    ")
		print_text_creatures_at(db, loc_id, "    ")
		fmt.println()
	}
	if !has_any do fmt.println("  No locations.")
	fmt.println()
}

print_text_story_state_standings :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("CHARACTER FACTION STANDINGS")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT fs.character_id, c.name, fs.faction_id, f.name, fs.standing, fs.notes FROM faction_standings fs JOIN characters c ON fs.character_id = c.id JOIN factions f ON fs.faction_id = f.id WHERE c.campaign_id = %d ORDER BY c.name, f.name",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		last_char_id := 0
		for sqlite.step(stmt) == .Row {
			char_id := int(sqlite.column_int(stmt, 0))
			char_name := sqlite.column_text(stmt, 1)
			fac_name := sqlite.column_text(stmt, 3)
			standing := sqlite.column_int(stmt, 4)
			notes := sqlite.column_text(stmt, 5)

			if char_id != last_char_id {
				last_char_id = char_id
				fmt.printf("  Character: %s (ID: %d)\n", char_name, char_id)
			}
			fmt.printf("    - %s: standing %+d (%s)\n", fac_name, standing, notes)
		}
	}
	fmt.println()
}

print_text_party_standings :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("PARTY FACTION STANDINGS")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT ps.campaign_id, ps.faction_id, f.name, ps.standing, ps.notes FROM party_faction_standings ps JOIN factions f ON ps.faction_id = f.id WHERE ps.campaign_id = %d ORDER BY f.name",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			fac_name := sqlite.column_text(stmt, 2)
			standing := sqlite.column_int(stmt, 3)
			notes := sqlite.column_text(stmt, 4)
			fmt.printf("  %s: party standing %+d (%s)\n", fac_name, standing, notes)
		}
		if !has_any do fmt.println("  No party faction standings defined.")
	}
	fmt.println()
}

print_text_story_state_actions :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("STORY LOG (Chronological)")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT sa.id, sa.description, sa.location_id, l.name, sa.standing_faction_id, f.name, sa.standing_impact, sa.story_progression, sa.status, sa.created_at, (SELECT group_concat(saa.actor_type || ':' || saa.actor_id) FROM story_action_actors saa WHERE saa.action_id = sa.id) AS actors FROM story_actions sa LEFT JOIN locations l ON sa.location_id = l.id LEFT JOIN factions f ON sa.standing_faction_id = f.id WHERE sa.campaign_id = %d ORDER BY sa.id",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		print_text_actions_stmt(db, stmt)
	}
}

campaign_get_story_state :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine campaign get-story-state <campaign_id>")
	}

	campaign_id := strconv.atoi(args[1])

	if db.is_json {
		fmt.print(`{"success":true`)
		fmt.print(`,"campaign":`)
		print_json_campaign_details(db, campaign_id)
		fmt.print(`,"journal":`)
		print_json_journal_for_state(db, campaign_id)
		fmt.print(`,"quests":`)
		print_json_quests_for_state(db, campaign_id)
		fmt.print(`,"locations_tree":`)
		print_json_locations_tree(db, campaign_id)
		fmt.print(`,"parties":`)
		print_json_parties(db, campaign_id)
		fmt.print(`,"factions":`)
		print_json_factions(db, campaign_id)
		fmt.print(`,"npc_relationships":`)
		print_json_npc_relationships(db, campaign_id)
		fmt.print(`,"character_faction_standings":`)
		print_json_standings_by_id(db, campaign_id)
		fmt.print(`,"party_faction_standings":`)
		print_json_party_standings(db, campaign_id)
		fmt.print(`,"combat":`)
		print_json_combat(db, campaign_id)
		fmt.print(`,"story_actions":`)
		print_json_actions_by_id(db, campaign_id)
		fmt.println(`}`)
	} else {
		print_text_story_state(db, campaign_id)
	}
	return 0
}

// v18: campaign journal entries for AI session continuity.
// The AI stores recaps as free-text entries; get-story-state loads the last N
// to reconstruct game state from a cold load.

campaign_add_journal_entry :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		return print_error(db, "Usage: ttrpg-engine campaign add-journal-entry <campaign_id> <entry_type> <description> [location_id] [session_num]")
	}

	campaign_id := strconv.atoi(args[1])
	entry_type := args[2]
	description := args[3]
	location_sql := parse_opt_id(args, 4)
	session_num := parse_opt_int(args, 5, 0)

	sql := fmt.tprintf(
		"INSERT INTO campaign_journal (campaign_id, entry_type, description, location_id, session_num) VALUES (%d, '%s', '%s', %s, %d)",
		campaign_id, escape_sql(entry_type), escape_sql(description), location_sql, session_num,
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to add journal entry")
	}

	entry_id := get_last_insert_id(db)
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Journal entry added","entry_id":{}}}`+"\n", entry_id)
	} else {
		fmt.printf("Journal entry #%d added (type: %s)\n", entry_id, entry_type)
	}
	return 0
}

campaign_list_journal :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine campaign list-journal <campaign_id> [limit]")
	}

	campaign_id := strconv.atoi(args[1])
	limit := parse_opt_int(args, 2, 10)

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT j.id, j.session_num, j.entry_type, j.description, j.location_id, l.name, j.created_at FROM campaign_journal j LEFT JOIN locations l ON j.location_id = l.id WHERE j.campaign_id = %d ORDER BY j.id DESC LIMIT %d",
		campaign_id, limit,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to list journal entries")
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			loc_id := sqlite.column_int(stmt, 4)
			loc_name := loc_id > 0 ? fmt.tprintf(`"%s"`, escape_json_string(column_text_safe(stmt, 5))) : "null"
			loc_id_str := loc_id > 0 ? fmt.tprintf("%d", loc_id) : "null"
			strings.write_string(&builder, "{")
			fmt.sbprintf(&builder, `"id":%d,"session_num":%d,"entry_type":"%s","description":"%s","location_id":%s,"location_name":%s,"created_at":"%s"`,
				sqlite.column_int(stmt, 0),
				sqlite.column_int(stmt, 1),
				column_text_safe(stmt, 2),
				escape_json_string(column_text_safe(stmt, 3)),
				loc_id_str,
				loc_name,
				column_text_safe(stmt, 6),
			)
			strings.write_string(&builder, "}")
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			entry_type := column_text_safe(stmt, 2)
			loc_name := column_text_safe(stmt, 5)
			created := column_text_safe(stmt, 6)
			fmt.printf("  [#%d] [%s] S%d \u2014 %s\n", sqlite.column_int(stmt, 0), entry_type, sqlite.column_int(stmt, 1), column_text_safe(stmt, 3))
			if len(loc_name) > 0 {
				fmt.printf("    Location: %s | %s\n", loc_name, created)
			} else {
				fmt.printf("    %s\n", created)
			}
		}
	}
	return 0
}

campaign_set_dm_notes :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine campaign set-dm-notes <campaign_id> <text>")
	}

	campaign_id := strconv.atoi(args[1])
	notes := args[2]
	sql := fmt.tprintf("UPDATE campaigns SET dm_notes='%s' WHERE id=%d", escape_sql(notes), campaign_id)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to set DM notes")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"DM notes updated","campaign_id":{}}}`+"\n", campaign_id)
	} else {
		fmt.printf("DM notes updated for campaign %d\n", campaign_id)
	}
	return 0
}

campaign_set_time :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		return print_error(db, "Usage: ttrpg-engine campaign set-time <campaign_id> <in_game_day> <time_of_day> <season>")
	}

	campaign_id := strconv.atoi(args[1])
	day := strconv.atoi(args[2])
	time_of_day := args[3]
	season := args[4]

	sql := fmt.tprintf(
		"UPDATE campaigns SET in_game_day=%d, in_game_time='%s', current_season='%s' WHERE id=%d",
		day, escape_sql(time_of_day), escape_sql(season), campaign_id,
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to set time")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Time updated","campaign_id":{},"in_game_day":{},"in_game_time":"{}","current_season":"{}"}}`+"\n", campaign_id, day, time_of_day, season)
	} else {
		fmt.printf("Campaign %d time: Day %d, %s, %s\n", campaign_id, day, time_of_day, season)
	}
	return 0
}

// v18: journal entries for get-story-state context packet.

print_json_journal_for_state :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT id, session_num, entry_type, description, location_id, created_at FROM campaign_journal WHERE campaign_id=%d ORDER BY id DESC LIMIT 10",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		loc_id := sqlite.column_int(stmt, 4)
		loc_id_str := loc_id > 0 ? fmt.tprintf("%d", loc_id) : "null"
		fmt.sbprintf(&builder, `{{"id":{},"session_num":{},"entry_type":"{}","description":"{}","location_id":{},"created_at":"{}"}}`,
			sqlite.column_int(stmt, 0),
			sqlite.column_int(stmt, 1),
			column_text_safe(stmt, 2),
			escape_json_string(column_text_safe(stmt, 3)),
			loc_id_str,
			column_text_safe(stmt, 5),
		)
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_text_journal_entries :: proc(db: ^lib.Db, campaign_id: int, limit: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT id, session_num, entry_type, description FROM campaign_journal WHERE campaign_id=%d ORDER BY id DESC LIMIT %d",
		campaign_id, limit,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("JOURNAL (last entries)")
	fmt.println("--------------------------------------------------------------------------------")
	has_any := false
	for sqlite.step(stmt) == .Row {
		has_any = true
		fmt.printf("  [#%d] [%s] S%d \u2014 %s\n",
			sqlite.column_int(stmt, 0),
			column_text_safe(stmt, 2),
			sqlite.column_int(stmt, 1),
			column_text_safe(stmt, 3),
		)
	}
	if !has_any do fmt.println("  No entries yet.")
	fmt.println()
}

// v18: quest display for get-story-state.

print_json_quests_for_state :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT q.id, q.name, q.description, q.quest_giver_npc_id, n.name, q.status, q.reward_description, q.chapter, q.created_at FROM quests q LEFT JOIN npcs n ON q.quest_giver_npc_id = n.id WHERE q.campaign_id=%d ORDER BY q.id",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		q_id := int(sqlite.column_int(stmt, 0))
		giver_id := int(sqlite.column_int(stmt, 3))
		giver_id_str := giver_id > 0 ? fmt.tprintf("%d", giver_id) : "null"
		giver_name := column_text_safe(stmt, 4)
		giver_name_str := len(giver_name) > 0 ? fmt.tprintf(`"%s"`, escape_json_string(giver_name)) : "null"

		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, `"id":%d,"name":"%s","description":"%s","quest_giver_npc_id":%s,"quest_giver_name":%s,"status":"%s","reward_description":"%s","chapter":"%s","created_at":"%s"`,
			q_id,
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			giver_id_str,
			giver_name_str,
			column_text_safe(stmt, 5),
			escape_json_string(column_text_safe(stmt, 6)),
			column_text_safe(stmt, 7),
			column_text_safe(stmt, 8),
		)
		strings.write_string(&builder, `,"objectives":`)
		print_json_quest_objectives(&builder, db, q_id)
		strings.write_string(&builder, `,"actors":`)
		print_json_quest_actors(&builder, db, q_id)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_quest_objectives :: proc(builder: ^strings.Builder, db: ^lib.Db, quest_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, description, status, sort_order FROM quest_objectives WHERE quest_id=%d ORDER BY sort_order, id", quest_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"description":"{}","status":"{}","sort_order":{}}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			column_text_safe(stmt, 2),
			sqlite.column_int(stmt, 3),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_quest_actors :: proc(builder: ^strings.Builder, db: ^lib.Db, quest_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT actor_type, actor_id, role FROM quest_actors WHERE quest_id=%d ORDER BY actor_type, actor_id", quest_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		actor_type := column_text_safe(stmt, 0)
		actor_id := int(sqlite.column_int(stmt, 1))
		actor_name := get_actor_name(db, actor_type, actor_id)
		fmt.sbprintf(builder, `{{"actor_type":"{}","actor_id":{},"actor_name":"{}","role":"{}"}}`,
			actor_type,
			actor_id,
			escape_json_string(actor_name),
			column_text_safe(stmt, 2),
		)
	}
	strings.write_byte(builder, ']')
}

print_text_quests :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT q.id, q.name, q.description, q.quest_giver_npc_id, n.name, q.status, q.reward_description, q.chapter FROM quests q LEFT JOIN npcs n ON q.quest_giver_npc_id = n.id WHERE q.campaign_id=%d ORDER BY q.id",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("QUESTS")
	fmt.println("--------------------------------------------------------------------------------")
	has_any := false
	for sqlite.step(stmt) == .Row {
		has_any = true
		q_id := int(sqlite.column_int(stmt, 0))
		fmt.printf("  [#%d] [%s] %s\n", q_id, column_text_safe(stmt, 5), column_text_safe(stmt, 1))
		fmt.printf("    %s\n", column_text_safe(stmt, 2))
		giver_id := int(sqlite.column_int(stmt, 3))
		if giver_id > 0 {
			fmt.printf("    Quest giver: %s (#%d)\n", column_text_safe(stmt, 4), giver_id)
		}
		ch := column_text_safe(stmt, 7)
		reward := column_text_safe(stmt, 6)
		if len(ch) > 0 || len(reward) > 0 {
			fmt.printf("    Chapter: %s | Reward: %s\n", ch, reward)
		}

		obj_stmt: ^sqlite.Statement
		obj_sql := fmt.tprintf("SELECT description, status FROM quest_objectives WHERE quest_id=%d ORDER BY sort_order, id", q_id)
		obj_c := cstring(raw_data(obj_sql))
		if sqlite.prepare(db.ptr, obj_c, i32(len(obj_sql)), &obj_stmt, nil) == .Ok {
			for sqlite.step(obj_stmt) == .Row {
				done := column_text_safe(obj_stmt, 1) == "complete" ? "x" : " "
				fmt.printf("    [%s] %s\n", done, column_text_safe(obj_stmt, 0))
			}
			sqlite.finalize(obj_stmt)
		}
		fmt.println()
	}
	if !has_any do fmt.println("  No quests.\n")
}

// v18: location tree for get-story-state. Each location node includes
// sub-locations, houses, shops, encounters, setpieces, and all entities present.

print_json_locations_tree :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter, is_current, COALESCE(parent_id,0), restricted, restricted_until FROM locations WHERE campaign_id=%d ORDER BY id", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_byte(&builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(&builder, ',')
		first = false
		loc_id := int(sqlite.column_int(stmt, 0))
		parent_id := int(sqlite.column_int(stmt, 5))
		parent_str := parent_id > 0 ? fmt.tprintf("%d", parent_id) : "null"
		is_curr := sqlite.column_int(stmt, 4) != 0 ? "true" : "false"

		strings.write_string(&builder, "{")
		fmt.sbprintf(&builder, `"id":%d,"name":"%s","description":"%s","chapter":"%s","is_current":%s,"parent_id":%s,"restricted":%d,"restricted_until":"%s"`,
			loc_id,
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			column_text_safe(stmt, 3),
			is_curr,
			parent_str,
			sqlite.column_int(stmt, 6),
			escape_json_string(column_text_safe(stmt, 7)),
		)
		strings.write_string(&builder, `,"sub_locations":`)
		print_json_sub_locations(&builder, db, loc_id)
		strings.write_string(&builder, `,"houses":`)
		print_json_houses(&builder, db, loc_id)
		strings.write_string(&builder, `,"shops":`)
		print_json_shops(&builder, db, loc_id)
		strings.write_string(&builder, `,"encounters":`)
		print_json_encounters(&builder, db, loc_id)
		strings.write_string(&builder, `,"setpieces":`)
		print_json_setpieces(&builder, db, loc_id)
		strings.write_string(&builder, `,"npcs_present":`)
		print_json_npcs_at(&builder, db, loc_id)
		strings.write_string(&builder, `,"characters_present":`)
		print_json_characters_at(&builder, db, loc_id)
		strings.write_string(&builder, `,"creatures_present":`)
		print_json_creatures_at(&builder, db, loc_id)
		strings.write_string(&builder, "}")
	}
	strings.write_byte(&builder, ']')
	fmt.print(strings.to_string(builder))
}

print_json_sub_locations :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name FROM locations WHERE parent_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_houses :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, npc_id, scale, restricted, restricted_until, inventory FROM houses WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","description":"{}","npc_id":{},"scale":"{}","restricted":{},"restricted_until":"{}","inventory":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			sqlite.column_int(stmt, 3),
			column_text_safe(stmt, 4),
			sqlite.column_int(stmt, 5),
			escape_json_string(column_text_safe(stmt, 6)),
			escape_json_string(column_text_safe(stmt, 7)),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_shops :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, npc_id, scale, open_hours, restricted, inventory FROM shops WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","description":"{}","npc_id":{},"scale":"{}","open_hours":"{}","restricted":{},"inventory":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			sqlite.column_int(stmt, 3),
			column_text_safe(stmt, 4),
			column_text_safe(stmt, 5),
			sqlite.column_int(stmt, 6),
			escape_json_string(column_text_safe(stmt, 7)),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_encounters :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, type, description, npc_id FROM encounters WHERE location_id=%d ORDER BY id", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"type":"{}","description":"{}","npc_id":{}}}`,
			sqlite.column_int(stmt, 0),
			column_text_safe(stmt, 1),
			escape_json_string(column_text_safe(stmt, 2)),
			sqlite.column_int(stmt, 3),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_setpieces :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter_event FROM setpieces WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","description":"{}","chapter_event":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			escape_json_string(column_text_safe(stmt, 3)),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_npcs_at :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, current_hp, max_hp, story_role, daily_role FROM npcs WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","description":"{}","current_hp":{},"max_hp":{},"story_role":"{}","daily_role":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			escape_json_string(column_text_safe(stmt, 2)),
			sqlite.column_int(stmt, 3),
			sqlite.column_int(stmt, 4),
			column_text_safe(stmt, 5),
			column_text_safe(stmt, 6),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_characters_at :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, current_hp, max_hp, owner, party FROM characters WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","current_hp":{},"max_hp":{},"owner":"{}","party":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			sqlite.column_int(stmt, 2),
			sqlite.column_int(stmt, 3),
			column_text_safe(stmt, 4),
			column_text_safe(stmt, 5),
		)
	}
	strings.write_byte(builder, ']')
}

print_json_creatures_at :: proc(builder: ^strings.Builder, db: ^lib.Db, location_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, current_hp, max_hp, story_role FROM creatures WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		strings.write_string(builder, "[]")
		return
	}
	defer sqlite.finalize(stmt)

	strings.write_byte(builder, '[')
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_byte(builder, ',')
		first = false
		fmt.sbprintf(builder, `{{"id":{},"name":"{}","current_hp":{},"max_hp":{},"story_role":"{}"}}`,
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			sqlite.column_int(stmt, 2),
			sqlite.column_int(stmt, 3),
			column_text_safe(stmt, 4),
		)
	}
	strings.write_byte(builder, ']')
}

print_text_npc_relationships :: proc(db: ^lib.Db, campaign_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT r.npc_id_1, n1.name, r.npc_id_2, n2.name, r.friendship_level, r.type, r.notes FROM npc_relationships r JOIN npcs n1 ON r.npc_id_1 = n1.id JOIN npcs n2 ON r.npc_id_2 = n2.id WHERE n1.campaign_id = %d ORDER BY r.friendship_level DESC",
		campaign_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("NPC RELATIONSHIPS")
	fmt.println("--------------------------------------------------------------------------------")
	has_any := false
	for sqlite.step(stmt) == .Row {
		has_any = true
		name1 := column_text_safe(stmt, 1)
		name2 := column_text_safe(stmt, 3)
		level := sqlite.column_int(stmt, 4)
		rel_type := column_text_safe(stmt, 5)
		notes := column_text_safe(stmt, 6)
		fmt.printf("  %s (#%d) --[%s, %+d]--> %s (#%d)\n", name1, sqlite.column_int(stmt, 0), rel_type, level, name2, sqlite.column_int(stmt, 2))
		if len(notes) > 0 {
			fmt.printf("    %s\n", notes)
		}
	}
	if !has_any do fmt.println("  No relationships defined.")
	fmt.println()
}

// Text-mode helpers for location tree display.

print_text_parties :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("PARTIES")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, notes, COALESCE(location_id,0), treasury_gold, treasury_silver, treasury_copper FROM parties WHERE campaign_id=%d ORDER BY name", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			pid := int(sqlite.column_int(stmt, 0))
			pname := column_text_safe(stmt, 1)
			pnotes := column_text_safe(stmt, 2)
			pgold := int(sqlite.column_int(stmt, 4))
			psilver := int(sqlite.column_int(stmt, 5))
			pcopper := int(sqlite.column_int(stmt, 6))
			fmt.printf("  %s (ID: %d)\n", pname, pid)
			if len(pnotes) > 0 do fmt.printf("    Notes: %s\n", pnotes)
			fmt.printf("    Treasury: %d gp, %d sp, %d cp\n", pgold, psilver, pcopper)
			mem_stmt: ^sqlite.Statement
			mem_sql := fmt.tprintf("SELECT name, current_hp, max_hp, ac FROM characters WHERE party_id=%d ORDER BY name", pid)
			mem_c := cstring(raw_data(mem_sql))
			if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) == .Ok {
				for sqlite.step(mem_stmt) == .Row {
					fmt.printf("    - %s  HP:%d/%d AC:%d\n", column_text_safe(mem_stmt, 0), int(sqlite.column_int(mem_stmt, 1)), int(sqlite.column_int(mem_stmt, 2)), int(sqlite.column_int(mem_stmt, 3)))
				}
				sqlite.finalize(mem_stmt)
			}
		}
		if !has_any do fmt.println("  No parties defined.")
	}
	fmt.println()
}

print_text_sub_locations :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name FROM locations WHERE parent_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		fmt.printf("%sSub-location: [%d] %s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1))
	}
}

print_text_houses :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, scale, restricted FROM houses WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		restr := sqlite.column_int(stmt, 3) != 0 ? " (restricted)" : ""
		fmt.printf("%sHouse: [%d] %s (scale: %s)%s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2), restr)
	}
}

print_text_shops :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, scale, open_hours FROM shops WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		fmt.printf("%sShop: [%d] %s (scale: %s, hours: %s)\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2), column_text_safe(stmt, 3))
	}
}

print_text_encounters :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, type, description FROM encounters WHERE location_id=%d ORDER BY id", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		fmt.printf("%sEncounter: [%d] (%s) %s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), column_text_safe(stmt, 2))
	}
}

print_text_setpieces :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter_event FROM setpieces WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		event := column_text_safe(stmt, 3)
		event_str := len(event) > 0 ? fmt.tprintf(" [Event: %s]", event) : ""
		fmt.printf("%sSetpiece: [%d] %s%s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), event_str)
	}
}

print_text_npcs_at :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, story_role FROM npcs WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		role := column_text_safe(stmt, 2)
		role_str := len(role) > 0 ? fmt.tprintf(" (%s)", role) : ""
		fmt.printf("%sNPC: [%d] %s%s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), role_str)
	}
}

print_text_characters_at :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, party FROM characters WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		party := column_text_safe(stmt, 2)
		party_str := len(party) > 0 ? fmt.tprintf(" (party: %s)", party) : ""
		fmt.printf("%sCharacter: [%d] %s%s\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), party_str)
	}
}

print_text_creatures_at :: proc(db: ^lib.Db, location_id: int, indent: string) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, current_hp, max_hp FROM creatures WHERE location_id=%d ORDER BY name", location_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok { return }
	defer sqlite.finalize(stmt)

	for sqlite.step(stmt) == .Row {
		fmt.printf("%sCreature: [%d] %s (%d/%d hp)\n", indent, sqlite.column_int(stmt, 0), column_text_safe(stmt, 1), sqlite.column_int(stmt, 2), sqlite.column_int(stmt, 3))
	}
}
