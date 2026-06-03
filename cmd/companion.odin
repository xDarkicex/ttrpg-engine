package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

CompanionStats :: struct {
	id: int,
	character_id: int,
	name: string,
	type: string,
	level: int,
	max_hp: int,
	current_hp: int,
	ac: int,
	attack_bonus: int,
	damage_dice: string,
	str: int,
	dex: int,
	con: int,
	int_: int,
	wis: int,
	cha: int,
	status_effects: string,
	resistances: string,
	vulnerabilities: string,
	immunities: string,
	last_action: string,
}

companion_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 9 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion create <char_id> <name> <type> <level> <max_hp> <ac> <attack_bonus> <damage_dice>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion create <char_id> <name> <type> <level> <max_hp> <ac> <attack_bonus> <damage_dice>")
		}
		return 1
	}

	char_id := strconv.atoi(args[1])
	name := args[2]
	comp_type := args[3]
	level := strconv.atoi(args[4])
	max_hp := strconv.atoi(args[5])
	ac := strconv.atoi(args[6])
	atk_bonus := strconv.atoi(args[7])
	dmg_dice := args[8]

	sql := fmt.tprintf(
		"INSERT INTO companions (character_id,name,type,level,max_hp,current_hp,ac,attack_bonus,damage_dice) VALUES(%d,'%s','%s',%d,%d,%d,%d,%d,'%s')",
		char_id, escape_sql(name), escape_sql(comp_type), level, max_hp, max_hp, ac, atk_bonus, escape_sql(dmg_dice),
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create companion"}`)
		} else {
			fmt.eprintln("Failed to create companion")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created companion: %s for character %d"}}\n`, name, char_id)
	} else {
		fmt.printf("Created companion %s for character %d\n", name, char_id)
	}
	return 0
}

companion_set_stats :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 8 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion set-stats <id> <str> <dex> <con> <int> <wis> <cha>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion set-stats <id> <str> <dex> <con> <int> <wis> <cha>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	str := strconv.atoi(args[2])
	dex := strconv.atoi(args[3])
	con := strconv.atoi(args[4])
	int_ := strconv.atoi(args[5])
	wis := strconv.atoi(args[6])
	cha := strconv.atoi(args[7])

	sql := fmt.tprintf(
		"UPDATE companions SET str=%d, dex=%d, con=%d, int_=%d, wis=%d, cha=%d WHERE id=%d",
		str, dex, con, int_, wis, cha, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update stats"}`)
		} else {
			fmt.eprintln("Failed to update stats")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated stats for companion %d"}}\n`, id)
	} else {
		fmt.println("Stats updated for companion", id)
	}
	return 0
}

companion_list :: proc(db: ^lib.Db, args: []string) -> int {
	char_id := 0
	if len(args) >= 2 {
		char_id = strconv.atoi(args[1])
	}

	stmt: ^sqlite.Statement
	sql := ""
	if char_id > 0 {
		sql = fmt.tprintf("SELECT id, name, type, level, current_hp, max_hp, character_id FROM companions WHERE character_id=%d ORDER BY id", char_id)
	} else {
		sql = "SELECT id, name, type, level, current_hp, max_hp, character_id FROM companions ORDER BY id"
	}
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list companions"}`)
		} else {
			fmt.eprintln("Failed to list companions")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","type":"{}","level":{},"current_hp":{},"max_hp":{},"character_id":{}}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_int(stmt, 4),
				sqlite.column_int(stmt, 5),
				sqlite.column_int(stmt, 6),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s (%s) Lvl%d HP:%d/%d (Owner char:%d)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_int(stmt, 4),
				sqlite.column_int(stmt, 5),
				sqlite.column_int(stmt, 6),
			)
		}
	}
	return 0
}

fetch_companion_stats :: proc(db: ^lib.Db, id: int) -> (comp: CompanionStats, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT id, character_id, name, type, level, max_hp, current_hp, ac, attack_bonus, damage_dice, str, dex, con, int_, wis, cha, status_effects, resistances, vulnerabilities, immunities, last_action FROM companions WHERE id=%d",
		id,
	)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return {}, false
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		return {}, false
	}

	comp.id = int(sqlite.column_int(stmt, 0))
	comp.character_id = int(sqlite.column_int(stmt, 1))
	comp.name = fmt.tprintf("%s", sqlite.column_text(stmt, 2))
	comp.type = fmt.tprintf("%s", sqlite.column_text(stmt, 3))
	comp.level = int(sqlite.column_int(stmt, 4))
	comp.max_hp = int(sqlite.column_int(stmt, 5))
	comp.current_hp = int(sqlite.column_int(stmt, 6))
	comp.ac = int(sqlite.column_int(stmt, 7))
	comp.attack_bonus = int(sqlite.column_int(stmt, 8))
	comp.damage_dice = fmt.tprintf("%s", sqlite.column_text(stmt, 9))
	comp.str = int(sqlite.column_int(stmt, 10))
	comp.dex = int(sqlite.column_int(stmt, 11))
	comp.con = int(sqlite.column_int(stmt, 12))
	comp.int_ = int(sqlite.column_int(stmt, 13))
	comp.wis = int(sqlite.column_int(stmt, 14))
	comp.cha = int(sqlite.column_int(stmt, 15))
	comp.status_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 16))
	comp.resistances = fmt.tprintf("%s", sqlite.column_text(stmt, 17))
	comp.vulnerabilities = fmt.tprintf("%s", sqlite.column_text(stmt, 18))
	comp.immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 19))
	comp.last_action = fmt.tprintf("%s", sqlite.column_text(stmt, 20))

	return comp, true
}

