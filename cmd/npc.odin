package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

NpcStats :: struct {
	id: int,
	name: string,
	description: string,
	current_hp: int,
	max_hp: int,
	dm_notes: string,
	campaign_id: int,
	gold: int,
	silver: int,
	copper: int,
	ac: int,
	status_effects: string,
	resistances: string,
	vulnerabilities: string,
	immunities: string,
	story_role: string,
	daily_role: string,
	backstory: string,
	faction_id: int,
	last_action: string,
	location_id: int,
	location_name: string,
	str: int,
	dex: int,
	con: int,
	int_: int,
	wis: int,
	cha: int,
}

npc_create :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc create <name> <desc> <max_hp> <camp_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc create <name> <desc> <max_hp> <camp_id>")
		}
		return 1
	}
	name := args[1]
	desc := args[2]
	max_hp := strconv.atoi(args[3])
	camp_id := strconv.atoi(args[4])

	sql := fmt.tprintf(
		"INSERT INTO npcs (name,description,max_hp,current_hp,campaign_id) VALUES('%s','%s',%d,%d,%d)",
		escape_sql(name), escape_sql(desc), max_hp, max_hp, camp_id,
	)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to create NPC"}`)
		} else {
			fmt.eprintln("Failed to create NPC")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Created NPC: %s"}}\n`, name)
	} else {
		fmt.println("Created NPC:", name)
	}
	return 0
}

npc_list :: proc(db: ^lib.Db) -> int {
	stmt: ^sqlite.Statement
	sql_str := "SELECT id,name,current_hp,max_hp,ac,campaign_id FROM npcs ORDER BY name"
	sql_c := cstring(raw_data(sql_str))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql_str)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to list NPCs"}`)
		} else {
			fmt.eprintln("Failed to list NPCs")
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

fetch_npc_stats :: proc(db: ^lib.Db, id: int) -> (npc: NpcStats, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT n.id, n.name, n.description, n.current_hp, n.max_hp, n.dm_notes, n.campaign_id, n.gold, n.silver, n.copper, n.ac, n.status_effects, n.resistances, n.vulnerabilities, n.immunities, n.story_role, n.daily_role, n.backstory, n.faction_id, n.last_action, n.location_id, COALESCE(l.name, ''), n.str, n.dex, n.con, n.int_, n.wis, n.cha FROM npcs n LEFT JOIN locations l ON n.location_id = l.id WHERE n.id=%d",
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

	npc.id = int(sqlite.column_int(stmt, 0))
	npc.name = fmt.tprintf("%s", sqlite.column_text(stmt, 1))
	npc.description = fmt.tprintf("%s", sqlite.column_text(stmt, 2))
	npc.current_hp = int(sqlite.column_int(stmt, 3))
	npc.max_hp = int(sqlite.column_int(stmt, 4))
	npc.dm_notes = fmt.tprintf("%s", sqlite.column_text(stmt, 5))
	npc.campaign_id = int(sqlite.column_int(stmt, 6))
	npc.gold = int(sqlite.column_int(stmt, 7))
	npc.silver = int(sqlite.column_int(stmt, 8))
	npc.copper = int(sqlite.column_int(stmt, 9))
	npc.ac = int(sqlite.column_int(stmt, 10))
	npc.status_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 11))
	npc.resistances = fmt.tprintf("%s", sqlite.column_text(stmt, 12))
	npc.vulnerabilities = fmt.tprintf("%s", sqlite.column_text(stmt, 13))
	npc.immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 14))
	npc.story_role = fmt.tprintf("%s", sqlite.column_text(stmt, 15))
	npc.daily_role = fmt.tprintf("%s", sqlite.column_text(stmt, 16))
	npc.backstory = fmt.tprintf("%s", sqlite.column_text(stmt, 17))
	npc.faction_id = int(sqlite.column_int(stmt, 18))
	npc.last_action = fmt.tprintf("%s", sqlite.column_text(stmt, 19))
	npc.location_id = int(sqlite.column_int(stmt, 20))
	npc.location_name = fmt.tprintf("%s", sqlite.column_text(stmt, 21))
	npc.str = int(sqlite.column_int(stmt, 22))
	npc.dex = int(sqlite.column_int(stmt, 23))
	npc.con = int(sqlite.column_int(stmt, 24))
	npc.int_ = int(sqlite.column_int(stmt, 25))
	npc.wis = int(sqlite.column_int(stmt, 26))
	npc.cha = int(sqlite.column_int(stmt, 27))

	return npc, true
}

