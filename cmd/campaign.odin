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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign create <name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign create <name>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign get <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign get <id>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign delete <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign delete <id>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign set-chapter <id> <chapter>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign set-chapter <id> <chapter>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign next-session <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign next-session <id>")
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
		return print_error(db, "Usage: dnd-agent campaign add-location <campaign_id> <name> <description> [chapter]")
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
		return print_error(db, "Usage: dnd-agent campaign set-location <campaign_id> <location_id>")
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
		return print_error(db, "Usage: dnd-agent campaign list-locations <campaign_id>")
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
		return print_error(db, "Usage: dnd-agent campaign add-action <campaign_id> <description> [location_id] [faction_id] [standing_impact] [story_progression] [status]")
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
		return print_error(db, "Usage: dnd-agent campaign link-actor <action_id> <char|npc> <actor_id>")
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
		return print_error(db, "Usage: dnd-agent campaign list-actions <campaign_id> [location_id]")
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
	sql := fmt.tprintf("SELECT id, name, chapter, session_num FROM campaigns WHERE id=%d", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("null")
		return
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) == .Row {
		fmt.print("{")
		fmt.printf("\"id\":%d,\"name\":\"%s\",\"chapter\":\"%s\",\"session_num\":%d",
			sqlite.column_int(stmt, 0),
			escape_json_string(column_text_safe(stmt, 1)),
			column_text_safe(stmt, 2),
			sqlite.column_int(stmt, 3),
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
	sql := fmt.tprintf("SELECT c.name, c.chapter, c.session_num, (SELECT name FROM locations WHERE campaign_id=c.id AND is_current=1 LIMIT 1) FROM campaigns c WHERE c.id=%d", campaign_id)
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
	curr_loc := sqlite.column_text(stmt, 3)
	curr_loc_str := curr_loc != nil ? string(curr_loc) : "None"

	fmt.println("================================================================================")
	fmt.printf("CAMPAIGN REPORT: %s (ID: %d)\n", camp_name, campaign_id)
	fmt.println("================================================================================")
	fmt.printf("Chapter: %s | Session: %d\n", chapter, session_num)
	fmt.printf("Current Active Location: %s\n\n", curr_loc_str)

	print_text_story_state_locations(db, campaign_id)
	print_text_story_state_standings(db, campaign_id)
	print_text_story_state_actions(db, campaign_id)
}

print_text_story_state_locations :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("LOCATIONS LIST")
	fmt.println("--------------------------------------------------------------------------------")
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, description, chapter, is_current FROM locations WHERE campaign_id=%d ORDER BY id", campaign_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		print_text_locations_stmt(stmt)
	}
	fmt.println()
}

print_text_story_state_standings :: proc(db: ^lib.Db, campaign_id: int) {
	fmt.println("--------------------------------------------------------------------------------")
	fmt.println("FACTION STANDINGS")
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
		return print_error(db, "Usage: dnd-agent campaign get-story-state <campaign_id>")
	}

	campaign_id := strconv.atoi(args[1])

	if db.is_json {
		fmt.print(`{"success":true`)
		fmt.print(`,"campaign":`)
		print_json_campaign_details(db, campaign_id)
		fmt.print(`,"locations":`)
		print_json_locations_by_id(db, campaign_id)
		fmt.print(`,"faction_standings":`)
		print_json_standings_by_id(db, campaign_id)
		fmt.print(`,"story_actions":`)
		print_json_actions_by_id(db, campaign_id)
		fmt.println(`}`)
	} else {
		print_text_story_state(db, campaign_id)
	}
	return 0
}