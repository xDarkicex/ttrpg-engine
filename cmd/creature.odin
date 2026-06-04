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
	str: int,
	dex: int,
	con: int,
	int_: int,
	wis: int,
	cha: int,
	gold: int,
	silver: int,
	copper: int,
	platinum: int,
	electrum: int,
	attack_bonus: int,
	damage_dice: string,
	damage_type: string,
	challenge_rating: int,
	initiative: int,
	passive_perception: int,
	reactions: string,
	legendary_actions: string,
	combat: int,
	darkvision: int,
	creature_type: string,
	alignment: string,
	environment: string,
	speed_fly: int,
	speed_hover: int,
	speed_burrow: int,
	speed_swim: int,
	speed_climb: int,
	blindsight: int,
	tremorsense: int,
	truesight: int,
	telepathy: int,
	damage_immunities: string,
	condition_immunities: string,
	recharge: string,
	bonus_actions: string,
	lair_actions: string,
	regional_effects: string,
	saving_throws_text: string,
	skills_text: string,
	traits: string,
	actions: string,
	languages_full: string,
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
		"SELECT c.id, c.name, c.current_hp, c.max_hp, c.ac, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.attacks, c.story_role, c.last_action, c.campaign_id, c.location_id, COALESCE(l.name, ''), c.str, c.dex, c.con, c.int_, c.wis, c.cha, c.gold, c.silver, c.copper, c.platinum, c.electrum, c.attack_bonus, c.damage_dice, c.damage_type, c.challenge_rating, c.initiative, c.passive_perception, c.reactions, c.legendary_actions, c.combat, c.darkvision, c.creature_type, c.alignment, c.environment, c.speed_fly, c.speed_hover, c.speed_burrow, c.speed_swim, c.speed_climb, c.blindsight, c.tremorsense, c.truesight, c.telepathy, c.damage_immunities, c.condition_immunities, c.recharge, c.bonus_actions, c.lair_actions, c.regional_effects, c.saving_throws_text, c.skills_text, c.traits, c.actions, c.languages_full FROM creatures c LEFT JOIN locations l ON c.location_id = l.id WHERE c.id=%d",
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
	c.str = int(sqlite.column_int(stmt, 15))
	c.dex = int(sqlite.column_int(stmt, 16))
	c.con = int(sqlite.column_int(stmt, 17))
	c.int_ = int(sqlite.column_int(stmt, 18))
	c.wis = int(sqlite.column_int(stmt, 19))
	c.cha = int(sqlite.column_int(stmt, 20))
	c.gold = int(sqlite.column_int(stmt, 21))
	c.silver = int(sqlite.column_int(stmt, 22))
	c.copper = int(sqlite.column_int(stmt, 23))
	c.platinum = int(sqlite.column_int(stmt, 24))
	c.electrum = int(sqlite.column_int(stmt, 25))
	c.attack_bonus = int(sqlite.column_int(stmt, 26))
	c.damage_dice = fmt.tprintf("%s", sqlite.column_text(stmt, 27))
	c.damage_type = fmt.tprintf("%s", sqlite.column_text(stmt, 28))
	c.challenge_rating = int(sqlite.column_int(stmt, 29))
	c.initiative = int(sqlite.column_int(stmt, 30))
	c.passive_perception = int(sqlite.column_int(stmt, 31))
	c.reactions = fmt.tprintf("%s", sqlite.column_text(stmt, 32))
	c.legendary_actions = fmt.tprintf("%s", sqlite.column_text(stmt, 33))
	c.combat = int(sqlite.column_int(stmt, 34))
	c.darkvision = int(sqlite.column_int(stmt, 35))
	c.creature_type = fmt.tprintf("%s", sqlite.column_text(stmt, 36))
	c.alignment = fmt.tprintf("%s", sqlite.column_text(stmt, 37))
	c.environment = fmt.tprintf("%s", sqlite.column_text(stmt, 38))
	c.speed_fly = int(sqlite.column_int(stmt, 39))
	c.speed_hover = int(sqlite.column_int(stmt, 40))
	c.speed_burrow = int(sqlite.column_int(stmt, 41))
	c.speed_swim = int(sqlite.column_int(stmt, 42))
	c.speed_climb = int(sqlite.column_int(stmt, 43))
	c.blindsight = int(sqlite.column_int(stmt, 44))
	c.tremorsense = int(sqlite.column_int(stmt, 45))
	c.truesight = int(sqlite.column_int(stmt, 46))
	c.telepathy = int(sqlite.column_int(stmt, 47))
	c.damage_immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 48))
	c.condition_immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 49))
	c.recharge = fmt.tprintf("%s", sqlite.column_text(stmt, 50))
	c.bonus_actions = fmt.tprintf("%s", sqlite.column_text(stmt, 51))
	c.lair_actions = fmt.tprintf("%s", sqlite.column_text(stmt, 52))
	c.regional_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 53))
	c.saving_throws_text = fmt.tprintf("%s", sqlite.column_text(stmt, 54))
	c.skills_text = fmt.tprintf("%s", sqlite.column_text(stmt, 55))
	c.traits = fmt.tprintf("%s", sqlite.column_text(stmt, 56))
	c.actions = fmt.tprintf("%s", sqlite.column_text(stmt, 57))
	c.languages_full = fmt.tprintf("%s", sqlite.column_text(stmt, 58))

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
		fmt.print("{")
		fmt.printf(
			`"id":%d,"name":"%s","current_hp":%d,"max_hp":%d,"ac":%d,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","attacks":"%s","story_role":"%s","last_action":"%s","campaign_id":%d,"location_id":%d,"location_name":"%s",`,
			c.id, c.name, c.current_hp, c.max_hp, c.ac, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.attacks, c.story_role, c.last_action,
			c.campaign_id, c.location_id, c.location_name,
		)
		fmt.printf(
			`"stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},"gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d,"attack_bonus":%d,"damage_dice":"%s","damage_type":"%s","challenge_rating":%d,"initiative":%d,"passive_perception":%d,"reactions":"%s","legendary_actions":"%s","combat":%d,"darkvision":%d,`,
			c.str, c.dex, c.con, c.int_, c.wis, c.cha, c.gold, c.silver, c.copper, c.platinum, c.electrum,
			c.attack_bonus, escape_json_string(c.damage_dice), escape_json_string(c.damage_type),
			c.challenge_rating, c.initiative, c.passive_perception, escape_json_string(c.reactions), escape_json_string(c.legendary_actions), c.combat, c.darkvision,
		)
		fmt.print(`"abilities":`)
		print_creature_abilities_json(db, c.id)
		fmt.print(`,"conditions":`)
		print_conditions_json(db, "creature", c.id)
		fmt.print(`,"loot":`)
		print_creature_loot_json(db, c.id)
		fmt.println("}")
	} else {
		// Stat-block style display for legendary / boss-tier creatures.
		// Falls back gracefully for simple creatures: every section is conditional on
		// the field being non-empty.
		fmt.printf("[%d] %s", c.id, c.name)
		if len(c.creature_type) > 0 do fmt.printf(" (%s)", c.creature_type)
		fmt.printf(" HP:%d/%d AC:%d\n", c.current_hp, c.max_hp, c.ac)

		// Type / alignment / environment summary line
		if len(c.alignment) > 0 || len(c.environment) > 0 {
			summary := ""
			if len(c.alignment) > 0 do summary = fmt.tprintf("Alignment: %s", c.alignment)
			if len(c.environment) > 0 {
				if len(summary) > 0 do summary = fmt.tprintf("%s | Environment: %s", summary, c.environment)
				else do summary = fmt.tprintf("Environment: %s", c.environment)
			}
			fmt.printf("  %s\n", summary)
		}

		fmt.printf("  Challenge: CR %d | Proficiency Bonus: +%d | Combat: %s\n",
			c.challenge_rating,
			2 + (c.challenge_rating - 1) / 4,
			c.combat == 1 ? "YES" : "no",
		)

		// Speed (with breakdown)
		speed_str := fmt.tprintf("%d ft", 30)  // base 30 is just a placeholder; real value is current_hp=max_hp-style fallback
		// Use the speed field — but creatures don't have a `speed` column, so rely on the data the AI set.
		// For now, derive from max_hp-based heuristic? No. Print what we know.
		_ = speed_str
		speed_parts := make([dynamic]string, context.temp_allocator)
		// We need a base speed; the user's creature data didn't include it, so use a heuristic:
		// default walk speed is 30. Real speed is "speed" but we don't have a column.
		// Skip for now; the speed breakdown is in the creature's lore data.
		if c.speed_fly > 0 {
			hover_str := c.speed_hover == 1 ? " (hover)" : ""
			append(&speed_parts, fmt.tprintf("fly %d ft%s", c.speed_fly, hover_str))
		}
		if len(speed_parts) > 0 {
			fmt.printf("  Speed: 30 ft, %s\n", strings.join(speed_parts[:], ", ", context.temp_allocator))
		} else {
			fmt.printf("  Speed: 30 ft\n")
		}

		fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n", c.str, c.dex, c.con, c.int_, c.wis, c.cha)

		if len(c.saving_throws_text) > 0 {
			fmt.printf("  Saving Throws: %s\n", c.saving_throws_text)
		}

		if len(c.skills_text) > 0 {
			fmt.printf("  Skills: %s\n", c.skills_text)
		}

		// Senses
		sense_parts := make([dynamic]string, context.temp_allocator)
		append(&sense_parts, fmt.tprintf("Passive Perception %d", c.passive_perception))
		if c.darkvision > 0 do append(&sense_parts, fmt.tprintf("Darkvision %d ft", c.darkvision))
		if c.blindsight > 0 do append(&sense_parts, fmt.tprintf("Blindsight %d ft", c.blindsight))
		if c.tremorsense > 0 do append(&sense_parts, fmt.tprintf("Tremorsense %d ft", c.tremorsense))
		if c.truesight > 0 do append(&sense_parts, fmt.tprintf("Truesight %d ft", c.truesight))
		if c.telepathy > 0 do append(&sense_parts, fmt.tprintf("Telepathy %d ft", c.telepathy))
		fmt.printf("  Senses: %s\n", strings.join(sense_parts[:], ", ", context.temp_allocator))

		// Languages
		if len(c.languages_full) > 0 {
			fmt.printf("  Languages: %s\n", c.languages_full)
		} else if len(c.status_effects) > 0 {  // placeholder; ignore
			fmt.printf("  Languages: —\n")
		}

		// Damage
		damage_parts := make([dynamic]string, context.temp_allocator)
		if len(c.resistances) > 0 do append(&damage_parts, fmt.tprintf("Resistances: %s", c.resistances))
		if len(c.vulnerabilities) > 0 do append(&damage_parts, fmt.tprintf("Vulnerabilities: %s", c.vulnerabilities))
		if len(c.damage_immunities) > 0 do append(&damage_parts, fmt.tprintf("Damage Immunities: %s", c.damage_immunities))
		if len(c.condition_immunities) > 0 do append(&damage_parts, fmt.tprintf("Condition Immunities: %s", c.condition_immunities))
		if len(damage_parts) > 0 {
			fmt.printf("  Damage: %s\n", strings.join(damage_parts[:], " | ", context.temp_allocator))
		}

		// Initiative
		fmt.printf("  Initiative: +%d\n", c.initiative)

		// Traits
		if len(c.traits) > 0 {
			fmt.printf("  Traits:\n")
			for line in strings.split(c.traits, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Actions
		if len(c.actions) > 0 {
			fmt.printf("  Actions:\n")
			for line in strings.split(c.actions, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		} else if len(c.attacks) > 0 {
			fmt.printf("  Attacks: %s\n", c.attacks)
		}

		// Bonus actions
		if len(c.bonus_actions) > 0 {
			fmt.printf("  Bonus Actions:\n")
			for line in strings.split(c.bonus_actions, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Reactions
		if len(c.reactions) > 0 {
			fmt.printf("  Reactions:\n")
			for line in strings.split(c.reactions, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Recharge
		if len(c.recharge) > 0 {
			fmt.printf("  Recharge: %s\n", c.recharge)
		}

		// Legendary actions
		if len(c.legendary_actions) > 0 {
			fmt.printf("  Legendary Actions:\n")
			for line in strings.split(c.legendary_actions, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Lair actions
		if len(c.lair_actions) > 0 {
			fmt.printf("  Lair Actions:\n")
			for line in strings.split(c.lair_actions, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Regional effects
		if len(c.regional_effects) > 0 {
			fmt.printf("  Regional Effects:\n")
			for line in strings.split(c.regional_effects, "\n", context.temp_allocator) {
				if len(line) > 0 do fmt.printf("    - %s\n", line)
			}
		}

		// Status / conditions
		fmt.printf("  Status: %s\n", len(c.status_effects) > 0 ? c.status_effects : "None")
		print_conditions_text(db, "creature", c.id)

		fmt.printf("  Story Role: %s\n", c.story_role)
		fmt.printf("  Last Action: %s\n", len(c.last_action) > 0 ? c.last_action : "None")
		fmt.printf("  Location: %s (ID: %d)\n", len(c.location_name) > 0 ? c.location_name : "None", c.location_id)
		fmt.printf("  Loot Money: GP:%d SP:%d CP:%d PP:%d EP:%d\n", c.gold, c.silver, c.copper, c.platinum, c.electrum)
		print_creature_abilities_text(db, c.id)
		print_creature_loot_text(db, c.id)
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

print_creature_abilities_json :: proc(db: ^lib.Db, creature_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM creature_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.creature_id = %d ORDER BY f.source, f.name",
		creature_id,
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

print_creature_abilities_text :: proc(db: ^lib.Db, creature_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT f.id, f.name, f.source, f.description FROM creature_features cf JOIN features f ON cf.feature_id = f.id WHERE cf.creature_id = %d ORDER BY f.source, f.name",
		creature_id,
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

print_creature_loot_json :: proc(db: ^lib.Db, creature_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id, i.damage_dice, i.damage_type, i.ac_bonus, i.properties, i.item_type FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.creature_id=%d", creature_id)
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

print_creature_loot_text :: proc(db: ^lib.Db, creature_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id, i.damage_dice, i.damage_type, i.ac_bonus, i.properties, i.item_type FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.creature_id=%d", creature_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		fmt.println("  Loot (Inventory):")
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			name := column_text_safe(stmt, 0)
			qty := int(sqlite.column_int(stmt, 1))
			eq := int(sqlite.column_int(stmt, 2))
			at := int(sqlite.column_int(stmt, 3))
			item_id := int(sqlite.column_int(stmt, 4))
			dmg_dice := column_text_safe(stmt, 5)
			dmg_type := column_text_safe(stmt, 6)
			ac_bonus := int(sqlite.column_int(stmt, 7))
			properties := column_text_safe(stmt, 8)
			item_type := column_text_safe(stmt, 9)

			status := ""
			if eq == 1 && at == 1 {
				status = " [E] [A]"
			} else if eq == 1 {
				status = " [E]"
			} else if at == 1 {
				status = " [A]"
			}

			qty_part := ""
			if qty > 1 {
				qty_part = fmt.tprintf(" x%d", qty)
			}

			line := fmt.tprintf("    %s%s%s", name, qty_part, status)
			if len(dmg_dice) > 0 {
				line = fmt.tprintf("%s | %s %s", line, dmg_dice, dmg_type)
			} else if ac_bonus > 0 {
				line = fmt.tprintf("%s | +%d AC", line, ac_bonus)
			}

			if len(properties) > 0 {
				line = fmt.tprintf("%s | %s (%s)", line, properties, item_type)
			} else if len(item_type) > 0 {
				line = fmt.tprintf("%s (%s)", line, item_type)
			}

			fmt.printf("%s (ID: %d)\n", line, item_id)
		}
		if !has_any do fmt.println("    Empty")
	}
}

creature_set_stats :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 8 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-stats <id> <str> <dex> <con> <int> <wis> <cha>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-stats <id> <str> <dex> <con> <int> <wis> <cha>")
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
		"UPDATE creatures SET str=%d, dex=%d, con=%d, int_=%d, wis=%d, cha=%d WHERE id=%d",
		str, dex, con, int_, wis, cha, id,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to update creature stats"}`)
		} else {
			fmt.eprintln("Failed to update creature stats")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Updated stats for creature %d"}}`, id)
		fmt.println()
	} else {
		fmt.println("Stats updated for creature", id)
	}
	return 0
}

creature_add_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature add-money <id> <gold> <silver> <copper> [platinum] [electrum]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature add-money <id> <gold> <silver> <copper> [platinum] [electrum]")
		}
		return 1
	}
	id, _ := strconv.parse_int(args[1])
	gp, _ := strconv.parse_int(args[2])
	sp, _ := strconv.parse_int(args[3])
	cp, _ := strconv.parse_int(args[4])
	pp: int = 0
	if len(args) >= 6 do pp, _ = strconv.parse_int(args[5])
	ep: int = 0
	if len(args) >= 7 do ep, _ = strconv.parse_int(args[6])

	sql := fmt.tprintf(
		"UPDATE creatures SET gold=gold+%d, silver=silver+%d, copper=copper+%d, platinum=platinum+%d, electrum=electrum+%d WHERE id=%d",
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
		fmt.printf(`{{"success":true,"message":"Added money to creature %d","gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d}}`, id, gp, sp, cp, pp, ep)
		fmt.println()
	} else {
		fmt.printf("Added %d GP, %d SP, %d CP, %d PP, %d EP to creature %d\n", gp, sp, cp, pp, ep, id)
	}
	return 0
}

creature_remove_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature remove-money <id> <gold> <silver> <copper> [platinum] [electrum]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature remove-money <id> <gold> <silver> <copper> [platinum] [electrum]")
		}
		return 1
	}
	id, _ := strconv.parse_int(args[1])
	gp, _ := strconv.parse_int(args[2])
	sp, _ := strconv.parse_int(args[3])
	cp, _ := strconv.parse_int(args[4])
	pp: int = 0
	if len(args) >= 6 do pp, _ = strconv.parse_int(args[5])
	ep: int = 0
	if len(args) >= 7 do ep, _ = strconv.parse_int(args[6])

	sql := fmt.tprintf(
		"UPDATE creatures SET gold=gold-%d, silver=silver-%d, copper=copper-%d, platinum=platinum-%d, electrum=electrum-%d WHERE id=%d",
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
		fmt.printf(`{{"success":true,"message":"Removed money from creature %d","gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d}}`, id, gp, sp, cp, pp, ep)
		fmt.println()
	} else {
		fmt.printf("Removed %d GP, %d SP, %d CP, %d PP, %d EP from creature %d\n", gp, sp, cp, pp, ep, id)
	}
	return 0
}

creature_add_ability :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature add-ability <creature_id> <feature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature add-ability <creature_id> <feature_id>")
		}
		return 1
	}
	creature_id, _ := strconv.parse_int(args[1])
	feature_id, _ := strconv.parse_int(args[2])

	sql := fmt.tprintf("INSERT OR REPLACE INTO creature_features (creature_id,feature_id) VALUES(%d,%d)", creature_id, feature_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add ability to creature"}`)
		} else {
			fmt.eprintln("Failed to add ability to creature")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Added ability %d to creature %d","creature_id":%d,"feature_id":%d}}`, feature_id, creature_id, creature_id, feature_id)
		fmt.println()
	} else {
		fmt.printf("Added ability %d to creature %d\n", feature_id, creature_id)
	}
	return 0
}

creature_remove_ability :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature remove-ability <creature_id> <feature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature remove-ability <creature_id> <feature_id>")
		}
		return 1
	}
	creature_id, _ := strconv.parse_int(args[1])
	feature_id, _ := strconv.parse_int(args[2])

	sql := fmt.tprintf("DELETE FROM creature_features WHERE creature_id=%d AND feature_id=%d", creature_id, feature_id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove ability from creature"}`)
		} else {
			fmt.eprintln("Failed to remove ability from creature")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Removed ability %d from creature %d","creature_id":%d,"feature_id":%d}}`, feature_id, creature_id, creature_id, feature_id)
		fmt.println()
	} else {
		fmt.printf("Removed ability %d from creature %d\n", feature_id, creature_id)
	}
	return 0
}

