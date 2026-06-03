package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

CreatureStats :: struct {
	id: int,
	name: string,
	current_hp: int,
	max_hp: int,
	ac: int,
	status_effects: string,
	resistances: string,
	vulnerabilities: string,
	immunities: string,
	attacks: string,
	story_role: string,
	last_action: string,
	campaign_id: int,
	location_id: int,
	location_name: string,
}

creature_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 7 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature create <name> <max_hp> <ac> <attacks> <story_role> <campaign_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature create <name> <max_hp> <ac> <attacks> <story_role> <campaign_id>")
		}
		return 1
	}

	name := args[1]
	max_hp, _ := strconv.parse_int(args[2])
	ac, _ := strconv.parse_int(args[3])
	attacks := args[4]
	story_role := args[5]
	campaign_id, _ := strconv.parse_int(args[6])

	sql := fmt.tprintf(
		"INSERT INTO creatures (name,current_hp,max_hp,ac,attacks,story_role,campaign_id) VALUES('%s',%d,%d,%d,'%s','%s',%d)",
		escape_sql(name), max_hp, max_hp, ac, escape_sql(attacks), escape_sql(story_role), campaign_id,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create creature"}`)
		} else {
			fmt.eprintln("Failed to create creature")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created creature: %s"}}`, name)
		fmt.println()
	} else {
		fmt.println("Created creature:", name)
	}
	return 0
}

creature_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id, name, current_hp, max_hp, ac, campaign_id FROM creatures ORDER BY id"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list creatures"}`)
		} else {
			fmt.eprintln("Failed to list creatures")
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","current_hp":{},"max_hp":{},"ac":{},"campaign_id":{}}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_int(stmt, 4),
				sqlite.column_int(stmt, 5),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		for sqlite.step(stmt) == .Row {
			fmt.printf("[%d] %s HP:%d/%d AC:%d (Camp:%d)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_int(stmt, 2),
				sqlite.column_int(stmt, 3),
				sqlite.column_int(stmt, 4),
				sqlite.column_int(stmt, 5),
			)
		}
	}
	return 0
}

fetch_creature_stats :: proc(db: ^lib.Db, id: int) -> (c: CreatureStats, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT c.id, c.name, c.current_hp, c.max_hp, c.ac, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.attacks, c.story_role, c.last_action, c.campaign_id, c.location_id, COALESCE(l.name, '') FROM creatures c LEFT JOIN locations l ON c.location_id = l.id WHERE c.id=%d",
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

	c.id = int(sqlite.column_int(stmt, 0))
	c.name = fmt.tprintf("%s", sqlite.column_text(stmt, 1))
	c.current_hp = int(sqlite.column_int(stmt, 2))
	c.max_hp = int(sqlite.column_int(stmt, 3))
	c.ac = int(sqlite.column_int(stmt, 4))
	c.status_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 5))
	c.resistances = fmt.tprintf("%s", sqlite.column_text(stmt, 6))
	c.vulnerabilities = fmt.tprintf("%s", sqlite.column_text(stmt, 7))
	c.immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 8))
	c.attacks = fmt.tprintf("%s", sqlite.column_text(stmt, 9))
	c.story_role = fmt.tprintf("%s", sqlite.column_text(stmt, 10))
	c.last_action = fmt.tprintf("%s", sqlite.column_text(stmt, 11))
	c.campaign_id = int(sqlite.column_int(stmt, 12))
	c.location_id = int(sqlite.column_int(stmt, 13))
	c.location_name = fmt.tprintf("%s", sqlite.column_text(stmt, 14))

	return c, true
}

creature_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature get <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature get <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])

	c, found := fetch_creature_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Creature not found"}`)
		} else {
			fmt.eprintln("Creature not found")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"id":%d,"name":"%s","current_hp":%d,"max_hp":%d,"ac":%d,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","attacks":"%s","story_role":"%s","last_action":"%s","campaign_id":%d,"location_id":%d,"location_name":"%s"}}`,
			c.id, c.name, c.current_hp, c.max_hp, c.ac, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.attacks, c.story_role, c.last_action,
			c.campaign_id, c.location_id, c.location_name,
		)
		fmt.println()
	} else {
		fmt.printf("[%d] %s HP:%d/%d AC:%d Campaign:%d\n", c.id, c.name, c.current_hp, c.max_hp, c.ac, c.campaign_id)
		fmt.printf("  Location: %s (ID: %d)\n", len(c.location_name) > 0 ? c.location_name : "None", c.location_id)
		fmt.printf("  Attacks: %s\n", c.attacks)
		fmt.printf("  Status: %s\n", len(c.status_effects) > 0 ? c.status_effects : "None")
		fmt.printf("  Resistances: %s\n", len(c.resistances) > 0 ? c.resistances : "None")
		fmt.printf("  Story Role: %s\n", c.story_role)
		fmt.printf("  Last Action: %s\n", len(c.last_action) > 0 ? c.last_action : "None")
	}
	return 0
}

