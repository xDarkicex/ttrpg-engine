package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

feature_upsert :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent feature upsert <name> <source> <description>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent feature upsert <name> <source> <description>")
		}
		return 1
	}
	name := args[1]
	source := args[2]
	description := args[3]

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO features (name,source,description) VALUES('%s','%s','%s')",
		escape_sql(name), escape_sql(source), escape_sql(description),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to upsert feature"}`)
		} else {
			fmt.eprintln("Failed to upsert feature")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Feature upserted: %s"}}\n`, name)
	} else {
		fmt.println("Feature upserted:", name)
	}
	return 0
}

feature_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,source FROM features ORDER BY source, name"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list features"}`)
		} else {
			fmt.eprintln("Failed to list features")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","source":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s (%s)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
	}
	return 0
}

feature_add_to_char :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent feature add-to-char <char_id> <feature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent feature add-to-char <char_id> <feature_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	feature_id := strconv.atoi(args[2])

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_features (character_id,feature_id) VALUES(%d,%d)",
		char_id, feature_id,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add feature to character"}`)
		} else {
			fmt.eprintln("Failed to add feature to character")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Character %d gained feature %d","character_id":%d,"feature_id":%d}}\n`, char_id, feature_id, char_id, feature_id)
	} else {
		fmt.println("Character", char_id, "gained feature", feature_id)
	}
	return 0
}

feature_list_character :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent feature list-character <char_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent feature list-character <char_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM character_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.character_id = %d ORDER BY f.source, f.name",
		char_id,
	)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to get character features"}`)
		} else {
			fmt.eprintln("Failed to get character features")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","source":"{}","description":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		fmt.printf("Features for character %d:\n", char_id)
		for sqlite.step(stmt) == .Row {
			fmt.printf("  [%d] %s (Source: %s) - %s\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
	}
	return 0
}
