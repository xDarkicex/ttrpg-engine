package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

CharacterStats :: struct {
	id: int,
	name: string,
	class: string,
	level: int,
	current_hp: int,
	max_hp: int,
	temp_hp: int,
	death_saves_success: int,
	death_saves_failure: int,
	exhaustion: int,
	hit_dice_expended: int,
	str: int,
	dex: int,
	con: int,
	int_: int,
	wis: int,
	cha: int,
	save_prof_str: int,
	save_prof_dex: int,
	save_prof_con: int,
	save_prof_int: int,
	save_prof_wis: int,
	save_prof_cha: int,
	ac: int,
	race: string,
	speed: int,
	status_effects: string,
	resistances: string,
	vulnerabilities: string,
	immunities: string,
	gold: int,
	silver: int,
	copper: int,
	platinum: int,
	electrum: int,
	inspiration: int,
	alignment: string,
	size: string,
	xp: int,
	faction_id: int,
	faction_name: string,
	campaign_id: int,
	last_action: string,
	party: string,
	backstory: string,
}

escape_sql :: proc(s: string) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == '\'' {
			strings.write_string(&builder, "''")
		} else {
			strings.write_byte(&builder, c)
		}
	}
	return strings.to_string(builder)
}

parse_int :: proc(s: string) -> int {
	result := 0
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c >= '0' && c <= '9' {
			result = result * 10 + int(c - '0')
		}
	}
	return result
}

is_numeric :: proc(s: string) -> bool {
	if len(s) == 0 do return false
	for i := 0; i < len(s); i += 1 {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

has_string_in_list :: proc(list_str: string, target: string) -> bool {
	if len(list_str) == 0 do return false
	if len(target) == 0 do return false

	start := 0
	for i := 0; i <= len(list_str); i += 1 {
		if i == len(list_str) || list_str[i] == ',' {
			item := list_str[start:i]
			if item == target {
				return true
			}
			start = i + 1
		}
	}
	return false
}

check_has_feature :: proc(db: ^lib.Db, char_id: int, feature_name: string) -> bool {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT COUNT(*) FROM character_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.character_id = %d AND f.name = '%s'",
		char_id, escape_sql(feature_name),
	)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return false
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) == .Row {
		count := sqlite.column_int(stmt, 0)
		return count > 0
	}
	return false
}

get_prof_bonus :: proc(level: int) -> int {
	if level >= 17 do return 6
	if level >= 13 do return 5
	if level >= 9 do return 4
	if level >= 5 do return 3
	return 2
}

calculate_modifier :: proc(stat_val: int) -> int {
	return (stat_val - 10) / 2
}

get_stat_and_prof :: proc(char: CharacterStats, save_type: string) -> (val: int, prof: bool) {
	switch save_type {
	case "str": return char.str, char.save_prof_str == 1
	case "dex": return char.dex, char.save_prof_dex == 1
	case "con": return char.con, char.save_prof_con == 1
	case "int": return char.int_, char.save_prof_int == 1
	case "wis": return char.wis, char.save_prof_wis == 1
	case "cha": return char.cha, char.save_prof_cha == 1
	}
	return 10, false
}

calculate_save_success :: proc(db: ^lib.Db, char: CharacterStats, save_type: string, dc: int, d20_roll: int) -> (success: bool, save_total: int, log_str: string) {
	stat_val, proficient := get_stat_and_prof(char, save_type)

	if has_string_in_list(char.status_effects, "unconscious") {
		if save_type == "str" || save_type == "dex" {
			return false, 0, "Unconscious: Auto-failed Dexterity/Strength saving throw"
		}
	}

	mod := calculate_modifier(stat_val)
	prof := proficient ? get_prof_bonus(char.level) : 0
	total := d20_roll + mod + prof

	log_val := fmt.tprintf("Saving Throw (%s): d20(%d) + mod(%d) + prof(%d) = %d vs DC %d",
		save_type, d20_roll, mod, prof, total, dc)

	return total >= dc, total, log_val
}

apply_save_reduction :: proc(db: ^lib.Db, char_id: int, amount: int, save_success: bool, is_dex_save: bool) -> (int, string) {
	dmg := amount
	has_evasion := is_dex_save && check_has_feature(db, char_id, "Evasion")

	if save_success {
		if has_evasion {
			return 0, "Evasion active: Took 0 damage on successful Dexterity save."
		}
		return dmg / 2, "Save succeeded: Took half damage."
	}

	if has_evasion {
		return dmg / 2, "Evasion active: Took half damage on failed Dexterity save."
	}

	return dmg, ""
}

apply_type_modifiers :: proc(char: CharacterStats, amount: int, damage_type: string) -> (int, string) {
	dmg := amount
	log_parts: [4]string
	log_count := 0

	has_res := has_string_in_list(char.resistances, damage_type)
	has_vuln := has_string_in_list(char.vulnerabilities, damage_type)

	if has_string_in_list(char.status_effects, "petrified") {
		has_res = true
		log_parts[log_count] = "Petrified: Resistant to all damage"
		log_count += 1
	}

	if damage_type == "poison" && char.race == "Dwarf" {
		has_res = true
		log_parts[log_count] = "Dwarven Resilience: Poison Resistance"
		log_count += 1
	}

	if has_string_in_list(char.immunities, damage_type) {
		return 0, fmt.tprintf("Immunity to %s: 0 damage.", damage_type)
	}

	// Resistance and Vulnerability BOTH apply if present (no stacking for same type, but order matters)
	// Order: apply Resistance first (round down), then Vulnerability (double)
	if has_res {
		dmg /= 2
		if has_string_in_list(char.resistances, damage_type) {
			log_parts[log_count] = fmt.tprintf("Resistance to %s: halved", damage_type)
			log_count += 1
		}
	}

	if has_vuln {
		dmg *= 2
		log_parts[log_count] = fmt.tprintf("Vulnerability to %s: doubled", damage_type)
		log_count += 1
	}

	log_str := strings.join(log_parts[:log_count], ", ", context.temp_allocator)
	return dmg, log_str
}