npc_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc get <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc get <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])

	npc, found := fetch_npc_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"NPC not found"}`)
		} else {
			fmt.eprintln("NPC not found")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(
			`{{"id":%d,"name":"%s","description":"%s","current_hp":%d,"max_hp":%d,"dm_notes":"%s","campaign_id":%d,"gold":%d,"silver":%d,"copper":%d,"ac":%d,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","story_role":"%s","daily_role":"%s","backstory":"%s","faction_id":%d,"last_action":"%s","location_id":%d,"location_name":"%s","stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}}}}\n`,
			npc.id, npc.name, npc.description, npc.current_hp, npc.max_hp, npc.dm_notes, npc.campaign_id,
			npc.gold, npc.silver, npc.copper, npc.ac, npc.status_effects, npc.resistances, npc.vulnerabilities, npc.immunities,
			npc.story_role, npc.daily_role, npc.backstory, npc.faction_id, npc.last_action, npc.location_id, npc.location_name,
			npc.str, npc.dex, npc.con, npc.int_, npc.wis, npc.cha,
		)
	} else {
		fmt.printf("[%d] %s (%s) HP:%d/%d AC:%d Campaign:%d Faction:%d\n",
			npc.id, npc.name, npc.description, npc.current_hp, npc.max_hp, npc.ac, npc.campaign_id, npc.faction_id,
		)
		fmt.printf("  Location: %s (ID: %d)\n", len(npc.location_name) > 0 ? npc.location_name : "None", npc.location_id)
		fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n", npc.str, npc.dex, npc.con, npc.int_, npc.wis, npc.cha)
		fmt.printf("  Money: GP:%d SP:%d CP:%d\n", npc.gold, npc.silver, npc.copper)
		fmt.printf("  Story Role: %s\n", npc.story_role)
		fmt.printf("  Daily Role: %s\n", npc.daily_role)
		fmt.printf("  Backstory: %s\n", npc.backstory)
		fmt.printf("  Status: %s\n", len(npc.status_effects) > 0 ? npc.status_effects : "None")
		fmt.printf("  Resistances: %s\n", len(npc.resistances) > 0 ? npc.resistances : "None")
		fmt.printf("  Last Action: %s\n", len(npc.last_action) > 0 ? npc.last_action : "None")
	}
	return 0
}

npc_delete :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc delete <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc delete <id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	sql := fmt.tprintf("DELETE FROM npcs WHERE id=%d", id)

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to delete NPC"}`)
		} else {
			fmt.eprintln("Failed to delete NPC")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Deleted NPC %d"}}\n`, id)
	} else {
		fmt.println("Deleted NPC", id)
	}
	return 0
}