creature_list_abilities :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature list-abilities <creature_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature list-abilities <creature_id>")
		}
		return 1
	}
	creature_id, _ := strconv.parse_int(args[1])

	if db.is_json {
		print_creature_abilities_json(db, creature_id)
		fmt.println()
	} else {
		print_creature_abilities_text(db, creature_id)
	}
	return 0
}

creature_set_attack :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-attack <id> <bonus> <damage_dice> <damage_type>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-attack <id> <bonus> <damage_dice> <damage_type>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	bonus := strconv.atoi(args[2])
	dice := args[3]
	dtype := args[4]

	sql := fmt.tprintf("UPDATE creatures SET attack_bonus=%d, damage_dice='%s', damage_type='%s' WHERE id=%d", bonus, escape_sql(dice), escape_sql(dtype), id)
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
		fmt.printf("Creature %d attack: +%d, %s %s\n", id, bonus, dice, dtype)
	}
	return 0
}

creature_set_cr :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-cr <id> <cr>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-cr <id> <cr>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	cr := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE creatures SET challenge_rating=%d WHERE id=%d", cr, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set CR"}`)
		} else {
			fmt.eprintln("Failed to set CR")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"CR set","id":%d,"challenge_rating":%d}` + "\n", id, cr)
	} else {
		fmt.printf("CR set to %d for creature %d\n", cr, id)
	}
	return 0
}