fetch_character_class_summary :: proc(db: ^lib.Db, char_id: int) -> (class_summary: string, total_level: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name, level FROM character_classes WHERE character_id=%d ORDER BY class_name", char_id)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return "None", 0
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	first := true

	for sqlite.step(stmt) == .Row {
		cls := sqlite.column_text(stmt, 0)
		lvl := int(sqlite.column_int(stmt, 1))
		total_level += lvl

		if !first do strings.write_string(&builder, " / ")
		first = false
		fmt.sbprintf(&builder, "%s %d", cls, lvl)
	}

	class_summary = fmt.tprintf("%s", strings.to_string(builder))
	if len(class_summary) == 0 do class_summary = "None"
	return
}

fetch_character_stats :: proc(db: ^lib.Db, id: int) -> (char: CharacterStats, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT c.id, c.name, c.current_hp, c.max_hp, c.temp_hp, c.death_saves_success, c.death_saves_failure, c.exhaustion, c.hit_dice_expended, c.str, c.dex, c.con, c.int_, c.wis, c.cha, c.save_prof_str, c.save_prof_dex, c.save_prof_con, c.save_prof_int, c.save_prof_wis, c.save_prof_cha, c.ac, c.race, c.speed, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.gold, c.silver, c.copper, c.platinum, c.electrum, c.inspiration, c.alignment, c.size, c.xp, c.faction_id, c.campaign_id, c.last_action, c.party, c.backstory, COALESCE(f.name, '') FROM characters c LEFT JOIN factions f ON c.faction_id = f.id WHERE c.id=%d",
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

	char.id = int(sqlite.column_int(stmt, 0))
	char.name = fmt.tprintf("%s", sqlite.column_text(stmt, 1))
	char.current_hp = int(sqlite.column_int(stmt, 2))
	char.max_hp = int(sqlite.column_int(stmt, 3))
	char.temp_hp = int(sqlite.column_int(stmt, 4))
	char.death_saves_success = int(sqlite.column_int(stmt, 5))
	char.death_saves_failure = int(sqlite.column_int(stmt, 6))
	char.exhaustion = int(sqlite.column_int(stmt, 7))
	char.hit_dice_expended = int(sqlite.column_int(stmt, 8))
	char.str = int(sqlite.column_int(stmt, 9))
	char.dex = int(sqlite.column_int(stmt, 10))
	char.con = int(sqlite.column_int(stmt, 11))
	char.int_ = int(sqlite.column_int(stmt, 12))
	char.wis = int(sqlite.column_int(stmt, 13))
	char.cha = int(sqlite.column_int(stmt, 14))
	char.save_prof_str = int(sqlite.column_int(stmt, 15))
	char.save_prof_dex = int(sqlite.column_int(stmt, 16))
	char.save_prof_con = int(sqlite.column_int(stmt, 17))
	char.save_prof_int = int(sqlite.column_int(stmt, 18))
	char.save_prof_wis = int(sqlite.column_int(stmt, 19))
	char.save_prof_cha = int(sqlite.column_int(stmt, 20))
	char.ac = int(sqlite.column_int(stmt, 21))
	char.race = fmt.tprintf("%s", sqlite.column_text(stmt, 22))
	char.speed = int(sqlite.column_int(stmt, 23))
	char.status_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 24))
	char.resistances = fmt.tprintf("%s", sqlite.column_text(stmt, 25))
	char.vulnerabilities = fmt.tprintf("%s", sqlite.column_text(stmt, 26))
	char.immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 27))
	char.gold = int(sqlite.column_int(stmt, 28))
	char.silver = int(sqlite.column_int(stmt, 29))
	char.copper = int(sqlite.column_int(stmt, 30))
	char.platinum = int(sqlite.column_int(stmt, 31))
	char.electrum = int(sqlite.column_int(stmt, 32))
	char.inspiration = int(sqlite.column_int(stmt, 33))
	char.alignment = fmt.tprintf("%s", sqlite.column_text(stmt, 34))
	char.size = fmt.tprintf("%s", sqlite.column_text(stmt, 35))
	char.xp = int(sqlite.column_int(stmt, 36))
	char.faction_id = int(sqlite.column_int(stmt, 37))
	char.campaign_id = int(sqlite.column_int(stmt, 38))
	char.last_action = fmt.tprintf("%s", sqlite.column_text(stmt, 39))
	char.party = fmt.tprintf("%s", sqlite.column_text(stmt, 40))
	char.backstory = fmt.tprintf("%s", sqlite.column_text(stmt, 41))
	char.faction_name = fmt.tprintf("%s", sqlite.column_text(stmt, 42))

	char.class, char.level = fetch_character_class_summary(db, id)

	return char, true
}

DamageArgs :: struct {
	id: int,
	amount: int,
	damage_type: string,
	attack_or_save: string,
	save_dc: int,
	d20_roll: int,
}

parse_damage_args :: proc(args: []string) -> DamageArgs {
	d: DamageArgs
	d.id = strconv.atoi(args[1])
	d.amount = strconv.atoi(args[2])
	if len(args) >= 4 do d.damage_type = args[3]
	if len(args) >= 5 do d.attack_or_save = args[4]
	if len(args) >= 6 do d.save_dc = strconv.atoi(args[5])
	if len(args) >= 7 do d.d20_roll = strconv.atoi(args[6])
	return d
}

character_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character create <name> <class> <level> <max_hp>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character create <name> <class> <level> <max_hp>")
		}
		return 1
	}
	name, class := args[1], args[2]
	level := strconv.atoi(args[3])
	max_hp := strconv.atoi(args[4])

	sql := fmt.tprintf(
		"INSERT INTO characters (name,max_hp,current_hp) VALUES('%s',%d,%d)",
		escape_sql(name), max_hp, max_hp,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create character"}`)
		} else {
			fmt.eprintln("Failed to create character")
		}
		return 1
	}

	char_id := get_last_insert_id(db)

	class_sql := fmt.tprintf("INSERT OR REPLACE INTO character_classes (character_id,class_name,level) VALUES(%d,'%s',%d)", char_id, escape_sql(class), level)
	lib.db_exec(db, class_sql)

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created character: %s","id":%d}}`, name, char_id)
		fmt.println()
	} else {
		fmt.println("Created:", name)
	}
	return 0
}