npc_heal :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc heal <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc heal <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amt := strconv.atoi(args[2])

	npc, found := fetch_npc_stats(db, id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"NPC not found"}`)
		} else {
			fmt.eprintln("NPC not found")
		}
		return 1
	}

	new_hp := npc.current_hp + amt
	if new_hp > npc.max_hp do new_hp = npc.max_hp

	sql2 := fmt.tprintf("UPDATE npcs SET current_hp=%d WHERE id=%d", new_hp, id)
	if lib.db_exec(db, sql2) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update HP"}`)
		} else {
			fmt.eprintln("Failed to update HP")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"id":%d,"current_hp":%d,"max_hp":%d}}\n`, id, new_hp, npc.max_hp)
	} else {
		fmt.printf("NPC HP now: %d/%d\n", new_hp, npc.max_hp)
	}
	return 0
}

npc_damage :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]")
		}
		return 1
	}

	d := parse_damage_args(args)
	npc, found := fetch_npc_stats(db, d.id)
	if !found {
		if db.is_json {
			fmt.println(`{"success":false,"error":"NPC not found"}`)
		} else {
			fmt.eprintln("NPC not found")
		}
		return 1
	}

	attack_hit := true
	if is_numeric(d.attack_or_save) {
		attack_roll := strconv.atoi(d.attack_or_save)
		if attack_roll < npc.ac {
			if db.is_json {
				fmt.printf(`{{"success":true,"id":%d,"attack_hit":false,"damage_applied":0,"current_hp":%d,"max_hp":%d}}\n`, npc.id, npc.current_hp, npc.max_hp)
			} else {
				fmt.printf("Attack roll %d missed NPC AC %d. 0 damage applied.\n", attack_roll, npc.ac)
			}
			return 0
		}
	}

	final_dmg := d.amount
	is_save := len(d.attack_or_save) > 0 && !is_numeric(d.attack_or_save)
	save_success := false
	save_log := ""

	if is_save {
		if has_string_in_list(npc.status_effects, "unconscious") && (d.attack_or_save == "str" || d.attack_or_save == "dex") {
			save_log = "Unconscious: Auto-failed Dex/Str saving throw."
		} else {
			if d.d20_roll >= d.save_dc {
				save_success = true
				save_log = fmt.tprintf("Saving Throw (%s): d20(%d) vs DC %d. Succeeded: Took half damage.", d.attack_or_save, d.d20_roll, d.save_dc)
				final_dmg /= 2
			} else {
				save_log = fmt.tprintf("Saving Throw (%s): d20(%d) vs DC %d. Failed: Took full damage.", d.attack_or_save, d.d20_roll, d.save_dc)
			}
		}
	}

	has_res := has_string_in_list(npc.resistances, d.damage_type)
	if has_string_in_list(npc.status_effects, "petrified") {
		has_res = true
	}

	if has_string_in_list(npc.immunities, d.damage_type) {
		final_dmg = 0
	} else {
		if has_res {
			final_dmg /= 2
		}
		if has_string_in_list(npc.vulnerabilities, d.damage_type) {
			final_dmg *= 2
		}
	}

	new_hp := npc.current_hp - final_dmg
	if new_hp < 0 do new_hp = 0

	sql := fmt.tprintf("UPDATE npcs SET current_hp=%d WHERE id=%d", new_hp, d.id)
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
			npc.id, final_dmg, new_hp, npc.max_hp, attack_hit, save_success, save_log,
		)
	} else {
		if len(save_log) > 0 do fmt.println(save_log)
		fmt.printf("NPC HP now: %d/%d (Took %d damage)\n", new_hp, npc.max_hp, final_dmg)
	}
	return 0
}

npc_set_details :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 6 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-details <id> <ac> <story_role> <daily_role> <backstory>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-details <id> <ac> <story_role> <daily_role> <backstory>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	ac := strconv.atoi(args[2])
	story := args[3]
	daily := args[4]
	backstory := args[5]

	sql := fmt.tprintf("UPDATE npcs SET ac=%d, story_role='%s', daily_role='%s', backstory='%s' WHERE id=%d", ac, escape_sql(story), escape_sql(daily), escape_sql(backstory), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update NPC details"}`)
		} else {
			fmt.eprintln("Failed to update NPC details")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Details updated for NPC %d"}}\n`, id)
	} else {
		fmt.println("Details updated for NPC", id)
	}
	return 0
}

npc_set_combat_meta :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-combat-meta <id> <resistances> <vulnerabilities> <immunities>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-combat-meta <id> <resistances> <vulnerabilities> <immunities>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	res := args[2]
	vuln := args[3]
	imm := args[4]

	sql := fmt.tprintf("UPDATE npcs SET resistances='%s', vulnerabilities='%s', immunities='%s' WHERE id=%d", escape_sql(res), escape_sql(vuln), escape_sql(imm), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update combat meta"}`)
		} else {
			fmt.eprintln("Failed to update combat meta")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Combat metadata updated for NPC %d"}}\n`, id)
	} else {
		fmt.println("Combat metadata updated for NPC", id)
	}
	return 0
}

npc_set_status :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-status <id> <status_effects>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-status <id> <status_effects>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	status := args[2]

	sql := fmt.tprintf("UPDATE npcs SET status_effects='%s' WHERE id=%d", escape_sql(status), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update status"}`)
		} else {
			fmt.eprintln("Failed to update status")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Status effects updated for NPC %d"}}\n`, id)
	} else {
		fmt.println("Status effects updated for NPC", id)
	}
	return 0
}

npc_add_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc add-money <id> <gold> <silver> <copper>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc add-money <id> <gold> <silver> <copper>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])

	sql := fmt.tprintf("UPDATE npcs SET gold=gold+%d, silver=silver+%d, copper=copper+%d WHERE id=%d", gp, sp, cp, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add money"}`)
		} else {
			fmt.eprintln("Failed to add money")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added money to NPC %d","gold":%d,"silver":%d,"copper":%d}}\n`, id, gp, sp, cp)
	} else {
		fmt.printf("Added %d GP, %d SP, %d CP to NPC %d\n", gp, sp, cp, id)
	}
	return 0
}

