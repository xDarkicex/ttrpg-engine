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
	cr: int,
	attack_bonus: int,
	damage_dice: string,
	damage_type: string,
	initiative: int,
	passive_perception: int,
	languages: string,
	concentrating_on: string,
	combat: int,
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
		"SELECT n.id, n.name, n.description, n.current_hp, n.max_hp, n.dm_notes, n.campaign_id, n.gold, n.silver, n.copper, n.ac, n.status_effects, n.resistances, n.vulnerabilities, n.immunities, n.story_role, n.daily_role, n.backstory, n.faction_id, n.last_action, n.location_id, COALESCE(l.name, ''), n.str, n.dex, n.con, n.int_, n.wis, n.cha, n.cr, n.attack_bonus, n.damage_dice, n.damage_type, n.initiative, n.passive_perception, n.languages, n.concentrating_on, n.combat FROM npcs n LEFT JOIN locations l ON n.location_id = l.id WHERE n.id=%d",
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
	npc.cr = int(sqlite.column_int(stmt, 28))
	npc.attack_bonus = int(sqlite.column_int(stmt, 29))
	npc.damage_dice = fmt.tprintf("%s", sqlite.column_text(stmt, 30))
	npc.damage_type = fmt.tprintf("%s", sqlite.column_text(stmt, 31))
	npc.initiative = int(sqlite.column_int(stmt, 32))
	npc.passive_perception = int(sqlite.column_int(stmt, 33))
	npc.languages = fmt.tprintf("%s", sqlite.column_text(stmt, 34))
	npc.concentrating_on = fmt.tprintf("%s", sqlite.column_text(stmt, 35))
	npc.combat = int(sqlite.column_int(stmt, 36))

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
		fmt.print("{")
		fmt.printf(
			`"id":%d,"name":"%s","description":"%s","current_hp":%d,"max_hp":%d,"dm_notes":"%s","campaign_id":%d,"gold":%d,"silver":%d,"copper":%d,"ac":%d,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","story_role":"%s","daily_role":"%s","backstory":"%s","faction_id":%d,"last_action":"%s","location_id":%d,"location_name":"%s","stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},"cr":%d,"attack_bonus":%d,"damage_dice":"%s","damage_type":"%s","initiative":%d,"passive_perception":%d,"languages":"%s","concentrating_on":"%s","combat":%d,`,
			npc.id, npc.name, npc.description, npc.current_hp, npc.max_hp, npc.dm_notes, npc.campaign_id,
			npc.gold, npc.silver, npc.copper, npc.ac, npc.status_effects, npc.resistances, npc.vulnerabilities, npc.immunities,
			npc.story_role, npc.daily_role, npc.backstory, npc.faction_id, escape_json_string(npc.last_action), npc.location_id, escape_json_string(npc.location_name),
			npc.str, npc.dex, npc.con, npc.int_, npc.wis, npc.cha,
			npc.cr, npc.attack_bonus, escape_json_string(npc.damage_dice), escape_json_string(npc.damage_type),
			npc.initiative, npc.passive_perception, escape_json_string(npc.languages), escape_json_string(npc.concentrating_on), npc.combat,
		)
		fmt.print(`"abilities":`)
		print_npc_abilities_json(db, npc.id)
		fmt.print(`,"skills":`)
		print_npc_skills_json(db, npc.id)
		fmt.print(`,"inventory":`)
		print_npc_inventory_json(db, npc.id)
		fmt.println("}")
	} else {
		fmt.printf("[%d] %s (%s) HP:%d/%d AC:%d Campaign:%d Faction:%d\n",
			npc.id, npc.name, npc.description, npc.current_hp, npc.max_hp, npc.ac, npc.campaign_id, npc.faction_id,
		)
		fmt.printf("  Location: %s (ID: %d)\n", len(npc.location_name) > 0 ? npc.location_name : "None", npc.location_id)
		fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n", npc.str, npc.dex, npc.con, npc.int_, npc.wis, npc.cha)
		fmt.printf("  Combat: CR:%d | Initiative: +%d | Passive Perception: %d | Attack: +%d (%s %s) | Combat: %s\n",
			npc.cr, npc.initiative, npc.passive_perception, npc.attack_bonus, npc.damage_dice, npc.damage_type,
			npc.combat == 1 ? "YES" : "no",
		)
		fmt.printf("  Languages: %s\n", len(npc.languages) > 0 ? npc.languages : "None")
		if len(npc.concentrating_on) > 0 {
			fmt.printf("  Concentrating On: %s\n", npc.concentrating_on)
		}
		fmt.printf("  Money: GP:%d SP:%d CP:%d\n", npc.gold, npc.silver, npc.copper)
		fmt.printf("  Story Role: %s\n", npc.story_role)
		fmt.printf("  Daily Role: %s\n", npc.daily_role)
		fmt.printf("  Backstory: %s\n", npc.backstory)
		fmt.printf("  Status: %s\n", len(npc.status_effects) > 0 ? npc.status_effects : "None")
		fmt.printf("  Resistances: %s\n", len(npc.resistances) > 0 ? npc.resistances : "None")
		fmt.printf("  Last Action: %s\n", len(npc.last_action) > 0 ? npc.last_action : "None")
		print_npc_abilities_text(db, npc.id)
		print_npc_skills_text(db, npc.id)
		print_npc_inventory_text(db, npc.id)
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

print_npc_abilities_json :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM npc_features nf JOIN features f ON nf.feature_id = f.id WHERE nf.npc_id = %d ORDER BY f.source, f.name",
		npc_id,
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
			fmt.sbprintf(&builder, `{{"id":{},"name":"{}","source":"{}","description":"{}"}}`,
				sqlite.column_int(stmt, 0),
				sqlite.column_text(stmt, 1),
				sqlite.column_text(stmt, 2),
				sqlite.column_text(stmt, 3),
			)
		}
		strings.write_byte(&builder, ']')
		fmt.print(strings.to_string(builder))
	} else {
		fmt.print("[]")
	}
}