character_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,current_hp,max_hp,ac,race FROM characters ORDER BY id"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list characters"}`)
		} else {
			fmt.eprintln("Failed to list characters")
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
			id := int(sqlite.column_int(stmt, 0))
			name := column_text_safe(stmt, 1)
			curr_hp := int(sqlite.column_int(stmt, 2))
			max_hp := int(sqlite.column_int(stmt, 3))
			ac := int(sqlite.column_int(stmt, 4))
			race := column_text_safe(stmt, 5)

			class_summary, total_level := fetch_character_class_summary(db, id)

			fmt.sbprintf(&builder, `{{"id":%d,"name":"%s","class":"%s","level":%d,"current_hp":%d,"max_hp":%d,"ac":%d,"race":"%s"}}`,
				id, name, class_summary, total_level, curr_hp, max_hp, ac, race,
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			id := int(sqlite.column_int(stmt, 0))
			name := column_text_safe(stmt, 1)
			curr_hp := int(sqlite.column_int(stmt, 2))
			max_hp := int(sqlite.column_int(stmt, 3))
			ac := int(sqlite.column_int(stmt, 4))
			race := column_text_safe(stmt, 5)

			class_summary, total_level := fetch_character_class_summary(db, id)

			fmt.printf("[%d] %s (%s) Lvl%d HP:%d/%d AC:%d Race:%s\n",
				id, name, class_summary, total_level, curr_hp, max_hp, ac, race,
			)
		}
	}
	return 0
}

print_character_inventory_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			name := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			qty := int(sqlite.column_int(stmt, 1))
			eq := int(sqlite.column_int(stmt, 2))
			at := int(sqlite.column_int(stmt, 3))
			item_id := int(sqlite.column_int(stmt, 4))
			fmt.sbprintf(&builder, `{{"name":"{}","quantity":{},"equipped":{},"attuned":{},"item_id":{}}}`,
				escape_json_string(name), qty, eq, at, item_id,
			)
		}
		strings.write_byte(&builder, ']')
		fmt.print(strings.to_string(builder))
	} else {
		fmt.print("[]")
	}
}

print_character_inventory_text :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		fmt.println("  Inventory:")
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			name := sqlite.column_text(stmt, 0)
			qty := sqlite.column_int(stmt, 1)
			eq := sqlite.column_int(stmt, 2)
			at := sqlite.column_int(stmt, 3)
			item_id := sqlite.column_int(stmt, 4)

			status := ""
			if eq == 1 && at == 1 {
				status = " [E] [A]"
			} else if eq == 1 {
				status = " [E]"
			} else if at == 1 {
				status = " [A]"
			}
			fmt.printf("    %s x%d%s (ID: %d)\n", name, qty, status, item_id)
		}
		if !has_any do fmt.println("    Empty")
	}
}

print_character_abilities_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM character_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.character_id = %d ORDER BY f.source, f.name",
		char_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			id := sqlite.column_int(stmt, 0)
			name := fmt.tprintf("%s", sqlite.column_text(stmt, 1))
			source := fmt.tprintf("%s", sqlite.column_text(stmt, 2))
			desc := fmt.tprintf("%s", sqlite.column_text(stmt, 3))
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","source":"{}","description":"{}"}}`,
				id,
				escape_json_string(name),
				escape_json_string(source),
				escape_json_string(desc),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.print(strings.to_string(builder))
	} else {
		fmt.print("[]")
	}
}

print_character_abilities_text :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM character_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.character_id = %d ORDER BY f.source, f.name",
		char_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		fmt.println("  Abilities & Racial Traits:")
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			fmt.printf("    [%d] %s (%s) - %s\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
		if !has_any do fmt.println("    None")
	}
}