companion_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion get <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion get <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])

	comp, found := fetch_companion_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Companion not found"}`)
		} else {
			fmt.eprintln("Companion not found")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"id":%d,"character_id":%d,"name":"%s","type":"%s","level":%d,"current_hp":%d,"max_hp":%d,"ac":%d,"attack_bonus":%d,"damage_dice":"%s","stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","last_action":"%s"}}\n`,
			comp.id, comp.character_id, comp.name, comp.type, comp.level, comp.current_hp, comp.max_hp, comp.ac, comp.attack_bonus, comp.damage_dice,
			comp.str, comp.dex, comp.con, comp.int_, comp.wis, comp.cha, comp.status_effects, comp.resistances, comp.vulnerabilities, comp.immunities, comp.last_action,
		)
	} else {
		fmt.printf("[%d] %s (%s) Lvl%d HP:%d/%d AC:%d AtkBonus:+%d DmgDice:%s\n",
			comp.id, comp.name, comp.type, comp.level, comp.current_hp, comp.max_hp, comp.ac, comp.attack_bonus, comp.damage_dice,
		)
		fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n",
			comp.str, comp.dex, comp.con, comp.int_, comp.wis, comp.cha,
		)
		fmt.printf("  Status: %s\n", len(comp.status_effects) > 0 ? comp.status_effects : "None")
		fmt.printf("  Resistances: %s\n", len(comp.resistances) > 0 ? comp.resistances : "None")
		fmt.printf("  Last Action: %s\n", len(comp.last_action) > 0 ? comp.last_action : "None")
	}
	return 0
}

companion_heal :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion heal <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion heal <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amt := strconv.atoi(args[2])

	comp, found := fetch_companion_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Companion not found"}`)
		} else {
			fmt.eprintln("Companion not found")
		}
		return 1
	}

	new_hp := comp.current_hp + amt
	if new_hp > comp.max_hp do new_hp = comp.max_hp

	sql := fmt.tprintf("UPDATE companions SET current_hp=%d WHERE id=%d", new_hp, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"id":%d,"current_hp":%d,"max_hp":%d}}\n`, id, new_hp, comp.max_hp)
	} else {
		fmt.printf("Companion HP now: %d/%d\n", new_hp, comp.max_hp)
	}
	return 0
}

calculate_companion_save :: proc(comp: CompanionStats, save_type: string, dc: int, d20_roll: int) -> (success: bool, save_total: int, log_str: string) {
	stat_val := 10
	switch save_type {
	case "str": stat_val = comp.str
	case "dex": stat_val = comp.dex
	case "con": stat_val = comp.con
	case "int": stat_val = comp.int_
	case "wis": stat_val = comp.wis
	case "cha": stat_val = comp.cha
	}

	if has_string_in_list(comp.status_effects, "unconscious") {
		if save_type == "str" || save_type == "dex" {
			return false, 0, "Unconscious: Auto-failed Dex/Str saving throw"
		}
	}

	mod := (stat_val - 10) / 2
	total := d20_roll + mod

	log_val := fmt.tprintf("Saving Throw (%s): d20(%d) + mod(%d) = %d vs DC %d", save_type, d20_roll, mod, total, dc)
	return total >= dc, total, log_val
}

companion_damage :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]")
		}
		return 1
	}

	d := parse_damage_args(args)
	comp, found := fetch_companion_stats(db, d.id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Companion not found"}`)
		} else {
			fmt.eprintln("Companion not found")
		}
		return 1
	}

	attack_hit := true
	if is_numeric(d.attack_or_save) {
		attack_roll := strconv.atoi(d.attack_or_save)
		if attack_roll < comp.ac {
			if db.is_json {
				fmt.printf(`{{"success":true,"id":%d,"attack_hit":false,"damage_applied":0,"current_hp":%d,"max_hp":%d}}\n`, comp.id, comp.current_hp, comp.max_hp)
			} else {
				fmt.printf("Attack roll %d missed companion AC %d. 0 damage applied.\n", attack_roll, comp.ac)
			}
			return 0
		}
	}

	final_dmg := d.amount
	is_save := len(d.attack_or_save) > 0 && !is_numeric(d.attack_or_save)
	save_success := false
	save_log := ""

	if is_save {
		var_success, _, var_log := calculate_companion_save(comp, d.attack_or_save, d.save_dc, d.d20_roll)
		save_success = var_success
		save_log = var_log
		if save_success {
			save_log = fmt.tprintf("%s. Succeeded: Took half damage.", save_log)
			final_dmg /= 2
		} else {
			save_log = fmt.tprintf("%s. Failed: Took full damage.", save_log)
		}
	}

	// Resistances math
	has_res := has_string_in_list(comp.resistances, d.damage_type)
	if has_string_in_list(comp.status_effects, "petrified") {
		has_res = true
	}

	if has_string_in_list(comp.immunities, d.damage_type) {
		final_dmg = 0
	} else if has_res {
		final_dmg /= 2
	} else if has_string_in_list(comp.vulnerabilities, d.damage_type) {
		final_dmg *= 2
	}

	new_hp := comp.current_hp - final_dmg
	if new_hp < 0 do new_hp = 0

	sql := fmt.tprintf("UPDATE companions SET current_hp=%d WHERE id=%d", new_hp, d.id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"success":true,"id":%d,"damage_applied":%d,"current_hp":%d,"max_hp":%d,"attack_hit":%t,"save_success":%t,"save_log":"%s"}}\n`,
			comp.id, final_dmg, new_hp, comp.max_hp, attack_hit, save_success, save_log,
		)
	} else {
		if len(save_log) > 0 do fmt.println(save_log)
		fmt.printf("Companion HP now: %d/%d (Took %d damage)\n", new_hp, comp.max_hp, final_dmg)
	}
	return 0
}