print_npc_abilities_text :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM npc_features nf JOIN features f ON nf.feature_id = f.id WHERE nf.npc_id = %d ORDER BY f.source, f.name",
		npc_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		fmt.println("  Abilities:")
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

print_npc_inventory_json :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.npc_id=%d", npc_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
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
		fmt.print(strings.to_string(builder))
	} else {
		fmt.print("[]")
	}
}

print_npc_inventory_text :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.npc_id=%d", npc_id)
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

print_npc_skills_json :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT skill_name, modifier FROM npc_skills WHERE npc_id=%d ORDER BY skill_name", npc_id)
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
		mod := int(sqlite.column_int(stmt, 1))
		fmt.sbprintf(&builder, `{"name":"%s","modifier":%d}`, escape_json_string(name), mod)
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_npc_skills_text :: proc(db: ^lib.Db, npc_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT skill_name, modifier FROM npc_skills WHERE npc_id=%d ORDER BY skill_name", npc_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	has_rows := false
	for sqlite.step(stmt) == .Row {
		if !has_rows {
			fmt.println("  Skills:")
			has_rows = true
		}
		name := column_text_safe(stmt, 0)
		mod := int(sqlite.column_int(stmt, 1))
		fmt.printf("    - %s: %+d\n", name, mod)
	}
}

npc_add_ability :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc add-ability <npc_id> <feature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc add-ability <npc_id> <feature_id>")
		}
		return 1
	}
	npc_id, _ := strconv.parse_int(args[1])
	feature_id, _ := strconv.parse_int(args[2])

	sql := fmt.tprintf("INSERT OR REPLACE INTO npc_features (npc_id,feature_id) VALUES(%d,%d)", npc_id, feature_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add ability to NPC"}`)
		} else {
			fmt.eprintln("Failed to add ability to NPC")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added ability %d to NPC %d","npc_id":%d,"feature_id":%d}}`, feature_id, npc_id, npc_id, feature_id)
		fmt.println()
	} else {
		fmt.printf("Added ability %d to NPC %d\n", feature_id, npc_id)
	}
	return 0
}

npc_remove_ability :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc remove-ability <npc_id> <feature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc remove-ability <npc_id> <feature_id>")
		}
		return 1
	}
	npc_id, _ := strconv.parse_int(args[1])
	feature_id, _ := strconv.parse_int(args[2])

	sql := fmt.tprintf("DELETE FROM npc_features WHERE npc_id=%d AND feature_id=%d", npc_id, feature_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove ability from NPC"}`)
		} else {
			fmt.eprintln("Failed to remove ability from NPC")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Removed ability %d from NPC %d","npc_id":%d,"feature_id":%d}}`, feature_id, npc_id, npc_id, feature_id)
		fmt.println()
	} else {
		fmt.printf("Removed ability %d from NPC %d\n", feature_id, npc_id)
	}
	return 0
}

npc_list_abilities :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc list-abilities <npc_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc list-abilities <npc_id>")
		}
		return 1
	}
	npc_id, _ := strconv.parse_int(args[1])
	
	if db.is_json {
		print_npc_abilities_json(db, npc_id)
		fmt.println()
	} else {
		print_npc_abilities_text(db, npc_id)
	}
	return 0
}

npc_set_cr :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-cr <id> <cr>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-cr <id> <cr>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	cr := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE npcs SET cr=%d WHERE id=%d", cr, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set CR"}`)
		} else {
			fmt.eprintln("Failed to set CR")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"CR set","id":%d,"cr":%d}` + "\n", id, cr)
	} else {
		fmt.printf("CR set to %d for NPC %d\n", cr, id)
	}
	return 0
}

