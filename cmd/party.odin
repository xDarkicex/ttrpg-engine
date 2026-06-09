package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

// ---------------------------------------------------------------------------
// party create <campaign_id> <name> [notes]
// ---------------------------------------------------------------------------
party_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine party create <campaign_id> <name> [notes]")
	}
	campaign_id := strconv.atoi(args[1])
	name := args[2]
	notes := ""
	if len(args) >= 4 do notes = args[3]

	sql := fmt.tprintf("INSERT INTO parties (campaign_id, name, notes) VALUES(%d, '%s', '%s')", campaign_id, escape_sql(name), escape_sql(notes))
	if lib.db_exec(db, sql) != lib.Error.None {
		return print_error(db, "Failed to create party. Name may already exist in this campaign.")
	}

	// Get the new ID
	stmt: ^sqlite.Statement
	id_sql := fmt.tprintf("SELECT id FROM parties WHERE campaign_id=%d AND name='%s'", campaign_id, escape_sql(name))
	id_c := cstring(raw_data(id_sql))
	party_id := 0
	if sqlite.prepare(db.ptr, id_c, i32(len(id_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row do party_id = int(sqlite.column_int(stmt, 0))
		sqlite.finalize(stmt)
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"party_id":%d,"name":"%s","campaign_id":%d}}` + "\n", party_id, escape_json_string(name), campaign_id)
	} else {
		fmt.printf("Party '%s' created (ID: %d) in campaign %d.\n", name, party_id, campaign_id)
	}
	return 0
}

// ---------------------------------------------------------------------------
// party add <party_id> <character_id>
// ---------------------------------------------------------------------------
party_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine party add <party_id> <character_id>")
	}
	party_id := strconv.atoi(args[1])
	char_id := strconv.atoi(args[2])

	// Get party name for syncing the text field
	party_name := ""
	stmt: ^sqlite.Statement
	name_sql := fmt.tprintf("SELECT name FROM parties WHERE id=%d", party_id)
	name_c := cstring(raw_data(name_sql))
	if sqlite.prepare(db.ptr, name_c, i32(len(name_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row do party_name = column_text_safe(stmt, 0)
		sqlite.finalize(stmt)
	}
	if len(party_name) == 0 do return print_error(db, "Party not found")

	// Update character's party_id and also the text party field for backward compat
	sql := fmt.tprintf("UPDATE characters SET party_id=%d, party='%s' WHERE id=%d", party_id, escape_sql(party_name), char_id)
	if lib.db_exec(db, sql) != lib.Error.None do return print_error(db, "Failed to add character to party")

	// Get character name for output
	char_name := ""
	char_sql := fmt.tprintf("SELECT name FROM characters WHERE id=%d", char_id)
	char_c := cstring(raw_data(char_sql))
	if sqlite.prepare(db.ptr, char_c, i32(len(char_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row do char_name = column_text_safe(stmt, 0)
		sqlite.finalize(stmt)
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"party_id":%d,"party_name":"%s","character_id":%d,"character_name":"%s"}}` + "\n", party_id, escape_json_string(party_name), char_id, escape_json_string(char_name))
	} else {
		fmt.printf("Added %s to party '%s'.\n", char_name, party_name)
	}
	return 0
}

