package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

item_upsert :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine item upsert <name> <description> <type> [damage_dice] [damage_type] [ac_bonus] [properties] [weight] [value_gp]")
		} else {
			fmt.eprintln("Usage: ttrpg-engine item upsert <name> <description> <type> [damage_dice] [damage_type] [ac_bonus] [properties] [weight] [value_gp]")
		}
		return 1
	}
	name := args[1]
	description := args[2]
	item_type := args[3]

	damage_dice := ""
	damage_type := ""
	ac_bonus := 0
	properties := ""
	weight := 0.0
	value_gp := 0.0

	if len(args) >= 5 do damage_dice = args[4]
	if len(args) >= 6 do damage_type = args[5]
	if len(args) >= 7 do ac_bonus = strconv.atoi(args[6])
	if len(args) >= 8 do properties = args[7]
	if len(args) >= 9 do weight = strconv.parse_f64(args[8]) or_else 0.0
	if len(args) >= 10 do value_gp = strconv.parse_f64(args[9]) or_else 0.0

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO items (name,description,item_type,damage_dice,damage_type,ac_bonus,properties,weight,value_gp) VALUES('%s','%s','%s','%s','%s',%d,'%s',%f,%f)",
		escape_sql(name), escape_sql(description), escape_sql(item_type), escape_sql(damage_dice), escape_sql(damage_type), ac_bonus, escape_sql(properties), weight, value_gp,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to upsert item")
		} else {
			fmt.eprintln("Failed to upsert item")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Upserted item: %s"}}\n`, name)
	} else {
		fmt.println("Upserted item:", name)
	}
	return 0
}

item_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id, name, item_type, value_gp FROM items ORDER BY name"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			usage_error(db, "Failed to list items")
		} else {
			fmt.eprintln("Failed to list items")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","type":"{}","value_gp":{}}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_double(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s (%s) - %.2fgp\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_double(stmt, 3),
			)
		}
	}
	return 0
}

get_inventory_column_name :: proc(target_type: string) -> (col: string, ok: bool) {
	if target_type == "char" do return "character_id", true
	if target_type == "npc" do return "npc_id", true
	if target_type == "creature" do return "creature_id", true
	return "", false
}

inventory_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine inventory add <char|npc|creature> <id> <item_id> <qty>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine inventory add <char|npc|creature> <id> <item_id> <qty>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	qty := strconv.atoi(args[4])

	col, ok := get_inventory_column_name(target_type)
	if !ok {
		if db.is_json {
			usage_error(db, "Target type must be 'char', 'npc', or 'creature'")
		} else {
			fmt.eprintln("Target type must be 'char', 'npc', or 'creature'")
		}
		return 1
	}

	sql := fmt.tprintf("INSERT INTO inventory (%s,item_id,quantity) VALUES(%d,%d,%d)", col, id, item_id, qty)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to add item to inventory")
		} else {
			fmt.eprintln("Failed to add item")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added item %d to %s %d","id":%d,"item_id":%d,"qty":%d}}\n`, item_id, target_type, id, id, item_id, qty)
	} else {
		fmt.printf("Added item %d to %s %d\n", item_id, target_type, id)
	}
	return 0
}

get_inventory_sql :: proc(target_type: string, id: int) -> (sql: string, ok: bool) {
	col, col_ok := get_inventory_column_name(target_type)
	if !col_ok do return "", false
	sql = fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.%s=%d", col, id)
	return sql, true
}

print_inventory :: proc(stmt: ^sqlite.Statement, is_json: bool) {
	if is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			fmt.sbprintf(&builder, `{{"name":"{}","quantity":{},"equipped":{},"attuned":{},"item_id":{}}}`,
				sqlite.column_text(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_int(stmt, 4),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			name := sqlite.column_text(stmt, 0)
			qty := sqlite.column_int(stmt, 1)
			eq := sqlite.column_int(stmt, 2)
			at := sqlite.column_int(stmt, 3)

			status := ""
			if eq == 1 && at == 1 {
				status = " [E] [A]"
			} else if eq == 1 {
				status = " [E]"
			} else if at == 1 {
				status = " [A]"
			}
			fmt.printf("  %s x%d%s\n", name, qty, status)
		}
	}
}