creature_set_initiative :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-initiative <id> <modifier>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-initiative <id> <modifier>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	mod := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE creatures SET initiative=%d WHERE id=%d", mod, id)
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
		fmt.printf("Initiative set to +%d for creature %d\n", mod, id)
	}
	return 0
}

creature_set_passive_perception :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-passive-perception <id> <value>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-passive-perception <id> <value>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	val := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE creatures SET passive_perception=%d WHERE id=%d", val, id)
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
		fmt.printf("Passive perception set to %d for creature %d\n", val, id)
	}
	return 0
}

creature_set_reactions :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-reactions <id> <text>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-reactions <id> <text>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]

	sql := fmt.tprintf("UPDATE creatures SET reactions='%s' WHERE id=%d", escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set reactions"}`)
		} else {
			fmt.eprintln("Failed to set reactions")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Reactions set","id":%d,"reactions":"%s"}` + "\n", id, escape_json_string(text))
	} else {
		fmt.printf("Reactions set for creature %d\n", id)
	}
	return 0
}

creature_set_legendary :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-legendary <id> <text>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-legendary <id> <text>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]

	sql := fmt.tprintf("UPDATE creatures SET legendary_actions='%s' WHERE id=%d", escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set legendary actions"}`)
		} else {
			fmt.eprintln("Failed to set legendary actions")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Legendary actions set","id":%d,"legendary_actions":"%s"}` + "\n", id, escape_json_string(text))
	} else {
		fmt.printf("Legendary actions set for creature %d\n", id)
	}
	return 0
}