character_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character get <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character get <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])

	char, found := fetch_character_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Character not found"}`)
		} else {
			fmt.eprintln("Not found")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(
			`"id":%d,"name":"%s","class":"%s","level":%d,"current_hp":%d,"max_hp":%d,"temp_hp":%d,"death_saves_success":%d,"death_saves_failure":%d,"exhaustion":%d,"hit_dice_expended":%d,"ac":%d,"race":"%s","speed":%d,"stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},"save_proficiencies":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d,"inspiration":%d,"alignment":"%s","size":"%s","xp":%d,"faction_id":%d,"faction_name":"%s","campaign_id":%d,"last_action":"%s","party":"%s","backstory":"%s",`,
			char.id, char.name, char.class, char.level, char.current_hp, char.max_hp, char.temp_hp, char.death_saves_success, char.death_saves_failure, char.exhaustion, char.hit_dice_expended, char.ac, char.race, char.speed,
			char.str, char.dex, char.con, char.int_, char.wis, char.cha,
			char.save_prof_str, char.save_prof_dex, char.save_prof_con, char.save_prof_int, char.save_prof_wis, char.save_prof_cha,
			char.status_effects, char.resistances, char.vulnerabilities, char.immunities,
			char.gold, char.silver, char.copper, char.platinum, char.electrum, char.inspiration, char.alignment, char.size, char.xp, char.faction_id, escape_json_string(char.faction_name), char.campaign_id, escape_json_string(char.last_action), escape_json_string(char.party), escape_json_string(char.backstory),
		)
		fmt.print(`"skills":`)
		print_character_skills_json(db, char)
		fmt.print(`,"resources":`)
		print_character_resources_json(db, char.id)
		fmt.print(`,"inventory":`)
		print_character_inventory_json(db, char.id)
		fmt.print(`,"abilities":`)
		print_character_abilities_json(db, char.id)
		fmt.println("}")
	} else {
		faction_str := "None"
		if char.faction_id > 0 {
			if len(char.faction_name) > 0 {
				faction_str = fmt.tprintf("%s (ID: %d)", char.faction_name, char.faction_id)
			} else {
				faction_str = fmt.tprintf("ID: %d", char.faction_id)
			}
		}
		fmt.printf("[%d] %s (%s) Lvl%d HP:%d/%d (Temp: %d) AC:%d Race:%s Speed:%d XP:%d Faction: %s Campaign:%d\n",
			char.id, char.name, char.class, char.level, char.current_hp, char.max_hp, char.temp_hp, char.ac, char.race, char.speed,
			char.xp, faction_str, char.campaign_id,
		)
		fmt.printf("  Identity: Alignment: %s | Size: %s | Inspiration: %d | Exhaustion: %d | Spent Hit Dice: %d\n",
			char.alignment, char.size, char.inspiration, char.exhaustion, char.hit_dice_expended,
		)
		fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n",
			char.str, char.dex, char.con, char.int_, char.wis, char.cha,
		)
		fmt.printf("  Save Proficiencies: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n",
			char.save_prof_str, char.save_prof_dex, char.save_prof_con, char.save_prof_int, char.save_prof_wis, char.save_prof_cha,
		)
		fmt.printf("  Money: GP:%d SP:%d CP:%d PP:%d EP:%d\n", char.gold, char.silver, char.copper, char.platinum, char.electrum)
		fmt.printf("  Status: %s\n", len(char.status_effects) > 0 ? char.status_effects : "None")
		fmt.printf("  Resistances: %s\n", len(char.resistances) > 0 ? char.resistances : "None")
		fmt.printf("  Last Action: %s\n", len(char.last_action) > 0 ? char.last_action : "None")
		fmt.printf("  Party: %s\n", len(char.party) > 0 ? char.party : "None")
		fmt.printf("  Backstory: %s\n", len(char.backstory) > 0 ? char.backstory : "None")

		print_character_skills_text(db, char)
		print_character_resources_text(db, char.id)
		print_character_inventory_text(db, char.id)
		print_character_abilities_text(db, char.id)
	}

	return 0
}

character_delete :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character delete <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character delete <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	sql := fmt.tprintf("DELETE FROM characters WHERE id=%d", id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to delete character"}`)
		} else {
			fmt.eprintln("Failed to delete")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Deleted character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Deleted character", id)
	}
	return 0
}

character_damage :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]")
		}
		return 1
	}

	d := parse_damage_args(args)
	char, found := fetch_character_stats(db, d.id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Character not found"}`)
		} else {
			fmt.eprintln("Character not found")
		}
		return 1
	}

	attack_hit := true
	if is_numeric(d.attack_or_save) {
		attack_roll := strconv.atoi(d.attack_or_save)
		if attack_roll < char.ac {
			if db.is_json {
				fmt.printf(`{{"success":true,"id":%d,"attack_hit":false,"damage_applied":0,"current_hp":%d,"max_hp":%d}}`, char.id, char.current_hp, char.max_hp)
				fmt.println()
			} else {
				fmt.printf("Attack roll %d missed AC %d. 0 damage applied.\n", attack_roll, char.ac)
			}
			return 0
		}
	}

	final_dmg := d.amount
	is_save := len(d.attack_or_save) > 0 && !is_numeric(d.attack_or_save)
	save_success := false
	save_log := ""

	if is_save {
		var_success, _, var_log := calculate_save_success(db, char, d.attack_or_save, d.save_dc, d.d20_roll)
		save_success = var_success
		save_log = var_log
		
		save_red_log := ""
		final_dmg, save_red_log = apply_save_reduction(db, char.id, final_dmg, save_success, d.attack_or_save == "dex")
		if len(save_red_log) > 0 {
			save_log = fmt.tprintf("%s. %s", save_log, save_red_log)
		}
	}

	type_log := ""
	final_dmg, type_log = apply_type_modifiers(char, final_dmg, d.damage_type)
	if len(type_log) > 0 {
		if len(save_log) > 0 {
			save_log = fmt.tprintf("%s. %s", save_log, type_log)
		} else {
			save_log = type_log
		}
	}

	final_dmg_applied := final_dmg
	temp_hp := char.temp_hp
	curr_hp := char.current_hp

	if temp_hp > 0 {
		if final_dmg <= temp_hp {
			temp_hp -= final_dmg
			final_dmg = 0
		} else {
			final_dmg -= temp_hp
			temp_hp = 0
		}
	}

	new_hp := curr_hp - final_dmg
	if new_hp < 0 do new_hp = 0

	sql2 := fmt.tprintf("UPDATE characters SET current_hp=%d, temp_hp=%d WHERE id=%d", new_hp, temp_hp, d.id)
	if lib.db_exec(db, sql2) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"success":true,"id":%d,"damage_applied":%d,"current_hp":%d,"max_hp":%d,"temp_hp":%d,"attack_hit":%t,"save_success":%t,"save_log":"%s"}}`,
			char.id, final_dmg_applied, new_hp, char.max_hp, temp_hp, attack_hit, save_success, save_log,
		)
		fmt.println()
	} else {
		if len(save_log) > 0 do fmt.println(save_log)
		fmt.printf("Character HP now: %d/%d (Temp HP: %d) (Took %d damage)\n", new_hp, char.max_hp, temp_hp, final_dmg_applied)
		if new_hp == 0 {
			fmt.println("Character is unconscious/dying!")
		}
	}
	return 0
}

character_heal :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character heal <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character heal <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amt := strconv.atoi(args[2])

	char, found := fetch_character_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Character not found"}`)
		} else {
			fmt.eprintln("Character not found")
		}
		return 1
	}

	new_hp := char.current_hp + amt
	if new_hp > char.max_hp do new_hp = char.max_hp

	sql2 := fmt.tprintf("UPDATE characters SET current_hp=%d WHERE id=%d", new_hp, id)
	if lib.db_exec(db, sql2) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"id":%d,"current_hp":%d,"max_hp":%d}}`, id, new_hp, char.max_hp)
		fmt.println()
	} else {
		fmt.printf("Character HP now: %d/%d\n", new_hp, char.max_hp)
	}
	return 0
}

character_set_stats :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 8 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-stats <id> <str> <dex> <con> <int> <wis> <cha>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-stats <id> <str> <dex> <con> <int> <wis> <cha>")
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
		"UPDATE characters SET str=%d, dex=%d, con=%d, int_=%d, wis=%d, cha=%d WHERE id=%d",
		str, dex, con, int_, wis, cha, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set stats"}`)
		} else {
			fmt.eprintln("Failed to set stats")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Stats updated for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Stats updated for character", id)
	}
	return 0
}