// ---------------------------------------------------------------------------
// party remove <character_id>
// ---------------------------------------------------------------------------
party_remove :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine party remove <character_id>")
	}
	char_id := strconv.atoi(args[1])

	char_name := ""
	stmt: ^sqlite.Statement
	char_sql := fmt.tprintf("SELECT name, party FROM characters WHERE id=%d", char_id)
	char_c := cstring(raw_data(char_sql))
	party_name := ""
	if sqlite.prepare(db.ptr, char_c, i32(len(char_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row {
			char_name = column_text_safe(stmt, 0)
			party_name = column_text_safe(stmt, 1)
		}
		sqlite.finalize(stmt)
	}

	sql := fmt.tprintf("UPDATE characters SET party_id=NULL, party='' WHERE id=%d", char_id)
	lib.db_exec(db, sql)

	if db.is_json {
		fmt.printf(`{{"success":true,"character_id":%d,"character_name":"%s","removed_from":"%s"}}` + "\n", char_id, escape_json_string(char_name), escape_json_string(party_name))
	} else {
		fmt.printf("Removed %s from party '%s'.\n", char_name, party_name)
	}
	return 0
}

// ---------------------------------------------------------------------------
// party list <campaign_id>
// ---------------------------------------------------------------------------
party_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: ttrpg-engine party list <campaign_id>")
	}
	campaign_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	parties_sql := fmt.tprintf("SELECT id, name, notes, COALESCE(location_id,0), treasury_gold, treasury_silver, treasury_copper FROM parties WHERE campaign_id=%d ORDER BY name", campaign_id)
	parties_c := cstring(raw_data(parties_sql))
	if sqlite.prepare(db.ptr, parties_c, i32(len(parties_sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to list parties")
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		fmt.print("[")
		first_party := true
		for sqlite.step(stmt) == .Row {
			if !first_party do fmt.print(",")
			first_party = false
			pid := int(sqlite.column_int(stmt, 0))
			pname := column_text_safe(stmt, 1)
			pnotes := column_text_safe(stmt, 2)
			ploc := int(sqlite.column_int(stmt, 3))
			pgold := int(sqlite.column_int(stmt, 4))
			psilver := int(sqlite.column_int(stmt, 5))
			pcopper := int(sqlite.column_int(stmt, 6))

			fmt.printf(`{"id":%d,"name":"%s","notes":"%s","location_id":%d,"treasury":{"gold":%d,"silver":%d,"copper":%d},"members":[`, pid, escape_json_string(pname), escape_json_string(pnotes), ploc, pgold, psilver, pcopper)

			// Members
			mem_stmt: ^sqlite.Statement
			mem_sql := fmt.tprintf("SELECT id, name, current_hp, max_hp, ac FROM characters WHERE party_id=%d ORDER BY name", pid)
			mem_c := cstring(raw_data(mem_sql))
			if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) == .Ok {
				first_mem := true
				for sqlite.step(mem_stmt) == .Row {
					if !first_mem do fmt.print(",")
					first_mem = false
					fmt.printf(`{"id":%d,"name":"%s","hp":%d,"max_hp":%d,"ac":%d}`,
						int(sqlite.column_int(mem_stmt, 0)), escape_json_string(column_text_safe(mem_stmt, 1)),
						int(sqlite.column_int(mem_stmt, 2)), int(sqlite.column_int(mem_stmt, 3)), int(sqlite.column_int(mem_stmt, 4)))
				}
				sqlite.finalize(mem_stmt)
			}
			fmt.print("]}")
		}
		fmt.print("]\n")
	} else {
		for sqlite.step(stmt) == .Row {
			pid := int(sqlite.column_int(stmt, 0))
			pname := column_text_safe(stmt, 1)
			pnotes := column_text_safe(stmt, 2)
			pgold := int(sqlite.column_int(stmt, 4))
			psilver := int(sqlite.column_int(stmt, 5))
			pcopper := int(sqlite.column_int(stmt, 6))

			fmt.printf("Party: %s (ID: %d)\n", pname, pid)
			if len(pnotes) > 0 do fmt.printf("  Notes: %s\n", pnotes)
			fmt.printf("  Treasury: %d gp, %d sp, %d cp\n", pgold, psilver, pcopper)

			mem_stmt: ^sqlite.Statement
			mem_sql := fmt.tprintf("SELECT name, current_hp, max_hp, ac FROM characters WHERE party_id=%d ORDER BY name", pid)
			mem_c := cstring(raw_data(mem_sql))
			if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) == .Ok {
				has_any := false
				for sqlite.step(mem_stmt) == .Row {
					has_any = true
					fmt.printf("  - %s  HP:%d/%d AC:%d\n", column_text_safe(mem_stmt, 0), int(sqlite.column_int(mem_stmt, 1)), int(sqlite.column_int(mem_stmt, 2)), int(sqlite.column_int(mem_stmt, 3)))
				}
				if !has_any do fmt.println("  (no members)")
				sqlite.finalize(mem_stmt)
			}
			fmt.println()
		}
	}
	return 0
}