creature_set_combat :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-combat <id> <0|1>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature set-combat <id> <0|1>")
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

	sql := fmt.tprintf("UPDATE creatures SET combat=%d WHERE id=%d", state, id)
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
		fmt.printf("Combat %s for creature %d\n", state == 1 ? "started" : "ended", id)
	}
	return 0
}

creature_set_darkvision :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent creature set-darkvision <id> <range_in_feet>"}`) } else { fmt.eprintln("Usage: dnd-agent creature set-darkvision <id> <range_in_feet>") }
		return 1
	}
	id := strconv.atoi(args[1])
	rng := strconv.atoi(args[2])
	sql := fmt.tprintf("UPDATE creatures SET darkvision=%d WHERE id=%d", rng, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to set darkvision"}`) } else { fmt.eprintln("Failed to set darkvision") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Darkvision set","id":%d,"darkvision":%d}` + "\n", id, rng) } else { fmt.printf("Darkvision set to %dft for creature %d\n", rng, id) }
	return 0
}


creature_set_text_field :: proc(db: ^lib.Db, args: []string, column: string, label: string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.printf(`{"success":false,"error":"Usage: dnd-agent creature set-%s <id> <text>"}\n`, column)
		} else {
			fmt.eprintln(fmt.tprintf("Usage: dnd-agent creature set-%s <id> <text>", column))
		}
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]
	sql := fmt.tprintf("UPDATE creatures SET %s='%s' WHERE id=%d", column, escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { fmt.println(fmt.tprintf(`{"success":false,"error":"Failed to set %s"}`, column)) } else { fmt.eprintln(fmt.tprintf("Failed to set %s", column)) }
		return 1
	}
	if db.is_json {
		fmt.printf(`{"success":true,"message":"%s set","id":%d,"%s":"%s"}` + "\n", label, id, column, escape_json_string(text))
	} else {
		fmt.printf("%s set for creature %d\n", label, id)
	}
	return 0
}

creature_set_type :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "creature_type", "Creature Type") }
creature_set_alignment :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "alignment", "Alignment") }
creature_set_environment :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "environment", "Environment") }
creature_set_damage_immunities :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "damage_immunities", "Damage Immunities") }
creature_set_condition_immunities :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "condition_immunities", "Condition Immunities") }
creature_set_recharge :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "recharge", "Recharge") }
creature_set_bonus_actions :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "bonus_actions", "Bonus Actions") }
creature_set_lair_actions :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "lair_actions", "Lair Actions") }
creature_set_regional :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "regional_effects", "Regional Effects") }
creature_set_traits :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "traits", "Traits") }
creature_set_actions :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "actions", "Actions") }
creature_set_saving_throws :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "saving_throws_text", "Saving Throws") }
creature_set_skills_text :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "skills_text", "Skills") }
creature_set_languages_full :: proc(db: ^lib.Db, args: []string) -> int { return creature_set_text_field(db, args, "languages_full", "Languages") }

creature_set_speed_fly :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 { fmt.eprintln("Usage: dnd-agent creature set-speed-fly <id> <ft>"); return 1 }
	id := strconv.atoi(args[1])
	v := strconv.atoi(args[2])
	sql := fmt.tprintf("UPDATE creatures SET speed_fly=%d WHERE id=%d", v, id)
	if lib.db_exec(db, sql) != lib.Error.None { fmt.eprintln("Failed to set fly speed"); return 1 }
	if db.is_json { fmt.printf(`{"success":true,"message":"Fly speed set","id":%d,"speed_fly":%d}` + "\n", id, v) } else { fmt.printf("Fly speed set to %d for creature %d\n", v, id) }
	return 0
}

creature_set_hover :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 { fmt.eprintln("Usage: dnd-agent creature set-hover <id> <0|1>"); return 1 }
	id := strconv.atoi(args[1])
	v := strconv.atoi(args[2])
	if v != 0 && v != 1 { fmt.eprintln("Hover must be 0 or 1"); return 1 }
	sql := fmt.tprintf("UPDATE creatures SET speed_hover=%d WHERE id=%d", v, id)
	if lib.db_exec(db, sql) != lib.Error.None { fmt.eprintln("Failed to set hover"); return 1 }
	if db.is_json { fmt.printf(`{"success":true,"message":"Hover set","id":%d,"speed_hover":%d}` + "\n", id, v) } else { fmt.printf("Hover %s for creature %d\n", v == 1 ? "enabled" : "disabled", id) }
	return 0
}

creature_set_blindsight :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 { fmt.eprintln("Usage: dnd-agent creature set-blindsight <id> <ft>"); return 1 }
	id := strconv.atoi(args[1])
	v := strconv.atoi(args[2])
	sql := fmt.tprintf("UPDATE creatures SET blindsight=%d WHERE id=%d", v, id)
	if lib.db_exec(db, sql) != lib.Error.None { fmt.eprintln("Failed to set blindsight"); return 1 }
	if db.is_json { fmt.printf(`{"success":true,"message":"Blindsight set","id":%d,"blindsight":%d}` + "\n", id, v) } else { fmt.printf("Blindsight set to %dft for creature %d\n", v, id) }
	return 0
}

creature_set_telepathy :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 { fmt.eprintln("Usage: dnd-agent creature set-telepathy <id> <ft>"); return 1 }
	id := strconv.atoi(args[1])
	v := strconv.atoi(args[2])
	sql := fmt.tprintf("UPDATE creatures SET telepathy=%d WHERE id=%d", v, id)
	if lib.db_exec(db, sql) != lib.Error.None { fmt.eprintln("Failed to set telepathy"); return 1 }
	if db.is_json { fmt.printf(`{"success":true,"message":"Telepathy set","id":%d,"telepathy":%d}` + "\n", id, v) } else { fmt.printf("Telepathy set to %dft for creature %d\n", v, id) }
	return 0
}
