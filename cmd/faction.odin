package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

faction_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent faction create <name> <description>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent faction create <name> <description>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent faction join <char|npc> <id> <faction_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent faction join <char|npc> <id> <faction_id>")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent faction set-standing <character_id> <faction_id> <standing> [notes]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent faction set-standing <character_id> <faction_id> <standing> [notes]")
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
			fmt.println(`{"success":false,"error":"Usage: dnd-agent faction get-standing <character_id> [faction_id]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent faction get-standing <character_id> [faction_id]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	faction_id := 0
	if len(args) >= 3 do faction_id = strconv.atoi(args[2])

	stmt: ^sqlite.Statement
	sql := ""
	if faction_id > 0 {
		sql = fmt.tprintf("SELECT fs.faction_id, f.name, fs.standing, fs.notes FROM faction_standings fs JOIN factions f ON fs.faction_id=f.id WHERE fs.character_id=%d AND fs.faction_id=%d", char_id, faction_id)
	} else {
		sql = fmt.tprintf("SELECT fs.faction_id, f.name, fs.standing, fs.notes FROM faction_standings fs JOIN factions f ON fs.faction_id=f.id WHERE fs.character_id=%d", char_id)
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

	if !db.is_json {
		fmt.printf("Faction standings for character %d:\n", char_id)
	}
	print_faction_standings(stmt, db.is_json)
	return 0
}