npc_set_attack :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-attack <id> <bonus> <damage_dice> <damage_type>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-attack <id> <bonus> <damage_dice> <damage_type>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	bonus := strconv.atoi(args[2])
	dice := args[3]
	dtype := args[4]

	sql := fmt.tprintf("UPDATE npcs SET attack_bonus=%d, damage_dice='%s', damage_type='%s' WHERE id=%d", bonus, escape_sql(dice), escape_sql(dtype), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set attack"}`)
		} else {
			fmt.eprintln("Failed to set attack")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Attack set","id":%d,"attack_bonus":%d,"damage_dice":"%s","damage_type":"%s"}` + "\n", id, bonus, escape_json_string(dice), escape_json_string(dtype))
	} else {
		fmt.printf("NPC %d attack: +%d, %s %s\n", id, bonus, dice, dtype)
	}
	return 0
}

npc_set_initiative :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-initiative <id> <modifier>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-initiative <id> <modifier>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	mod := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE npcs SET initiative=%d WHERE id=%d", mod, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set initiative"}`)
		} else {
			fmt.eprintln("Failed to set initiative")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Initiative set","id":%d,"initiative":%d}` + "\n", id, mod)
	} else {
		fmt.printf("Initiative set to +%d for NPC %d\n", mod, id)
	}
	return 0
}

npc_set_combat :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-combat <id> <0|1>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-combat <id> <0|1>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	state := strconv.atoi(args[2])
	if state != 0 && state != 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Combat state must be 0 or 1"}`)
		} else {
			fmt.eprintln("Combat state must be 0 or 1")
		}
		return 1
	}

	sql := fmt.tprintf("UPDATE npcs SET combat=%d WHERE id=%d", state, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set combat state"}`)
		} else {
			fmt.eprintln("Failed to set combat state")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Combat state set","id":%d,"combat":%d}` + "\n", id, state)
	} else {
		fmt.printf("Combat %s for NPC %d\n", state == 1 ? "started" : "ended", id)
	}
	return 0
}

npc_set_languages :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-languages <id> <csv>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-languages <id> <csv>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	langs := args[2]

	sql := fmt.tprintf("UPDATE npcs SET languages='%s' WHERE id=%d", escape_sql(langs), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set languages"}`)
		} else {
			fmt.eprintln("Failed to set languages")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Languages set","id":%d,"languages":"%s"}` + "\n", id, escape_json_string(langs))
	} else {
		fmt.printf("Languages set to '%s' for NPC %d\n", langs, id)
	}
	return 0
}

npc_set_passive_perception :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-passive-perception <id> <value>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-passive-perception <id> <value>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	val := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE npcs SET passive_perception=%d WHERE id=%d", val, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set passive perception"}`)
		} else {
			fmt.eprintln("Failed to set passive perception")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Passive perception set","id":%d,"passive_perception":%d}` + "\n", id, val)
	} else {
		fmt.printf("Passive perception set to %d for NPC %d\n", val, id)
	}
	return 0
}

npc_set_concentrating :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-concentrating <id> <spell_name_or_blank>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-concentrating <id> <spell_name_or_blank>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	spell := args[2]

	sql := fmt.tprintf("UPDATE npcs SET concentrating_on='%s' WHERE id=%d", escape_sql(spell), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set concentration"}`)
		} else {
			fmt.eprintln("Failed to set concentration")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Concentration set","id":%d,"concentrating_on":"%s"}` + "\n", id, escape_json_string(spell))
	} else {
		if len(spell) > 0 {
			fmt.printf("NPC %d now concentrating on: %s\n", id, spell)
		} else {
			fmt.printf("NPC %d concentration cleared\n", id)
		}
	}
	return 0
}

npc_set_skill :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc set-skill <npc_id> <skill_name> <modifier>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc set-skill <npc_id> <skill_name> <modifier>")
		}
		return 1
	}
	npc_id, _ := strconv.parse_int(args[1])
	skill_name := args[2]
	modifier, _ := strconv.parse_int(args[3])

	sql := fmt.tprintf("INSERT OR REPLACE INTO npc_skills (npc_id, skill_name, modifier) VALUES(%d, '%s', %d)", npc_id, escape_sql(skill_name), modifier)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set skill"}`)
		} else {
			fmt.eprintln("Failed to set skill")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Skill set","npc_id":%d,"skill_name":"%s","modifier":%d}` + "\n", npc_id, escape_json_string(skill_name), modifier)
	} else {
		fmt.printf("NPC %d %s: %+d\n", npc_id, skill_name, modifier)
	}
	return 0
}

npc_remove_skill :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc remove-skill <npc_id> <skill_name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc remove-skill <npc_id> <skill_name>")
		}
		return 1
	}
	npc_id, _ := strconv.parse_int(args[1])
	skill_name := args[2]

	sql := fmt.tprintf("DELETE FROM npc_skills WHERE npc_id=%d AND skill_name='%s'", npc_id, escape_sql(skill_name))
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove skill"}`)
		} else {
			fmt.eprintln("Failed to remove skill")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Skill removed","npc_id":%d,"skill_name":"%s"}` + "\n", npc_id, escape_json_string(skill_name))
	} else {
		fmt.printf("Removed skill '%s' from NPC %d\n", skill_name, npc_id)
	}
	return 0
}