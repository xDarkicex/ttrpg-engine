package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

specialty_upsert :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine class-specialty upsert <class_name> <level> <ability_name> <description>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine class-specialty upsert <class_name> <level> <ability_name> <description>")
		}
		return 1
	}
	class_name := args[1]
	level := strconv.atoi(args[2])
	ability_name := args[3]
	description := args[4]

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO class_specialties (class_name,level,ability_name,description) VALUES('%s',%d,'%s','%s')",
		escape_sql(class_name), level, escape_sql(ability_name), escape_sql(description),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to upsert class specialty")
		} else {
			fmt.eprintln("Failed to upsert class specialty")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Upserted specialty: %s for %s Lvl%d"}}\n`, ability_name, class_name, level)
	} else {
		fmt.printf("Upserted specialty: %s for %s Lvl%d\n", ability_name, class_name, level)
	}
	return 0
}

specialty_list :: proc(db: ^lib.Db, args: []string) -> int {
	class_filter := ""
	if len(args) >= 2 {
		class_filter = args[1]
	}

	stmt: ^sqlite.Statement
	sql := ""
	if len(class_filter) > 0 {
		sql = fmt.tprintf("SELECT class_name, level, ability_name, description FROM class_specialties WHERE class_name='%s' ORDER BY level, ability_name", escape_sql(class_filter))
	} else {
		sql = "SELECT class_name, level, ability_name, description FROM class_specialties ORDER BY class_name, level, ability_name"
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			usage_error(db, "Failed to list specialties")
		} else {
			fmt.eprintln("Failed to list specialties")
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
			fmt.sbprintf(&builder, `{{"class_name":"{}","level":{},"ability_name":"{}","description":"{}"}}`,
				sqlite.column_text(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%s Lvl%d] %s: %s\n",
				sqlite.column_text(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
	}
	return 0
}