creature_heal :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature heal <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature heal <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amt := strconv.atoi(args[2])

	c, found := fetch_creature_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Creature not found"}`)
		} else {
			fmt.eprintln("Creature not found")
		}
		return 1
	}

	new_hp := c.current_hp + amt
	if new_hp > c.max_hp do new_hp = c.max_hp

	sql := fmt.tprintf("UPDATE creatures SET current_hp=%d WHERE id=%d", new_hp, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"id":%d,"current_hp":%d,"max_hp":%d}}`, id, new_hp, c.max_hp)
		fmt.println()
	} else {
		fmt.printf("Creature HP now: %d/%d\n", new_hp, c.max_hp)
	}
	return 0
}

creature_set_status :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-status <id> <status_effects>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-status <id> <status_effects>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	status := args[2]

	sql := fmt.tprintf("UPDATE creatures SET status_effects='%s' WHERE id=%d", escape_sql(status), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update status"}`)
		} else {
			fmt.eprintln("Failed to update status")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated status for creature %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Status updated for creature", id)
	}
	return 0
}

creature_set_combat_meta :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-combat-meta <id> <resistances> <vulnerabilities> <immunities>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-combat-meta <id> <resistances> <vulnerabilities> <immunities>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	res := args[2]
	vuln := args[3]
	imm := args[4]

	sql := fmt.tprintf("UPDATE creatures SET resistances='%s', vulnerabilities='%s', immunities='%s' WHERE id=%d", escape_sql(res), escape_sql(vuln), escape_sql(imm), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update combat meta"}`)
		} else {
			fmt.eprintln("Failed to update combat meta")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated combat meta for creature %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Combat meta updated for creature", id)
	}
	return 0
}

creature_set_action :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-action <id> <action>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-action <id> <action>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	action := args[2]

	sql := fmt.tprintf("UPDATE creatures SET last_action='%s' WHERE id=%d", escape_sql(action), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update action"}`)
		} else {
			fmt.eprintln("Failed to update action")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated action for creature %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Action updated for creature", id)
	}
	return 0
}

creature_damage :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]")
		}
		return 1
	}

	d := parse_damage_args(args)
	c, found := fetch_creature_stats(db, d.id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Creature not found"}`)
		} else {
			fmt.eprintln("Creature not found")
		}
		return 1
	}

	attack_hit := true
	if is_numeric(d.attack_or_save) {
		attack_roll := strconv.atoi(d.attack_or_save)
		if attack_roll < c.ac {
			if db.is_json {
				fmt.printf(`{{"success":true,"id":%d,"attack_hit":false,"damage_applied":0,"current_hp":%d,"max_hp":%d}}`, c.id, c.current_hp, c.max_hp)
				fmt.println()
			} else {
				fmt.printf("Attack roll %d missed creature AC %d. 0 damage applied.\n", attack_roll, c.ac)
			}
			return 0
		}
	}

	final_dmg := d.amount
	is_save := len(d.attack_or_save) > 0 && !is_numeric(d.attack_or_save)
	save_success := false
	save_log := ""

	if is_save {
		if d.d20_roll >= d.save_dc {
			save_success = true
			save_log = fmt.tprintf("Saving Throw (%s): d20(%d) vs DC %d. Succeeded: Took half damage.", d.attack_or_save, d.d20_roll, d.save_dc)
			final_dmg /= 2
		} else {
			save_log = fmt.tprintf("Saving Throw (%s): d20(%d) vs DC %d. Failed: Took full damage.", d.attack_or_save, d.d20_roll, d.save_dc)
		}
	}

	// Resistances math
	has_res := has_string_in_list(c.resistances, d.damage_type)
	if has_string_in_list(c.status_effects, "petrified") {
		has_res = true
	}

	if has_string_in_list(c.immunities, d.damage_type) {
		final_dmg = 0
	} else {
		if has_res {
			final_dmg /= 2
		}
		if has_string_in_list(c.vulnerabilities, d.damage_type) {
			final_dmg *= 2
		}
	}

	new_hp := c.current_hp - final_dmg
	if new_hp < 0 do new_hp = 0

	sql := fmt.tprintf("UPDATE creatures SET current_hp=%d WHERE id=%d", new_hp, d.id)
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
			`{{"success":true,"id":%d,"damage_applied":%d,"current_hp":%d,"max_hp":%d,"attack_hit":%t,"save_success":%t,"save_log":"%s"}}`,
			c.id, final_dmg, new_hp, c.max_hp, attack_hit, save_success, save_log,
		)
		fmt.println()
	} else {
		if len(save_log) > 0 do fmt.println(save_log)
		fmt.printf("Creature HP now: %d/%d (Took %d damage)\n", new_hp, c.max_hp, final_dmg)
	}
	return 0
}

creature_set_location :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-location <creature_id> <location_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-location <creature_id> <location_id>")
		}
		return 1
	}
	creature_id, _ := strconv.parse_int(args[1])
	loc_id, _ := strconv.parse_int(args[2])

	sql := ""
	if loc_id > 0 {
		sql = fmt.tprintf("UPDATE creatures SET location_id=%d WHERE id=%d", loc_id, creature_id)
	} else {
		sql = fmt.tprintf("UPDATE creatures SET location_id=NULL WHERE id=%d", creature_id)
	}

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set creature location"}`)
		} else {
			fmt.eprintln("Failed to set creature location")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Location set for creature %d","id":%d,"location_id":%d}}`, creature_id, creature_id, loc_id)
		fmt.println()
	} else {
		fmt.printf("Set location for creature %d to %d\n", creature_id, loc_id)
	}
	return 0
}
