package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

spell_upsert :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 9 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine spell upsert <name> <level> <school> <casting_time> <range> <components> <duration> <description>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine spell upsert <name> <level> <school> <casting_time> <range> <components> <duration> <description>")
		}
		return 1
	}
	name := args[1]
	level := strconv.atoi(args[2])
	school := args[3]
	casting_time := args[4]
	range_val := args[5]
	components := args[6]
	duration := args[7]
	description := args[8]

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO spells (name,level,school,casting_time,range,components,duration,description) VALUES('%s',%d,'%s','%s','%s','%s','%s','%s')",
		escape_sql(name), level, escape_sql(school), escape_sql(casting_time), escape_sql(range_val), escape_sql(components), escape_sql(duration), escape_sql(description),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to upsert spell")
		} else {
			fmt.eprintln("Failed to upsert spell")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Spell upserted: %s"}}\n`, name)
	} else {
		fmt.println("Spell upserted:", name)
	}
	return 0
}

spell_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,level,school FROM spells ORDER BY level, name"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			usage_error(db, "Failed to list spells")
		} else {
			fmt.eprintln("Failed to list spells")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","level":{},"school":"{}"}}`,
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
			fmt.printf("[%d] %s (Level %d %s)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
	}
	return 0
}

spell_learn :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine spell learn <char_id> <spell_id> [prepared (0/1)] [class_name] [source]")
		} else {
			fmt.eprintln("Usage: ttrpg-engine spell learn <char_id> <spell_id> [prepared (0/1)] [class_name] [source]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	spell_id := strconv.atoi(args[2])
	prepared := 0
	if len(args) >= 4 {
		prepared = strconv.atoi(args[3])
	}
	class_name := ""
	if len(args) >= 5 {
		class_name = args[4]
	}
	source := ""
	if len(args) >= 6 {
		source = args[5]
	}

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_spells (character_id,spell_id,prepared,class_name,source) VALUES(%d,%d,%d,'%s','%s')",
		char_id, spell_id, prepared, escape_sql(class_name), escape_sql(source),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to learn spell")
		} else {
			fmt.eprintln("Failed to learn spell")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"character_id":%d,"spell_id":%d,"prepared":%d,"class_name":"%s","source":"%s"}}\n`, char_id, spell_id, prepared, escape_json_string(class_name), escape_json_string(source))
	} else {
		fmt.println("Character", char_id, "learned spell", spell_id)
	}
	return 0
}

spell_prepare :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine spell prepare <char_id> <spell_id> <0/1>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine spell prepare <char_id> <spell_id> <0/1>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	spell_id := strconv.atoi(args[2])
	prepared := strconv.atoi(args[3])

	sql := fmt.tprintf(
		"UPDATE character_spells SET prepared=%d WHERE character_id=%d AND spell_id=%d",
		prepared, char_id, spell_id,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to prepare/unprepare spell")
		} else {
			fmt.eprintln("Failed to prepare/unprepare spell")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"character_id":%d,"spell_id":%d,"prepared":%d}}\n`, char_id, spell_id, prepared)
	} else {
		fmt.printf("Set spell %d preparation for character %d to %d\n", spell_id, char_id, prepared)
	}
	return 0
}

spell_list_character :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine spell list-character <char_id>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine spell list-character <char_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT s.id, s.name, s.level, cs.prepared, cs.class_name FROM character_spells cs JOIN spells s ON cs.spell_id = s.id WHERE cs.character_id = %d ORDER BY cs.class_name, s.level, s.name",
		char_id,
	)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			usage_error(db, "Failed to get character spells")
		} else {
			fmt.eprintln("Failed to get character spells")
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
			class_name := column_text_safe(stmt, 4)
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","level":{},"prepared":{},"class_name":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_int(stmt, 3),
				class_name,
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		fmt.printf("Spells for character %d:\n", char_id)
		for sqlite.step(stmt) == .Row {
			prep_str := sqlite.column_int(stmt, 3) == 1 ? "[Prepared]" : "[Unprepared]"
			cls := column_text_safe(stmt, 4)
			cls_part := len(cls) > 0 ? fmt.tprintf(" (%s)", cls) : ""
			fmt.printf("  [%d] %s (Level %d)%s %s\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				cls_part,
				prep_str,
			)
		}
	}
	return 0
}


spell_forget :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine spell forget <char_id> <spell_id>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine spell forget <char_id> <spell_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	spell_id := strconv.atoi(args[2])

	sql := fmt.tprintf("DELETE FROM character_spells WHERE character_id=%d AND spell_id=%d", char_id, spell_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to forget spell")
		} else {
			fmt.eprintln("Failed to forget spell")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{"success":true,"message":"Spell forgotten","character_id":%d,"spell_id":%d}` + "\n", char_id, spell_id)
	} else {
		fmt.printf("Character %d forgot spell %d\n", char_id, spell_id)
	}
	return 0
}