character_set_save_prof :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 8 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-save-prof <id> <str> <dex> <con> <int> <wis> <cha>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-save-prof <id> <str> <dex> <con> <int> <wis> <cha>")
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
		"UPDATE characters SET save_prof_str=%d, save_prof_dex=%d, save_prof_con=%d, save_prof_int=%d, save_prof_wis=%d, save_prof_cha=%d WHERE id=%d",
		str, dex, con, int_, wis, cha, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set save proficiencies"}`)
		} else {
			fmt.eprintln("Failed to set saving throw proficiencies")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Saving throw proficiencies updated for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Saving throw proficiencies updated for character", id)
	}
	return 0
}

character_set_details :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-details <id> <ac> <race> <speed> [alignment] [size]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-details <id> <ac> <race> <speed> [alignment] [size]")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	ac := strconv.atoi(args[2])
	race := args[3]
	speed := strconv.atoi(args[4])

	sql: string
	if len(args) >= 7 {
		alignment := args[5]
		size := args[6]
		sql = fmt.tprintf(
			"UPDATE characters SET ac=%d, race='%s', speed=%d, alignment='%s', size='%s' WHERE id=%d",
			ac, escape_sql(race), speed, escape_sql(alignment), escape_sql(size), id,
		)
	} else if len(args) >= 6 {
		alignment := args[5]
		sql = fmt.tprintf(
			"UPDATE characters SET ac=%d, race='%s', speed=%d, alignment='%s' WHERE id=%d",
			ac, escape_sql(race), speed, escape_sql(alignment), id,
		)
	} else {
		sql = fmt.tprintf(
			"UPDATE characters SET ac=%d, race='%s', speed=%d WHERE id=%d",
			ac, escape_sql(race), speed, id,
		)
	}

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character details"}`)
		} else {
			fmt.eprintln("Failed to set character details")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Details updated for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Details updated for character", id)
	}
	return 0
}

character_set_combat_meta :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-combat-meta <id> <resistances> <vulnerabilities> <immunities>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-combat-meta <id> <resistances> <vulnerabilities> <immunities>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	res := args[2]
	vuln := args[3]
	imm := args[4]

	sql := fmt.tprintf(
		"UPDATE characters SET resistances='%s', vulnerabilities='%s', immunities='%s' WHERE id=%d",
		escape_sql(res), escape_sql(vuln), escape_sql(imm), id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set combat meta"}`)
		} else {
			fmt.eprintln("Failed to set combat meta")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Combat metadata updated for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Combat metadata updated for character", id)
	}
	return 0
}

character_set_status :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-status <id> <status_effects>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-status <id> <status_effects>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	status := args[2]

	sql := fmt.tprintf(
		"UPDATE characters SET status_effects='%s' WHERE id=%d",
		escape_sql(status), id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set status"}`)
		} else {
			fmt.eprintln("Failed to set status effects")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Status effects updated for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Status effects updated for character", id)
	}
	return 0
}

character_add_class :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character add-class <char_id> <class_name> <level>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character add-class <char_id> <class_name> <level>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	class_name := args[2]
	level := strconv.atoi(args[3])

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_classes (character_id,class_name,level) VALUES(%d,'%s',%d)",
		char_id, escape_sql(class_name), level,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add class"}`)
		} else {
			fmt.eprintln("Failed to add class")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added class %s Lvl%d to character %d"}}`, class_name, level, char_id)
		fmt.println()
	} else {
		fmt.printf("Added class %s Lvl%d to character %d\n", class_name, level, char_id)
	}
	return 0
}