// ---------------------------------------------------------------------------
// party rest <party_id> <short|long> [hit_dice_count_for_short]
// ---------------------------------------------------------------------------
party_rest :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine party rest <party_id> <short|long> [hit_dice_count]")
	}
	party_id := strconv.atoi(args[1])
	rest_type := args[2]
	hd_count := 1
	if rest_type == "short" && len(args) >= 4 do hd_count = strconv.atoi(args[3])

	if rest_type != "short" && rest_type != "long" {
		return print_error(db, "Rest type must be 'short' or 'long'")
	}

	// Get party name and all member IDs
	mem_stmt: ^sqlite.Statement
	mem_sql := fmt.tprintf("SELECT id, name FROM characters WHERE party_id=%d", party_id)
	mem_c := cstring(raw_data(mem_sql))
	if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) != .Ok {
		return print_error(db, "Party not found or has no members")
	}
	defer sqlite.finalize(mem_stmt)

	member_ids: [dynamic]int
	member_names: [dynamic]string
	for sqlite.step(mem_stmt) == .Row {
		append(&member_ids, int(sqlite.column_int(mem_stmt, 0)))
		append(&member_names, column_text_safe(mem_stmt, 1))
	}

	if len(member_ids) == 0 do return print_error(db, "Party has no members")

	for i := 0; i < len(member_ids); i += 1 {
		if rest_type == "short" {
			rest_short(db, []string{"short", fmt.tprintf("%d", member_ids[i]), fmt.tprintf("%d", hd_count)})
		} else {
			rest_long(db, []string{"long", fmt.tprintf("%d", member_ids[i])})
		}
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"party_id":%d,"rest_type":"%s","members_rested":%d}}` + "\n", party_id, rest_type, len(member_ids))
	} else {
		fmt.printf("Party %s rest: %d members completed %s rest.\n", rest_type, len(member_ids), rest_type)
	}
	return 0
}

// ---------------------------------------------------------------------------
// party move <party_id> <location_id>
// ---------------------------------------------------------------------------
party_move :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: ttrpg-engine party move <party_id> <location_id>")
	}
	party_id := strconv.atoi(args[1])
	location_id := strconv.atoi(args[2])

	// Update party's location
	lib.db_exec(db, fmt.tprintf("UPDATE parties SET location_id=%d WHERE id=%d", location_id, party_id))

	// Move all members
	mem_stmt: ^sqlite.Statement
	mem_sql := fmt.tprintf("SELECT id, name FROM characters WHERE party_id=%d", party_id)
	mem_c := cstring(raw_data(mem_sql))
	if sqlite.prepare(db.ptr, mem_c, i32(len(mem_sql)), &mem_stmt, nil) != .Ok {
		return print_error(db, "Party not found")
	}
	defer sqlite.finalize(mem_stmt)

	count := 0
	for sqlite.step(mem_stmt) == .Row {
		id := int(sqlite.column_int(mem_stmt, 0))
		lib.db_exec(db, fmt.tprintf("UPDATE characters SET location_id=%d WHERE id=%d", location_id, id))
		count += 1
	}

	if count == 0 do return print_error(db, "Party has no members")

	// Get location name
	loc_name := ""
	loc_stmt: ^sqlite.Statement
	loc_sql := fmt.tprintf("SELECT name FROM locations WHERE id=%d", location_id)
	loc_c := cstring(raw_data(loc_sql))
	if sqlite.prepare(db.ptr, loc_c, i32(len(loc_sql)), &loc_stmt, nil) == .Ok {
		if sqlite.step(loc_stmt) == .Row do loc_name = column_text_safe(loc_stmt, 0)
		sqlite.finalize(loc_stmt)
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"party_id":%d,"location_id":%d,"location_name":"%s","members_moved":%d}}` + "\n", party_id, location_id, escape_json_string(loc_name), count)
	} else {
		fmt.printf("Party moved to %s (location %d). %d members relocated.\n", loc_name, location_id, count)
	}
	return 0
}

// ---------------------------------------------------------------------------
// party treasury <party_id> <add|remove|set> <gold> <silver> <copper>
// ---------------------------------------------------------------------------
party_treasury :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 6 {
		return print_error(db, "Usage: ttrpg-engine party treasury <party_id> <add|remove|set> <gold> <silver> <copper>")
	}
	party_id := strconv.atoi(args[1])
	op := args[2]
	gold := strconv.atoi(args[3])
	silver := strconv.atoi(args[4])
	copper := strconv.atoi(args[5])

	if op == "set" {
		lib.db_exec(db, fmt.tprintf("UPDATE parties SET treasury_gold=%d, treasury_silver=%d, treasury_copper=%d WHERE id=%d", gold, silver, copper, party_id))
	} else if op == "add" {
		lib.db_exec(db, fmt.tprintf("UPDATE parties SET treasury_gold=treasury_gold+%d, treasury_silver=treasury_silver+%d, treasury_copper=treasury_copper+%d WHERE id=%d", gold, silver, copper, party_id))
	} else if op == "remove" {
		lib.db_exec(db, fmt.tprintf("UPDATE parties SET treasury_gold=MAX(0,treasury_gold-%d), treasury_silver=MAX(0,treasury_silver-%d), treasury_copper=MAX(0,treasury_copper-%d) WHERE id=%d", gold, silver, copper, party_id))
	} else {
		return print_error(db, "Operation must be 'add', 'remove', or 'set'")
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"party_id":%d,"operation":"%s","gold":%d,"silver":%d,"copper":%d}}` + "\n", party_id, op, gold, silver, copper)
	} else {
		fmt.printf("Party %d treasury updated: %s %d gp, %d sp, %d cp.\n", party_id, op, gold, silver, copper)
	}
	return 0
}