inventory_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine inventory get <char|npc|creature> <id>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine inventory get <char|npc|creature> <id>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])

	sql, ok := get_inventory_sql(target_type, id)
	if !ok {
		if db.is_json {
			usage_error(db, "Target type must be 'char', 'npc', or 'creature'")
		} else {
			fmt.eprintln("Target type must be 'char', 'npc', or 'creature'")
		}
		return 1
	}

	stmt: ^sqlite.Statement
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			usage_error(db, "Failed to get inventory")
		} else {
			fmt.eprintln("Failed to get inventory")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	print_inventory(stmt, db.is_json)
	return 0
}

inventory_remove :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine inventory remove <char|npc|creature> <id> <item_id> <qty>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine inventory remove <char|npc|creature> <id> <item_id> <qty>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	qty := strconv.atoi(args[4])

	col, ok := get_inventory_column_name(target_type)
	if !ok {
		if db.is_json {
			usage_error(db, "Target type must be 'char', 'npc', or 'creature'")
		} else {
			fmt.eprintln("Target type must be 'char', 'npc', or 'creature'")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE inventory SET quantity=quantity-%d WHERE %s=%d AND item_id=%d", qty, col, id, item_id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to remove item")
		} else {
			fmt.eprintln("Failed to remove item")
		}
		return 1
	}

	// Clean up rows where quantity is 0 or less
	lib.db_exec(db, "DELETE FROM inventory WHERE quantity <= 0")

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Removed item %d from %s %d","id":%d,"item_id":%d,"qty":%d}}\n`, item_id, target_type, id, id, item_id, qty)
	} else {
		fmt.printf("Removed item %d from %s %d\n", item_id, target_type, id)
	}
	return 0
}

inventory_equip :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine inventory equip <char|npc|creature> <id> <item_id> <0/1>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine inventory equip <char|npc|creature> <id> <item_id> <0/1>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	val := strconv.atoi(args[4])

	col, ok := get_inventory_column_name(target_type)
	if !ok {
		if db.is_json {
			usage_error(db, "Target type must be 'char', 'npc', or 'creature'")
		} else {
			fmt.eprintln("Target type must be 'char', 'npc', or 'creature'")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE inventory SET equipped=%d WHERE %s=%d AND item_id=%d", val, col, id, item_id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to equip item")
		} else {
			fmt.eprintln("Failed to equip item")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Set item %d equipped to %d for %s %d","id":%d,"item_id":%d,"equipped":%d}}\n`, item_id, val, target_type, id, id, item_id, val)
	} else {
		fmt.printf("Set item %d equipped to %d for %s %d\n", item_id, val, target_type, id)
	}
	return 0
}

inventory_attune :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			usage_error(db, "Usage: ttrpg-engine inventory attune <char|npc|creature> <id> <item_id> <0/1>")
		} else {
			fmt.eprintln("Usage: ttrpg-engine inventory attune <char|npc|creature> <id> <item_id> <0/1>")
		}
		return 1
	}
	target_type := args[1]
	id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	val := strconv.atoi(args[4])

	col, ok := get_inventory_column_name(target_type)
	if !ok {
		if db.is_json {
			usage_error(db, "Target type must be 'char', 'npc', or 'creature'")
		} else {
			fmt.eprintln("Target type must be 'char', 'npc', or 'creature'")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE inventory SET attuned=%d WHERE %s=%d AND item_id=%d", val, col, id, item_id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			usage_error(db, "Failed to attune item")
		} else {
			fmt.eprintln("Failed to attune item")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Set item %d attuned to %d for %s %d","id":%d,"item_id":%d,"attuned":%d}}\n`, item_id, val, target_type, id, id, item_id, val)
	} else {
		fmt.printf("Set item %d attuned to %d for %s %d\n", item_id, val, target_type, id)
	}
	return 0
}