npc_remove_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc remove-money <id> <gold> <silver> <copper>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc remove-money <id> <gold> <silver> <copper>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])

	sql := fmt.tprintf("UPDATE npcs SET gold=gold-%d, silver=silver-%d, copper=copper-%d WHERE id=%d", gp, sp, cp, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove money"}`)
		} else {
			fmt.eprintln("Failed to remove money")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Removed money from NPC %d","gold":%d,"silver":%d,"copper":%d}}\n`, id, gp, sp, cp)
	} else {
		fmt.printf("Removed %d GP, %d SP, %d CP from NPC %d\n", gp, sp, cp, id)
	}
	return 0
}

npc_set_action :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-action <id> <action>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-action <id> <action>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	action := args[2]

	sql := fmt.tprintf("UPDATE npcs SET last_action='%s' WHERE id=%d", escape_sql(action), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update action"}`)
		} else {
			fmt.eprintln("Failed to update action")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated last action for NPC %d"}}\n`, id)
	} else {
		fmt.println("Last action updated for NPC", id)
	}
	return 0
}

npc_set_relationship :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-relationship <npc_id_1> <npc_id_2> <friendship_level> [notes]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-relationship <npc_id_1> <npc_id_2> <friendship_level> [notes]")
		}
		return 1
	}
	n1 := strconv.atoi(args[1])
	n2 := strconv.atoi(args[2])
	friend := strconv.atoi(args[3])
	notes := len(args) >= 5 ? args[4] : ""

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO npc_relationships (npc_id_1,npc_id_2,friendship_level,notes) VALUES(%d,%d,%d,'%s')",
		n1, n2, friend, escape_sql(notes),
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set relationship"}`)
		} else {
			fmt.eprintln("Failed to set relationship")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Relationship updated between NPC %d and %d"}}\n`, n1, n2)
	} else {
		fmt.printf("Relationship updated between NPC %d and %d (friendship: %d)\n", n1, n2, friend)
	}
	return 0
}

npc_list_relationships :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc list-relationships <npc_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc list-relationships <npc_id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT npc_id_2, friendship_level, notes FROM npc_relationships WHERE npc_id_1=%d ORDER BY friendship_level DESC", id)
	sql_c := cstring(raw_data(sql))

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to get relationships"}`)
		} else {
			fmt.eprintln("Failed to get relationships")
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
			fmt.sbprintf(&builder, `{{"target_npc_id":{},"friendship_level":{},"notes":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		fmt.printf("Relationships for NPC %d:\n", id)
		for sqlite.step(stmt) == .Row {
			fmt.printf("  With NPC %d: friendship:%d (%s)\n",
				sqlite.column_int(stmt, 0),
				sqlite.column_int(stmt, 1),
				sqlite.column_text(stmt, 2),
			)
		}
	}
	return 0
}

npc_set_location :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-location <npc_id> <location_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-location <npc_id> <location_id>")
		}
		return 1
	}
	npc_id := strconv.atoi(args[1])
	loc_id := strconv.atoi(args[2])

	sql := ""
	if loc_id > 0 {
		sql = fmt.tprintf("UPDATE npcs SET location_id=%d WHERE id=%d", loc_id, npc_id)
	} else {
		sql = fmt.tprintf("UPDATE npcs SET location_id=NULL WHERE id=%d", npc_id)
	}

	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set NPC location"}`)
		} else {
			fmt.eprintln("Failed to set NPC location")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Location set for NPC %d","id":%d,"location_id":%d}}\n`, npc_id, npc_id, loc_id)
	} else {
		fmt.printf("Set location for NPC %d to %d\n", npc_id, loc_id)
	}
	return 0
}

npc_set_stats :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 8 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-stats <id> <str> <dex> <con> <int> <wis> <cha>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-stats <id> <str> <dex> <con> <int> <wis> <cha>")
		}
		return 1
	}
	id, _ := strconv.parse_int(args[1])
	str, _ := strconv.parse_int(args[2])
	dex, _ := strconv.parse_int(args[3])
	con, _ := strconv.parse_int(args[4])
	int_, _ := strconv.parse_int(args[5])
	wis, _ := strconv.parse_int(args[6])
	cha, _ := strconv.parse_int(args[7])

	sql := fmt.tprintf(
		"UPDATE npcs SET str=%d, dex=%d, con=%d, int_=%d, wis=%d, cha=%d WHERE id=%d",
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
		fmt.printf(`{{"success":true,"message":"Updated stats for NPC %d"}}\n`, id)
	} else {
		fmt.println("Stats updated for NPC", id)
	}
	return 0
}