character_list_classes :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character list-classes <char_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character list-classes <char_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name, level FROM character_classes WHERE character_id=%d ORDER BY class_name", char_id)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to get classes"}`)
		} else {
			fmt.eprintln("Failed to get classes")
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
			fmt.sbprintf(&builder, `{{"class":"{}","level":{}}}`, sqlite.column_text(stmt, 0), sqlite.column_int(stmt, 1))
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		fmt.printf("Classes for character %d:\n", char_id)
		for sqlite.step(stmt) == .Row {
			fmt.printf("  %s - Level %d\n", sqlite.column_text(stmt, 0), sqlite.column_int(stmt, 1))
		}
	}
	return 0
}

character_add_xp :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character add-xp <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character add-xp <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amt := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET xp=xp+%d WHERE id=%d", amt, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add XP"}`)
		} else {
			fmt.eprintln("Failed to add XP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added %d XP to character %d"}}`, amt, id)
		fmt.println()
	} else {
		fmt.printf("Added %d XP to character %d\n", amt, id)
	}
	return 0
}

character_add_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character add-money <id> <gold> <silver> <copper> [platinum] [electrum]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character add-money <id> <gold> <silver> <copper> [platinum] [electrum]")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])
	pp := 0
	if len(args) >= 6 do pp = strconv.atoi(args[5])
	ep := 0
	if len(args) >= 7 do ep = strconv.atoi(args[6])

	sql := fmt.tprintf(
		"UPDATE characters SET gold=gold+%d, silver=silver+%d, copper=copper+%d, platinum=platinum+%d, electrum=electrum+%d WHERE id=%d",
		gp, sp, cp, pp, ep, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add money"}`)
		} else {
			fmt.eprintln("Failed to add money")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added money to character %d","gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d}}`, id, gp, sp, cp, pp, ep)
		fmt.println()
	} else {
		fmt.printf("Added %d GP, %d SP, %d CP, %d PP, %d EP to character %d\n", gp, sp, cp, pp, ep, id)
	}
	return 0
}

character_remove_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character remove-money <id> <gold> <silver> <copper> [platinum] [electrum]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character remove-money <id> <gold> <silver> <copper> [platinum] [electrum]")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])
	pp := 0
	if len(args) >= 6 do pp = strconv.atoi(args[5])
	ep := 0
	if len(args) >= 7 do ep = strconv.atoi(args[6])

	sql := fmt.tprintf(
		"UPDATE characters SET gold=gold-%d, silver=silver-%d, copper=copper-%d, platinum=platinum-%d, electrum=electrum-%d WHERE id=%d",
		gp, sp, cp, pp, ep, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove money"}`)
		} else {
			fmt.eprintln("Failed to remove money")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Removed money from character %d","gold":%d,"silver":%d,"copper":%d","platinum":%d,"electrum":%d}}`, id, gp, sp, cp, pp, ep)
		fmt.println()
	} else {
		fmt.printf("Removed %d GP, %d SP, %d CP, %d PP, %d EP from character %d\n", gp, sp, cp, pp, ep, id)
	}
	return 0
}

character_set_action :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-action <id> <action>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-action <id> <action>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	action := args[2]

	sql := fmt.tprintf("UPDATE characters SET last_action='%s' WHERE id=%d", escape_sql(action), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update action"}`)
		} else {
			fmt.eprintln("Failed to update last action")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated last action for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Last action updated for character", id)
	}
	return 0
}

character_set_party :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-party <id> <party_name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-party <id> <party_name>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	party_name := args[2]

	sql := fmt.tprintf("UPDATE characters SET party='%s' WHERE id=%d", escape_sql(party_name), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update party"}`)
		} else {
			fmt.eprintln("Failed to update party")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated party for character %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Party updated for character", id)
	}
	return 0
}

character_set_campaign :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-campaign <id> <campaign_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-campaign <id> <campaign_id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	camp_id := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET campaign_id=%d WHERE id=%d", camp_id, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set campaign"}`)
		} else {
			fmt.eprintln("Failed to set campaign")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Campaign set to %d for character %d","id":%d,"campaign_id":%d}}`, camp_id, id, id, camp_id)
		fmt.println()
	} else {
		fmt.printf("Campaign set to %d for character %d\n", camp_id, id)
	}
	return 0
}

get_ability_modifier :: proc(score: int) -> int {
	return (score - 10) / 2 - (score < 10 && score % 2 != 0 ? 1 : 0)
}

get_skill_ability :: proc(char: CharacterStats, skill: string) -> int {
	s := strings.to_lower(skill, context.temp_allocator)
	switch s {
	case "athletics":
		return char.str
	case "acrobatics", "sleight of hand", "sleight_of_hand", "stealth":
		return char.dex
	case "arcana", "history", "investigation", "nature", "religion":
		return char.int_
	case "animal handling", "animal_handling", "insight", "medicine", "perception", "survival":
		return char.wis
	case "deception", "intimidation", "performance", "persuasion":
		return char.cha
	}
	return 10
}

print_character_skills_json :: proc(db: ^lib.Db, char: CharacterStats) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT skill_name, proficiency_level FROM character_skills WHERE character_id=%d ORDER BY skill_name", char.id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "[")
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_string(&builder, ",")
		first = false

		skill := column_text_safe(stmt, 0)
		prof_level := int(sqlite.column_int(stmt, 1))

		ability_score := get_skill_ability(char, skill)
		ability_mod := get_ability_modifier(ability_score)
		prof_bonus := 2 + (char.level - 1) / 4
		total_mod := ability_mod + prof_level * prof_bonus

		fmt.sbprintf(&builder, `{{"name":"%s","proficiency_level":%d,"modifier":%d}}`,
			escape_json_string(skill), prof_level, total_mod,
		)
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_character_skills_text :: proc(db: ^lib.Db, char: CharacterStats) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT skill_name, proficiency_level FROM character_skills WHERE character_id=%d ORDER BY skill_name", char.id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	has_rows := false
	for sqlite.step(stmt) == .Row {
		if !has_rows {
			fmt.println("  Skills & Proficiencies:")
			has_rows = true
		}
		skill := column_text_safe(stmt, 0)
		prof_level := int(sqlite.column_int(stmt, 1))

		ability_score := get_skill_ability(char, skill)
		ability_mod := get_ability_modifier(ability_score)
		prof_bonus := 2 + (char.level - 1) / 4
		total_mod := ability_mod + prof_level * prof_bonus

		prof_str := "None"
		if prof_level == 1 do prof_str = "Proficient"
		if prof_level == 2 do prof_str = "Expertise"

		fmt.printf("    - %s: %s (%+d)\n", skill, prof_str, total_mod)
	}
}

print_character_resources_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT resource_name, max_amount, current_amount, reset_condition FROM character_resources WHERE character_id=%d ORDER BY resource_name", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		fmt.print("[]")
		return
	}
	defer sqlite.finalize(stmt)

	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "[")
	first := true
	for sqlite.step(stmt) == .Row {
		if !first do strings.write_string(&builder, ",")
		first = false

		name := column_text_safe(stmt, 0)
		max_val := int(sqlite.column_int(stmt, 1))
		curr_val := int(sqlite.column_int(stmt, 2))
		reset_cond := column_text_safe(stmt, 3)

		fmt.sbprintf(&builder, `{{"name":"%s","max_amount":%d,"current_amount":%d,"reset_condition":"%s"}}`,
			escape_json_string(name), max_val, curr_val, escape_json_string(reset_cond),
		)
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_character_resources_text :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT resource_name, max_amount, current_amount, reset_condition FROM character_resources WHERE character_id=%d ORDER BY resource_name", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	has_rows := false
	for sqlite.step(stmt) == .Row {
		if !has_rows {
			fmt.println("  Class Resources:")
			has_rows = true
		}
		name := column_text_safe(stmt, 0)
		max_val := int(sqlite.column_int(stmt, 1))
		curr_val := int(sqlite.column_int(stmt, 2))
		reset_cond := column_text_safe(stmt, 3)

		fmt.printf("    - %s: %d/%d (Reset: %s)\n", name, curr_val, max_val, reset_cond)
	}
}

character_set_temp_hp :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-temp-hp <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-temp-hp <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amount := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET temp_hp=%d WHERE id=%d", amount, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set temporary HP"}`)
		} else {
			fmt.eprintln("Failed to set temporary HP")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Temporary HP set","id":%d,"temp_hp":%d`, id, amount)
		fmt.println("}")
	} else {
		fmt.printf("Temporary HP set to %d for character %d\n", amount, id)
	}
	return 0
}

character_set_death_saves :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-death-saves <id> <successes> <failures>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-death-saves <id> <successes> <failures>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	successes := strconv.atoi(args[2])
	failures := strconv.atoi(args[3])

	if successes < 0 || successes > 3 || failures < 0 || failures > 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Death saves must be between 0 and 3"}`)
		} else {
			fmt.eprintln("Error: Successes and failures must be between 0 and 3")
		}
		return 1
	}

	sql := fmt.tprintf(
		"UPDATE characters SET death_saves_success=%d, death_saves_failure=%d WHERE id=%d",
		successes, failures, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set death saves"}`)
		} else {
			fmt.eprintln("Failed to set death saves")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Death saves set","id":%d,"successes":%d,"failures":%d`, id, successes, failures)
		fmt.println("}")
	} else {
		fmt.printf("Death saves set to %d successes and %d failures for character %d\n", successes, failures, id)
	}
	return 0
}

character_set_exhaustion :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-exhaustion <id> <level>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-exhaustion <id> <level>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	level := strconv.atoi(args[2])

	if level < 0 || level > 6 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Exhaustion level must be between 0 and 6"}`)
		} else {
			fmt.eprintln("Error: Exhaustion level must be between 0 and 6")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE characters SET exhaustion=%d WHERE id=%d", level, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set exhaustion level"}`)
		} else {
			fmt.eprintln("Failed to set exhaustion level")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Exhaustion set","id":%d,"exhaustion":%d`, id, level)
		fmt.println("}")
	} else {
		fmt.printf("Exhaustion level set to %d for character %d\n", level, id)
	}
	return 0
}

character_set_hit_dice :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-hit-dice <id> <expended>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-hit-dice <id> <expended>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	expended := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET hit_dice_expended=%d WHERE id=%d", expended, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set expended hit dice"}`)
		} else {
			fmt.eprintln("Failed to set expended hit dice")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Hit dice expended set","id":%d,"hit_dice_expended":%d`, id, expended)
		fmt.println("}")
	} else {
		fmt.printf("Expended hit dice count set to %d for character %d\n", expended, id)
	}
	return 0
}

character_set_inspiration :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-inspiration <id> <0/1>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-inspiration <id> <0/1>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	inspiration := strconv.atoi(args[2])

	if inspiration != 0 && inspiration != 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Inspiration must be 0 or 1"}`)
		} else {
			fmt.eprintln("Error: Inspiration must be 0 or 1")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE characters SET inspiration=%d WHERE id=%d", inspiration, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set inspiration"}`)
		} else {
			fmt.eprintln("Failed to set inspiration")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Inspiration set","id":%d,"inspiration":%d`, id, inspiration)
		fmt.println("}")
	} else {
		fmt.printf("Inspiration set to %d for character %d\n", inspiration, id)
	}
	return 0
}

character_set_skill :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-skill <char_id> <skill_name> <proficiency_level>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-skill <char_id> <skill_name> <proficiency_level>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	skill_name := args[2]
	prof_level := strconv.atoi(args[3])

	if prof_level < 0 || prof_level > 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Proficiency level must be 0 (none), 1 (proficient), or 2 (expertise)"}`)
		} else {
			fmt.eprintln("Error: Proficiency level must be 0 (none), 1 (proficient), or 2 (expertise)")
		}
		return 1
	}

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_skills (character_id, skill_name, proficiency_level) VALUES (%d, '%s', %d)",
		char_id, escape_sql(skill_name), prof_level,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set skill proficiency"}`)
		} else {
			fmt.eprintln("Failed to set skill proficiency")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Skill set","character_id":%d,"skill_name":"%s","proficiency_level":%d`, char_id, escape_json_string(skill_name), prof_level)
		fmt.println("}")
	} else {
		fmt.printf("Skill %s set to proficiency level %d for character %d\n", skill_name, prof_level, char_id)
	}
	return 0
}

character_list_skills :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character list-skills <char_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character list-skills <char_id>")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	char, found := fetch_character_stats(db, char_id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Character not found"}`)
		} else {
			fmt.eprintln("Character not found")
		}
		return 1
	}

	if db.is_json {
		print_character_skills_json(db, char)
		fmt.println()
	} else {
		fmt.printf("Skills for %s (ID: %d):\n", char.name, char.id)
		stmt: ^sqlite.Statement
		sql := fmt.tprintf("SELECT skill_name, proficiency_level FROM character_skills WHERE character_id=%d ORDER BY skill_name", char.id)
		sql_c := cstring(raw_data(sql))
		if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
			defer sqlite.finalize(stmt)
			has_any := false
			for sqlite.step(stmt) == .Row {
				has_any = true
				skill := column_text_safe(stmt, 0)
				prof_level := int(sqlite.column_int(stmt, 1))

				ability_score := get_skill_ability(char, skill)
				ability_mod := get_ability_modifier(ability_score)
				prof_bonus := 2 + (char.level - 1) / 4
				total_mod := ability_mod + prof_level * prof_bonus

				prof_str := "None"
				if prof_level == 1 do prof_str = "Proficient"
				if prof_level == 2 do prof_str = "Expertise"

				fmt.printf("  - %s: %s (%+d)\n", skill, prof_str, total_mod)
			}
			if !has_any {
				fmt.println("  No skill proficiencies set.")
			}
		}
	}
	return 0
}

character_set_resource :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-resource <char_id> <resource_name> <max> <current> [reset_condition]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-resource <char_id> <resource_name> <max> <current> [reset_condition]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	resource_name := args[2]
	max_val := strconv.atoi(args[3])
	curr_val := strconv.atoi(args[4])
	reset_condition := "long_rest"
	if len(args) >= 6 do reset_condition = args[5]

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, '%s', %d, %d, '%s')",
		char_id, escape_sql(resource_name), max_val, curr_val, escape_sql(reset_condition),
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character resource"}`)
		} else {
			fmt.eprintln("Failed to set character resource")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Resource set","character_id":%d,"resource_name":"%s","max_amount":%d,"current_amount":%d,"reset_condition":"%s"`, char_id, escape_json_string(resource_name), max_val, curr_val, escape_json_string(reset_condition))
		fmt.println("}")
	} else {
		fmt.printf("Resource %s set to %d/%d (Reset: %s) for character %d\n", resource_name, curr_val, max_val, reset_condition, char_id)
	}
	return 0
}

character_use_resource :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character use-resource <char_id> <resource_name> [amount]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character use-resource <char_id> <resource_name> [amount]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	resource_name := args[2]
	amount := 1
	if len(args) >= 4 do amount = strconv.atoi(args[3])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT current_amount, max_amount FROM character_resources WHERE character_id=%d AND resource_name='%s'", char_id, escape_sql(resource_name))
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to prepare select query"}`)
		} else {
			fmt.eprintln("Failed to query resource status")
		}
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Resource not found for character"}`)
		} else {
			fmt.eprintln("Resource not found for character")
		}
		return 1
	}

	curr_val := int(sqlite.column_int(stmt, 0))
	max_val := int(sqlite.column_int(stmt, 1))

	if curr_val < amount {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Insufficient resource amount"}`)
		} else {
			fmt.printf("Error: Insufficient resource. Current: %d, trying to use: %d\n", curr_val, amount)
		}
		return 1
	}

	new_amount := curr_val - amount
	update_sql := fmt.tprintf("UPDATE character_resources SET current_amount=%d WHERE character_id=%d AND resource_name='%s'", new_amount, char_id, escape_sql(resource_name))
	if lib.db_exec(db, update_sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update resource"}`)
		} else {
			fmt.eprintln("Failed to update resource")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Resource used","character_id":%d,"resource_name":"%s","used_amount":%d,"current_amount":%d,"max_amount":%d`, char_id, escape_json_string(resource_name), amount, new_amount, max_val)
		fmt.println("}")
	} else {
		fmt.printf("Used %d of resource %s. Remaining: %d/%d for character %d\n", amount, resource_name, new_amount, max_val, char_id)
	}
	return 0
}

character_reset_resources :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character reset-resources <char_id> [reset_condition]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character reset-resources <char_id> [reset_condition]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	sql: string
	if len(args) >= 3 {
		cond := args[2]
		if cond == "long_rest" {
			sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition IN ('long_rest', 'short_rest')", char_id)
		} else if cond == "short_rest" {
			sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition='short_rest'", char_id)
		} else {
			sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition='%s'", char_id, escape_sql(cond))
		}
	} else {
		sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d", char_id)
	}

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to reset resources"}`)
		} else {
			fmt.eprintln("Failed to reset resources")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Resources reset","character_id":%d`, char_id)
		fmt.println("}")
	} else {
		if len(args) >= 3 {
			fmt.printf("Resources with reset condition matching '%s' reset for character %d\n", args[2], char_id)
		} else {
			fmt.printf("All resources reset for character %d\n", char_id)
		}
	}
	return 0
}

character_list_resources :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character list-resources <char_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character list-resources <char_id>")
		}
		return 1
	}
	char_id, _ := strconv.parse_int(args[1])

	if db.is_json {
		print_character_resources_json(db, char_id)
		fmt.println()
	} else {
		fmt.printf("Resources for character %d:\n", char_id)
		stmt: ^sqlite.Statement
		sql := fmt.tprintf("SELECT resource_name, max_amount, current_amount, reset_condition FROM character_resources WHERE character_id=%d ORDER BY resource_name", char_id)
		sql_c := cstring(raw_data(sql))
		if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
			defer sqlite.finalize(stmt)
			has_any := false
			for sqlite.step(stmt) == .Row {
				has_any = true
				name := column_text_safe(stmt, 0)
				max_val := int(sqlite.column_int(stmt, 1))
				curr_val := int(sqlite.column_int(stmt, 2))
				reset_cond := column_text_safe(stmt, 3)
				fmt.printf("  - %s: %d/%d (Reset: %s)\n", name, curr_val, max_val, reset_cond)
			}
			if !has_any {
				fmt.println("  No resources configured.")
			}
		}
	}
	return 0
}

character_set_backstory :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-backstory <id> <backstory>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-backstory <id> <backstory>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	backstory := args[2]

	sql := fmt.tprintf("UPDATE characters SET backstory='%s' WHERE id=%d", escape_sql(backstory), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set backstory"}`)
		} else {
			fmt.eprintln("Failed to set backstory")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Backstory set","id":%d,"backstory":"%s"`, id, escape_json_string(backstory))
		fmt.println("}")
	} else {
		fmt.printf("Backstory set for character %d\n", id)
	}
	return 0
}