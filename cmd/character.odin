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
	max_hit_dice: int,
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
	owner: string,
	chapter_id: string,
	location_id: int,
	location_name: string,
	proficiency_bonus: int,
	spell_save_dc: int,
	spell_attack_bonus: int,
	initiative: int,
	passive_perception: int,
	languages: string,
	concentrating_on: string,
	combat: int,
	darkvision: int,
	bond: string,
	flaw: string,
	ideal: string,
	personality_traits: string,
	appearance: string,
	short_rests_available: int,
	long_rests_available: int,
	gender: string,
	age: int,
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

MULTICLASS_SPELL_SLOTS := [21][10]int{
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 2, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 3, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 4, 2, 0, 0, 0, 0, 0, 0, 0},
	{0, 4, 3, 0, 0, 0, 0, 0, 0, 0},
	{0, 4, 3, 2, 0, 0, 0, 0, 0, 0},
	{0, 4, 3, 3, 0, 0, 0, 0, 0, 0},
	{0, 4, 3, 3, 1, 0, 0, 0, 0, 0},
	{0, 4, 3, 3, 2, 0, 0, 0, 0, 0},
	{0, 4, 3, 3, 3, 1, 0, 0, 0, 0},
	{0, 4, 3, 3, 3, 2, 0, 0, 0, 0},
	{0, 4, 3, 3, 3, 2, 1, 0, 0, 0},
	{0, 4, 3, 3, 3, 2, 1, 0, 0, 0},
	{0, 4, 3, 3, 3, 2, 1, 1, 0, 0},
	{0, 4, 3, 3, 3, 2, 1, 1, 0, 0},
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 0},
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 0},
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 1},
	{0, 4, 3, 3, 3, 3, 1, 1, 1, 1},
	{0, 4, 3, 3, 3, 3, 2, 1, 1, 1},
	{0, 4, 3, 3, 3, 3, 2, 2, 1, 1},
}

// Per-class single-class spell slot table (PHB 5e).
// Index [class_level][slot_level]. Used to validate prepared spells of a specific class.
// Per multiclass PHB rules, you prepare spells per-class as if single-classed; combined caster
// level only governs how many slots you have total, not what each class can prepare.
// 5e Warlock is special (pact magic) and not handled here — Warlock spells should use the
// Warlock-specific slot count from invocations, not this table.
SINGLE_CLASS_SPELL_SLOTS := [22][10]int{
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 2, 0, 0, 0, 0, 0, 0, 0, 0},  // 1
	{0, 3, 0, 0, 0, 0, 0, 0, 0, 0},  // 2
	{0, 4, 2, 0, 0, 0, 0, 0, 0, 0},  // 3
	{0, 4, 3, 0, 0, 0, 0, 0, 0, 0},  // 4
	{0, 4, 3, 2, 0, 0, 0, 0, 0, 0},  // 5
	{0, 4, 3, 3, 0, 0, 0, 0, 0, 0},  // 6
	{0, 4, 3, 3, 1, 0, 0, 0, 0, 0},  // 7
	{0, 4, 3, 3, 2, 0, 0, 0, 0, 0},  // 8
	{0, 4, 3, 3, 3, 1, 0, 0, 0, 0},  // 9
	{0, 4, 3, 3, 3, 2, 0, 0, 0, 0},  // 10
	{0, 4, 3, 3, 3, 2, 1, 0, 0, 0},  // 11
	{0, 4, 3, 3, 3, 2, 1, 0, 0, 0},  // 12
	{0, 4, 3, 3, 3, 2, 1, 1, 0, 0},  // 13
	{0, 4, 3, 3, 3, 2, 1, 1, 0, 0},  // 14
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 0},  // 15
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 0},  // 16
	{0, 4, 3, 3, 3, 2, 1, 1, 1, 1},  // 17
	{0, 4, 3, 3, 3, 3, 1, 1, 1, 1},  // 18
	{0, 4, 3, 3, 3, 3, 2, 1, 1, 1},  // 19
	{0, 4, 3, 3, 3, 3, 2, 2, 1, 1},  // 20
	{0, 4, 3, 3, 3, 3, 2, 2, 2, 1},  // 21 (epic)
}

// Returns the max slot level (1-9) a character has for a specific class at their current level in that class.
// Returns 0 if the class has no spell slots or the level is out of range.
get_class_max_slot_level :: proc(db: ^lib.Db, char_id: int, class_name: string) -> int {
	cls := strings.to_lower(class_name, context.temp_allocator)
	// Only full/half casters use the standard slot table; non-casters get 0.
	can_cast := cls == "bard" || cls == "cleric" || cls == "druid" || cls == "sorcerer" || cls == "wizard" ||
	            cls == "paladin" || cls == "ranger" || cls == "artificer"
	if !can_cast do return 0

	lvl := get_class_level(db, char_id, class_name)
	if lvl <= 0 || lvl >= len(SINGLE_CLASS_SPELL_SLOTS) do return 0

	max_lvl := 0
	for slot_lvl := 9; slot_lvl >= 1; slot_lvl -= 1 {
		if SINGLE_CLASS_SPELL_SLOTS[lvl][slot_lvl] > 0 {
			return slot_lvl
		}
	}
	return 0
}

get_skill_modifier :: proc(db: ^lib.Db, char: CharacterStats, skill_name: string) -> int {
	ability_score := get_skill_ability(char, skill_name)
	ability_mod := get_ability_modifier(ability_score)
	
	prof_level := 0
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT proficiency_level FROM character_skills WHERE character_id=%d AND skill_name='%s'", char.id, escape_sql(skill_name))
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			prof_level = int(sqlite.column_int(stmt, 0))
		}
	}
	
	prof_bonus := get_prof_bonus(char.level)
	return ability_mod + prof_level * prof_bonus
}

ArmorCategory :: enum {
	Light,
	Medium,
	Heavy,
}

get_armor_category :: proc(name: string, properties: string, ac_bonus: int) -> ArmorCategory {
	name_lower := strings.to_lower(name, context.temp_allocator)
	props_lower := strings.to_lower(properties, context.temp_allocator)
	
	if strings.contains(name_lower, "plate") || 
	   strings.contains(name_lower, "splint") || 
	   strings.contains(name_lower, "ring mail") || 
	   strings.contains(name_lower, "chain mail") ||
	   strings.contains(props_lower, "heavy") {
		return .Heavy
	}
	
	if strings.contains(name_lower, "breastplate") || 
	   strings.contains(name_lower, "chain shirt") || 
	   strings.contains(name_lower, "scale mail") || 
	   strings.contains(name_lower, "hide") ||
	   strings.contains(props_lower, "medium") {
		return .Medium
	}
	
	if strings.contains(name_lower, "leather") || 
	   strings.contains(name_lower, "padded") || 
	   strings.contains(name_lower, "studded") ||
	   strings.contains(props_lower, "light") {
		return .Light
	}
	
	if ac_bonus >= 6 do return .Heavy
	if ac_bonus >= 3 do return .Medium
	return .Light
}

check_has_condition_or_effect :: proc(db: ^lib.Db, char_id: int, name: string) -> bool {
	name_lower := strings.to_lower(name, context.temp_allocator)
	
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT COUNT(*) FROM conditions WHERE target_type='character' AND target_id=%d AND (LOWER(name)='%s' OR LOWER(source)='%s')", char_id, name_lower, name_lower)
	sql_c := cstring(raw_data(sql))
	has := false
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			if sqlite.column_int(stmt, 0) > 0 do has = true
		}
	}
	if has do return true

	char_sql := fmt.tprintf("SELECT status_effects FROM characters WHERE id=%d", char_id)
	char_sql_c := cstring(raw_data(char_sql))
	if sqlite.prepare(db.ptr, char_sql_c, i32(len(char_sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			effects := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			effects_lower := strings.to_lower(effects, context.temp_allocator)
			if strings.contains(effects_lower, name_lower) do has = true
		}
	}
	return has
}

calculate_character_ac :: proc(db: ^lib.Db, char: CharacterStats) -> int {
	dex_mod := get_ability_modifier(char.dex)
	wis_mod := get_ability_modifier(char.wis)
	con_mod := get_ability_modifier(char.con)
	
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, i.item_type, i.ac_bonus, i.properties FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d AND inv.equipped=1", char.id)
	sql_c := cstring(raw_data(sql))
	
	has_armor := false
	armor_name := ""
	armor_bonus := 0
	armor_props := ""
	
	has_shield := false
	shield_bonus := 0
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		for sqlite.step(stmt) == .Row {
			name := column_text_safe(stmt, 0)
			item_type := column_text_safe(stmt, 1)
			ac_bonus := int(sqlite.column_int(stmt, 2))
			properties := column_text_safe(stmt, 3)
			
			if item_type == "armor" {
				has_armor = true
				armor_name = name
				armor_bonus = ac_bonus
				armor_props = properties
			} else if item_type == "shield" {
				has_shield = true
				shield_bonus = ac_bonus
			}
		}
	}
	
	ac := 10 + dex_mod
	
	if !has_armor {
		is_monk := strings.contains(strings.to_lower(char.class, context.temp_allocator), "monk")
		is_barb := strings.contains(strings.to_lower(char.class, context.temp_allocator), "barbarian")
		
		unarmored_base := 10 + dex_mod
		
		if is_monk && !has_shield {
			monk_ac := 10 + dex_mod + wis_mod
			if monk_ac > unarmored_base do unarmored_base = monk_ac
		}
		
		if is_barb {
			barb_ac := 10 + dex_mod + con_mod
			if barb_ac > unarmored_base do unarmored_base = barb_ac
		}
		
		if check_has_condition_or_effect(db, char.id, "Mage Armor") {
			mage_ac := 13 + dex_mod
			if mage_ac > unarmored_base do unarmored_base = mage_ac
		}
		
		ac = unarmored_base
	} else {
		cat := get_armor_category(armor_name, armor_props, armor_bonus)
		switch cat {
		case .Light:
			ac = 10 + armor_bonus + dex_mod
		case .Medium:
			ac = 10 + armor_bonus + (dex_mod > 2 ? 2 : dex_mod)
		case .Heavy:
			ac = 10 + armor_bonus
		}
	}
	
	if has_shield {
		ac += shield_bonus
	}
	
	if check_has_condition_or_effect(db, char.id, "Shield") {
		ac += 5
	}
	
	return ac
}

get_class_level :: proc(db: ^lib.Db, char_id: int, target_class: string) -> int {
	stmt: ^sqlite.Statement
	// Class names are case-insensitive in user data; use LOWER() so "Cleric" / "cleric" / "CLERIC" all match.
	sql := fmt.tprintf("SELECT level FROM character_classes WHERE character_id=%d AND LOWER(class_name)=LOWER('%s')", char_id, escape_sql(target_class))
	sql_c := cstring(raw_data(sql))
	
	level := 0
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			level = int(sqlite.column_int(stmt, 0))
		}
	}
	return level
}

get_ki_points_max :: proc(db: ^lib.Db, char_id: int, db_max: int) -> int {
	monk_lvl := get_class_level(db, char_id, "Monk")
	return monk_lvl > 0 ? monk_lvl : db_max
}

get_bardic_inspiration_max :: proc(db: ^lib.Db, char: CharacterStats, db_max: int) -> int {
	bard_lvl := get_class_level(db, char.id, "Bard")
	if bard_lvl <= 0 do return db_max
	cha_mod := get_ability_modifier(char.cha)
	return cha_mod > 1 ? cha_mod : 1
}

get_rage_max :: proc(db: ^lib.Db, char_id: int, db_max: int) -> int {
	barb_lvl := get_class_level(db, char_id, "Barbarian")
	if barb_lvl <= 0 do return db_max
	if barb_lvl >= 17 do return 6
	if barb_lvl >= 12 do return 5
	if barb_lvl >= 6  do return 4
	if barb_lvl >= 3  do return 3
	return 2
}

get_channel_divinity_max :: proc(db: ^lib.Db, char_id: int, db_max: int) -> int {
	cleric_lvl := get_class_level(db, char_id, "Cleric")
	if cleric_lvl < 2 do return db_max
	if cleric_lvl >= 18 do return 4
	if cleric_lvl >= 6 do return 3
	return 2
}

get_arcane_recovery_max :: proc(db: ^lib.Db, char_id: int, db_max: int) -> int {
	wizard_lvl := get_class_level(db, char_id, "Wizard")
	return wizard_lvl > 0 ? 1 : db_max
}

get_character_resource_max :: proc(db: ^lib.Db, char: CharacterStats, resource_name: string, db_max: int) -> int {
	name_lower := strings.to_lower(resource_name, context.temp_allocator)
	switch name_lower {
	case "ki points", "ki", "discipline points":
		return get_ki_points_max(db, char.id, db_max)
	case "bardic inspiration":
		return get_bardic_inspiration_max(db, char, db_max)
	case "rage":
		return get_rage_max(db, char.id, db_max)
	case "channel divinity":
		return get_channel_divinity_max(db, char.id, db_max)
	case "arcane recovery":
		return get_arcane_recovery_max(db, char.id, db_max)
	}
	return db_max
}

sync_bard_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	bard_lvl := get_class_level(db, char.id, "Bard")
	if bard_lvl <= 0 do return
	cha_mod := get_ability_modifier(char.cha)
	max_val := cha_mod > 1 ? cha_mod : 1
	reset_cond := bard_lvl >= 5 ? "short_rest" : "long_rest"
	insert_sql := fmt.tprintf("INSERT OR IGNORE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, 'Bardic Inspiration', %d, %d, '%s')", char.id, max_val, max_val, reset_cond)
	lib.db_exec(db, insert_sql)
}

sync_monk_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	monk_lvl := get_class_level(db, char.id, "Monk")
	if monk_lvl <= 0 do return
	insert_sql := fmt.tprintf("INSERT OR IGNORE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, 'Ki Points', %d, %d, 'short_rest')", char.id, monk_lvl, monk_lvl)
	lib.db_exec(db, insert_sql)
}

sync_barb_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	barb_lvl := get_class_level(db, char.id, "Barbarian")
	if barb_lvl <= 0 do return
	max_rage := get_rage_max(db, char.id, 2)
	insert_sql := fmt.tprintf("INSERT OR IGNORE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, 'Rage', %d, %d, 'long_rest')", char.id, max_rage, max_rage)
	lib.db_exec(db, insert_sql)
}

sync_wizard_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	wizard_lvl := get_class_level(db, char.id, "Wizard")
	if wizard_lvl <= 0 do return
	insert_sql := fmt.tprintf("INSERT OR IGNORE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, 'Arcane Recovery', 1, 1, 'long_rest')", char.id)
	lib.db_exec(db, insert_sql)
}

sync_cleric_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	cleric_lvl := get_class_level(db, char.id, "Cleric")
	if cleric_lvl < 2 do return
	max_val := get_channel_divinity_max(db, char.id, 2)
	insert_sql := fmt.tprintf("INSERT OR IGNORE INTO character_resources (character_id, resource_name, max_amount, current_amount, reset_condition) VALUES (%d, 'Channel Divinity', %d, %d, 'short_rest')", char.id, max_val, max_val)
	lib.db_exec(db, insert_sql)
}

sync_missing_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	sync_bard_resources(db, char)
	sync_monk_resources(db, char)
	sync_barb_resources(db, char)
	sync_wizard_resources(db, char)
	sync_cleric_resources(db, char)
}

sync_character_resources :: proc(db: ^lib.Db, char: CharacterStats) {
	sync_missing_resources(db, char)

	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT resource_name, max_amount, current_amount FROM character_resources WHERE character_id=%d", char.id)
	sql_c := cstring(raw_data(sql))
	
	ResourceEntry :: struct {
		name: string,
		max: int,
		curr: int,
	}
	entries := make([dynamic]ResourceEntry, context.temp_allocator)
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		for sqlite.step(stmt) == .Row {
			name := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			max_val := int(sqlite.column_int(stmt, 1))
			curr_val := int(sqlite.column_int(stmt, 2))
			append(&entries, ResourceEntry{name, max_val, curr_val})
		}
	}
	
	for entry in entries {
		computed_max := get_character_resource_max(db, char, entry.name, entry.max)
		if computed_max != entry.max {
			new_curr := entry.curr
			if new_curr > computed_max do new_curr = computed_max
			update_sql := fmt.tprintf("UPDATE character_resources SET max_amount=%d, current_amount=%d WHERE character_id=%d AND resource_name='%s'", computed_max, new_curr, char.id, escape_sql(entry.name))
			lib.db_exec(db, update_sql)
		}
	}
}

get_multiclass_caster_level :: proc(db: ^lib.Db, char_id: int) -> int {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name, level FROM character_classes WHERE character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0
	}
	defer sqlite.finalize(stmt)
	
	caster_level_sum := 0
	for sqlite.step(stmt) == .Row {
		cls := sqlite.column_text(stmt, 0)
		lvl := int(sqlite.column_int(stmt, 1))
		cls_lower := strings.to_lower(fmt.tprintf("%s", cls), context.temp_allocator)
		
		if cls_lower == "bard" || cls_lower == "cleric" || cls_lower == "druid" || cls_lower == "sorcerer" || cls_lower == "wizard" {
			caster_level_sum += lvl
		} else if cls_lower == "paladin" || cls_lower == "ranger" || cls_lower == "artificer" {
			caster_level_sum += (lvl + 1) / 2
		} else if cls_lower == "fighter" || cls_lower == "rogue" {
		}
	}
	
	return caster_level_sum
}

get_class_hit_die :: proc(cls_lower: string) -> (hit_die: int, fixed_hp: int) {
	switch cls_lower {
	case "wizard", "sorcerer":
		return 6, 4
	case "bard", "cleric", "druid", "monk", "rogue", "warlock":
		return 8, 5
	case "fighter", "paladin", "ranger":
		return 10, 6
	case "barbarian":
		return 12, 7
	}
	return 8, 5
}

calculate_default_max_hp :: proc(db: ^lib.Db, char: CharacterStats) -> int {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name, level FROM character_classes WHERE character_id=%d ORDER BY id ASC", char.id)
	sql_c := cstring(raw_data(sql))
	
	con_mod := get_ability_modifier(char.con)
	total_hp := 0
	is_first := true
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		for sqlite.step(stmt) == .Row {
			cls := sqlite.column_text(stmt, 0)
			lvl := int(sqlite.column_int(stmt, 1))
			cls_lower := strings.to_lower(fmt.tprintf("%s", cls), context.temp_allocator)
			
			hit_die, fixed_hp := get_class_hit_die(cls_lower)
			
			if is_first {
				total_hp += hit_die + con_mod
				if lvl > 1 do total_hp += (lvl - 1) * (fixed_hp + con_mod)
				is_first = false
			} else {
				total_hp += lvl * (fixed_hp + con_mod)
			}
		}
	}
	
	if total_hp <= 0 do total_hp = 10 + con_mod
	return total_hp
}

get_class_spell_stat :: proc(char: CharacterStats, cls_lower: string) -> (stat: int, is_caster: bool) {
	switch cls_lower {
	case "bard", "sorcerer", "warlock", "paladin":
		return char.cha, true
	case "wizard", "artificer":
		return char.int_, true
	case "cleric", "druid", "ranger":
		return char.wis, true
	}
	return 10, false
}

get_string_magic_bonus :: proc(s: string) -> int {
	if strings.contains(s, "+3") do return 3
	if strings.contains(s, "+2") do return 2
	if strings.contains(s, "+1") do return 1
	return 0
}

get_item_magic_bonus :: proc(name: string, props: string, desc: string) -> int {
	b1 := get_string_magic_bonus(name)
	if b1 > 0 do return b1
	b2 := get_string_magic_bonus(props)
	if b2 > 0 do return b2
	b3 := get_string_magic_bonus(desc)
	if b3 > 0 do return b3
	return 0
}

is_spellcasting_focus :: proc(name: string, desc: string) -> bool {
	name_l := strings.to_lower(name, context.temp_allocator)
	desc_l := strings.to_lower(desc, context.temp_allocator)
	
	switch {
	case strings.contains(name_l, "wand"), strings.contains(name_l, "rod"), strings.contains(name_l, "staff"):
		return true
	case strings.contains(name_l, "amulet"), strings.contains(name_l, "focus"), strings.contains(name_l, "grimoire"):
		return true
	case strings.contains(desc_l, "spell attack"), strings.contains(desc_l, "spell save"):
		return true
	}
	return false
}

get_highest_spellcasting_ability :: proc(db: ^lib.Db, char: CharacterStats) -> (ability_score: int, has_spellcasting: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name, level FROM character_classes WHERE character_id=%d", char.id)
	sql_c := cstring(raw_data(sql))
	
	ability_score = 10
	has_spellcasting = false
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		highest_lvl := 0
		highest_mod := -99
		for sqlite.step(stmt) == .Row {
			cls := sqlite.column_text(stmt, 0)
			lvl := int(sqlite.column_int(stmt, 1))
			cls_lower := strings.to_lower(fmt.tprintf("%s", cls), context.temp_allocator)
			class_ability_score, class_has_spellcasting := get_class_spell_stat(char, cls_lower)
			if class_has_spellcasting {
				has_spellcasting = true
				mod := get_ability_modifier(class_ability_score)
				if lvl > highest_lvl || (lvl == highest_lvl && mod > highest_mod) {
					highest_lvl = lvl
					highest_mod = mod
					ability_score = class_ability_score
				}
			}
		}
	}
	return
}

calculate_class_spellcasting_stats :: proc(db: ^lib.Db, char: CharacterStats, class_name: string) -> (dc: int, attack: int, found: bool) {
	cls_lower := strings.to_lower(class_name, context.temp_allocator)
	ability_score, is_caster := get_class_spell_stat(char, cls_lower)
	if !is_caster do return 0, 0, false
	
	ability_mod := get_ability_modifier(ability_score)
	prof := get_prof_bonus(char.level)
	
	dc = 8 + prof + ability_mod
	attack = prof + ability_mod
	
	stmt_items: ^sqlite.Statement
	sql_items := fmt.tprintf("SELECT i.name, i.properties, i.description FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d AND inv.equipped=1", char.id)
	sql_items_c := cstring(raw_data(sql_items))
	if sqlite.prepare(db.ptr, sql_items_c, i32(len(sql_items)), &stmt_items, nil) == .Ok {
		defer sqlite.finalize(stmt_items)
		for sqlite.step(stmt_items) == .Row {
			name := column_text_safe(stmt_items, 0)
			props := column_text_safe(stmt_items, 1)
			desc := column_text_safe(stmt_items, 2)
			
			bonus := get_item_magic_bonus(name, props, desc)
			if bonus > 0 {
				if is_spellcasting_focus(name, desc) {
					dc += bonus
					attack += bonus
				}
			}
		}
	}
	
	return dc, attack, true
}

print_spellcasting_stats_text :: proc(db: ^lib.Db, char: CharacterStats) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name FROM character_classes WHERE character_id=%d", char.id)
	sql_c := cstring(raw_data(sql))
	
	CasterClass :: struct {
		name: string,
		dc: int,
		atk: int,
	}
	casters := make([dynamic]CasterClass, context.temp_allocator)
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		for sqlite.step(stmt) == .Row {
			cls_name := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			dc, atk, ok := calculate_class_spellcasting_stats(db, char, cls_name)
			if ok {
				append(&casters, CasterClass{cls_name, dc, atk})
			}
		}
	}
	
	if len(casters) == 0 {
		fmt.printf("Spell DC: %d | Spell Atk: %+d", char.spell_save_dc, char.spell_attack_bonus)
	} else if len(casters) == 1 {
		fmt.printf("Spell DC: %d | Spell Atk: %+d (%s)", casters[0].dc, casters[0].atk, casters[0].name)
	} else {
		for caster, idx in casters {
			if idx > 0 do fmt.print(" | ")
			fmt.printf("%s: DC %d, Atk %+d", caster.name, caster.dc, caster.atk)
		}
	}
}

print_spellcasting_stats_json :: proc(db: ^lib.Db, char: CharacterStats) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT class_name FROM character_classes WHERE character_id=%d", char.id)
	sql_c := cstring(raw_data(sql))
	
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "[")
	first := true
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		for sqlite.step(stmt) == .Row {
			cls_name := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			dc, atk, ok := calculate_class_spellcasting_stats(db, char, cls_name)
			if ok {
				if !first do strings.write_string(&builder, ",")
				first = false
				fmt.sbprintf(&builder, `{{"class":"%s","spell_save_dc":%d,"spell_attack_bonus":%d}}`, escape_json_string(cls_name), dc, atk)
			}
		}
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

calculate_spellcasting_stats :: proc(db: ^lib.Db, char: CharacterStats) -> (dc: int, attack: int) {
	ability_score, has_spellcasting := get_highest_spellcasting_ability(db, char)
	
	if !has_spellcasting {
		ability_score = char.cha
		if char.wis > ability_score do ability_score = char.wis
		if char.int_ > ability_score do ability_score = char.int_
	}
	
	ability_mod := get_ability_modifier(ability_score)
	prof := get_prof_bonus(char.level)
	
	dc = 8 + prof + ability_mod
	attack = prof + ability_mod
	
	stmt_items: ^sqlite.Statement
	sql_items := fmt.tprintf("SELECT i.name, i.properties, i.description FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d AND inv.equipped=1", char.id)
	sql_items_c := cstring(raw_data(sql_items))
	if sqlite.prepare(db.ptr, sql_items_c, i32(len(sql_items)), &stmt_items, nil) == .Ok {
		defer sqlite.finalize(stmt_items)
		for sqlite.step(stmt_items) == .Row {
			name := column_text_safe(stmt_items, 0)
			props := column_text_safe(stmt_items, 1)
			desc := column_text_safe(stmt_items, 2)
			
			bonus := get_item_magic_bonus(name, props, desc)
			if bonus > 0 {
				if is_spellcasting_focus(name, desc) {
					dc += bonus
					attack += bonus
				}
			}
		}
	}
	return dc, attack
}

fetch_character_stats :: proc(db: ^lib.Db, id: int) -> (char: CharacterStats, found: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT c.id, c.name, c.current_hp, c.max_hp, c.temp_hp, c.death_saves_success, c.death_saves_failure, c.exhaustion, c.hit_dice_expended, c.max_hit_dice, c.str, c.dex, c.con, c.int_, c.wis, c.cha, c.save_prof_str, c.save_prof_dex, c.save_prof_con, c.save_prof_int, c.save_prof_wis, c.save_prof_cha, c.ac, c.race, c.speed, c.status_effects, c.resistances, c.vulnerabilities, c.immunities, c.gold, c.silver, c.copper, c.platinum, c.electrum, c.inspiration, c.alignment, c.size, c.xp, c.faction_id, c.campaign_id, c.last_action, c.party, c.backstory, c.owner, c.chapter_id, c.location_id, COALESCE(f.name, ''), COALESCE(l.name, ''), c.proficiency_bonus, c.spell_save_dc, c.spell_attack_bonus, c.initiative, c.passive_perception, c.languages, c.concentrating_on, c.combat, c.darkvision, c.bond, c.flaw, c.ideal, c.personality_traits, c.appearance, c.short_rests_available, c.long_rests_available, COALESCE(c.gender, ''), COALESCE(c.age, 0) FROM characters c LEFT JOIN factions f ON c.faction_id = f.id LEFT JOIN locations l ON c.location_id = l.id WHERE c.id=%d",
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
	char.max_hit_dice = int(sqlite.column_int(stmt, 9))
	char.str = int(sqlite.column_int(stmt, 10))
	char.dex = int(sqlite.column_int(stmt, 11))
	char.con = int(sqlite.column_int(stmt, 12))
	char.int_ = int(sqlite.column_int(stmt, 13))
	char.wis = int(sqlite.column_int(stmt, 14))
	char.cha = int(sqlite.column_int(stmt, 15))
	char.save_prof_str = int(sqlite.column_int(stmt, 16))
	char.save_prof_dex = int(sqlite.column_int(stmt, 17))
	char.save_prof_con = int(sqlite.column_int(stmt, 18))
	char.save_prof_int = int(sqlite.column_int(stmt, 19))
	char.save_prof_wis = int(sqlite.column_int(stmt, 20))
	char.save_prof_cha = int(sqlite.column_int(stmt, 21))
	char.ac = int(sqlite.column_int(stmt, 22))
	char.race = fmt.tprintf("%s", sqlite.column_text(stmt, 23))
	char.speed = int(sqlite.column_int(stmt, 24))
	char.status_effects = fmt.tprintf("%s", sqlite.column_text(stmt, 25))
	char.resistances = fmt.tprintf("%s", sqlite.column_text(stmt, 26))
	char.vulnerabilities = fmt.tprintf("%s", sqlite.column_text(stmt, 27))
	char.immunities = fmt.tprintf("%s", sqlite.column_text(stmt, 28))
	char.gold = int(sqlite.column_int(stmt, 29))
	char.silver = int(sqlite.column_int(stmt, 30))
	char.copper = int(sqlite.column_int(stmt, 31))
	char.platinum = int(sqlite.column_int(stmt, 32))
	char.electrum = int(sqlite.column_int(stmt, 33))
	char.inspiration = int(sqlite.column_int(stmt, 34))
	char.alignment = fmt.tprintf("%s", sqlite.column_text(stmt, 35))
	char.size = fmt.tprintf("%s", sqlite.column_text(stmt, 36))
	char.xp = int(sqlite.column_int(stmt, 37))
	char.faction_id = int(sqlite.column_int(stmt, 38))
	char.campaign_id = int(sqlite.column_int(stmt, 39))
	char.last_action = fmt.tprintf("%s", sqlite.column_text(stmt, 40))
	char.party = fmt.tprintf("%s", sqlite.column_text(stmt, 41))
	char.backstory = fmt.tprintf("%s", sqlite.column_text(stmt, 42))
	char.owner = fmt.tprintf("%s", sqlite.column_text(stmt, 43))
	char.chapter_id = fmt.tprintf("%s", sqlite.column_text(stmt, 44))
	char.location_id = int(sqlite.column_int(stmt, 45))
	char.faction_name = fmt.tprintf("%s", sqlite.column_text(stmt, 46))
	char.location_name = fmt.tprintf("%s", sqlite.column_text(stmt, 47))
	char.proficiency_bonus = int(sqlite.column_int(stmt, 48))
	char.spell_save_dc = int(sqlite.column_int(stmt, 49))
	char.spell_attack_bonus = int(sqlite.column_int(stmt, 50))
	char.initiative = int(sqlite.column_int(stmt, 51))
	char.passive_perception = int(sqlite.column_int(stmt, 52))
	char.languages = fmt.tprintf("%s", sqlite.column_text(stmt, 53))
	char.concentrating_on = fmt.tprintf("%s", sqlite.column_text(stmt, 54))
	char.combat = int(sqlite.column_int(stmt, 55))
	char.darkvision = int(sqlite.column_int(stmt, 56))
	char.bond = fmt.tprintf("%s", sqlite.column_text(stmt, 57))
	char.flaw = fmt.tprintf("%s", sqlite.column_text(stmt, 58))
	char.ideal = fmt.tprintf("%s", sqlite.column_text(stmt, 59))
	char.personality_traits = fmt.tprintf("%s", sqlite.column_text(stmt, 60))
	char.appearance = fmt.tprintf("%s", sqlite.column_text(stmt, 61))
	char.short_rests_available = int(sqlite.column_int(stmt, 62))
	char.long_rests_available = int(sqlite.column_int(stmt, 63))
	char.gender = fmt.tprintf("%s", sqlite.column_text(stmt, 64))
	char.age = int(sqlite.column_int(stmt, 65))

	char.class, char.level = fetch_character_class_summary(db, id)

	if char.max_hp <= 1 {
		char.max_hp = calculate_default_max_hp(db, char)
		if char.current_hp <= 1 {
			char.current_hp = char.max_hp
		}
	}

	char.proficiency_bonus = get_prof_bonus(char.level)
	// 2024 Alert feat: adds Proficiency Bonus to initiative (not flat +5)
	alert_bonus := check_has_feature(db, char.id, "Alert") ? char.proficiency_bonus : 0
	char.initiative = get_ability_modifier(char.dex) + alert_bonus
	char.passive_perception = 10 + get_skill_modifier(db, char, "perception")
	char.ac = calculate_character_ac(db, char)
	char.spell_save_dc, char.spell_attack_bonus = calculate_spellcasting_stats(db, char)
	sync_character_resources(db, char)

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

get_item_status_string :: proc(eq: int, at: int) -> string {
	if eq == 1 && at == 1 do return " [E] [A]"
	if eq == 1 do return " [E]"
	if at == 1 do return " [A]"
	return ""
}

get_item_stats_and_type_string :: proc(line: string, dmg_dice: string, dmg_type: string, ac_bonus: int, properties: string, item_type: string) -> string {
	result := line
	if len(dmg_dice) > 0 {
		result = fmt.tprintf("%s | %s %s", result, dmg_dice, dmg_type)
	} else if ac_bonus > 0 {
		result = fmt.tprintf("%s | +%d AC", result, ac_bonus)
	}

	if len(properties) > 0 {
		result = fmt.tprintf("%s | %s (%s)", result, properties, item_type)
	} else if len(item_type) > 0 {
		result = fmt.tprintf("%s (%s)", result, item_type)
	}
	return result
}

get_character_strength :: proc(db: ^lib.Db, char_id: int) -> int {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT str FROM characters WHERE id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	str := 10
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			str = int(sqlite.column_int(stmt, 0))
		}
	}
	return str
}

calculate_inventory_weight :: proc(db: ^lib.Db, char_id: int) -> f64 {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT SUM(i.weight * inv.quantity) FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	weight := 0.0
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		if sqlite.step(stmt) == .Row {
			weight = f64(sqlite.column_double(stmt, 0))
		}
	}
	return weight
}

print_character_inventory_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id, i.weight FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	
	total_weight := calculate_inventory_weight(db, char_id)
	capacity := get_character_strength(db, char_id) * 15

	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		builder := strings.builder_make(context.temp_allocator)
		strings.write_string(&builder, `{"items":[`)
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			name := fmt.tprintf("%s", sqlite.column_text(stmt, 0))
			qty := int(sqlite.column_int(stmt, 1))
			eq := int(sqlite.column_int(stmt, 2))
			at := int(sqlite.column_int(stmt, 3))
			item_id := int(sqlite.column_int(stmt, 4))
			weight := f64(sqlite.column_double(stmt, 5))
			fmt.sbprintf(&builder, `{{"name":"{}","quantity":{},"equipped":{},"attuned":{},"item_id":{},"weight":{:.2f}}}`,
				escape_json_string(name), qty, eq, at, item_id, weight,
			)
		}
		fmt.sbprintf(&builder, `],"total_weight":{:.2f},"carrying_capacity":{}}`, total_weight, capacity)
		fmt.print(strings.to_string(builder))
	} else {
		fmt.printf(`{{"items":[],"total_weight":0.00,"carrying_capacity":%d}}`, capacity)
	}
}

print_character_inventory_text :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT i.name, inv.quantity, inv.equipped, inv.attuned, i.id, i.damage_dice, i.damage_type, i.ac_bonus, i.properties, i.item_type, i.weight FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
		defer sqlite.finalize(stmt)
		fmt.println("  Inventory:")
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
			weight := f64(sqlite.column_double(stmt, 10))

			status := get_item_status_string(eq, at)
			qty_part := qty > 1 ? fmt.tprintf(" x%d", qty) : ""
			line := fmt.tprintf("    %s%s%s", name, qty_part, status)
			line = get_item_stats_and_type_string(line, dmg_dice, dmg_type, ac_bonus, properties, item_type)
			
			if weight > 0 {
				line = fmt.tprintf("%s | %.1f lbs", line, weight * f64(qty))
			}

			fmt.printf("%s (ID: %d)\n", line, item_id)
		}
		if !has_any do fmt.println("    Empty")
	}
	
	total_weight := calculate_inventory_weight(db, char_id)
	capacity := get_character_strength(db, char_id) * 15
	fmt.printf("  Total Weight: %.1f lbs / Carrying Capacity: %d lbs\n", total_weight, capacity)
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

print_character_save_proficiencies_json :: proc(char: CharacterStats) {
	fmt.printf(
		`{{"str":%s,"dex":%s,"con":%s,"int":%s,"wis":%s,"cha":%s}}`,
		char.save_prof_str == 1 ? "true" : "false",
		char.save_prof_dex == 1 ? "true" : "false",
		char.save_prof_con == 1 ? "true" : "false",
		char.save_prof_int == 1 ? "true" : "false",
		char.save_prof_wis == 1 ? "true" : "false",
		char.save_prof_cha == 1 ? "true" : "false",
	)
}

print_character_save_bonuses_json :: proc(char: CharacterStats) {
	str_save := get_ability_modifier(char.str) + (char.save_prof_str == 1 ? char.proficiency_bonus : 0)
	dex_save := get_ability_modifier(char.dex) + (char.save_prof_dex == 1 ? char.proficiency_bonus : 0)
	con_save := get_ability_modifier(char.con) + (char.save_prof_con == 1 ? char.proficiency_bonus : 0)
	int_save := get_ability_modifier(char.int_) + (char.save_prof_int == 1 ? char.proficiency_bonus : 0)
	wis_save := get_ability_modifier(char.wis) + (char.save_prof_wis == 1 ? char.proficiency_bonus : 0)
	cha_save := get_ability_modifier(char.cha) + (char.save_prof_cha == 1 ? char.proficiency_bonus : 0)
	fmt.printf(
		`{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}}`,
		str_save, dex_save, con_save, int_save, wis_save, cha_save,
	)
}

character_get_json :: proc(db: ^lib.Db, char: CharacterStats) {
	fmt.print("{")
	fmt.printf(
		`"ruleset":"5.5e / 2024","id":%d,"name":"%s","class":"%s","level":%d,"current_hp":%d,"max_hp":%d,"temp_hp":%d,"death_saves_success":%d,"death_saves_failure":%d,"exhaustion":%d,"hit_dice_expended":%d,"max_hit_dice":%d,"ac":%d,"race":"%s","speed":%d,`,
		char.id, char.name, char.class, char.level, char.current_hp, char.max_hp, char.temp_hp, char.death_saves_success, char.death_saves_failure, char.exhaustion, char.hit_dice_expended, char.max_hit_dice, char.ac, char.race, char.speed,
	)
	fmt.printf(
		`"stats":{{"str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d}},`,
		char.str, char.dex, char.con, char.int_, char.wis, char.cha,
	)
	fmt.print(`"save_proficiencies":`)
	print_character_save_proficiencies_json(char)
	fmt.print(`,"save_bonuses":`)
	print_character_save_bonuses_json(char)
	
	total_weight := calculate_inventory_weight(db, char.id)
	capacity := get_character_strength(db, char.id) * 15
	fmt.printf(`,"total_weight":%.2f,"carrying_capacity":%d`, total_weight, capacity)

	fmt.printf(
		`,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","gold":%d,"silver":%d,"copper":%d,"platinum":%d,"electrum":%d,"inspiration":%d,"alignment":"%s","size":"%s","xp":%d,"faction_id":%d,"faction_name":"%s","campaign_id":%d,`,
		char.status_effects, char.resistances, char.vulnerabilities, char.immunities,
		char.gold, char.silver, char.copper, char.platinum, char.electrum, char.inspiration, char.alignment, char.size, char.xp, char.faction_id, escape_json_string(char.faction_name), char.campaign_id,
	)
	fmt.printf(
		`"last_action":"%s","party":"%s","backstory":"%s","owner":"%s","chapter_id":"%s","location_id":%d,"location_name":"%s","proficiency_bonus":%d,"spell_save_dc":%d,"spell_attack_bonus":%d,"initiative":%d,"passive_perception":%d,"languages":"%s","concentrating_on":"%s","combat":%d,"darkvision":%d,"bond":"%s","flaw":"%s","ideal":"%s","personality_traits":"%s","appearance":"%s","short_rests_available":%d,"long_rests_available":%d,`,
		escape_json_string(char.last_action), escape_json_string(char.party), escape_json_string(char.backstory),
		escape_json_string(char.owner), escape_json_string(char.chapter_id), char.location_id, escape_json_string(char.location_name),
		char.proficiency_bonus, char.spell_save_dc, char.spell_attack_bonus, char.initiative, char.passive_perception, escape_json_string(char.languages), escape_json_string(char.concentrating_on), char.combat, char.darkvision, escape_json_string(char.bond), escape_json_string(char.flaw), escape_json_string(char.ideal), escape_json_string(char.personality_traits), escape_json_string(char.appearance),
		char.short_rests_available, char.long_rests_available,
	)
	fmt.print(`"spellcasting_stats":`)
	print_spellcasting_stats_json(db, char)
	fmt.print(`,"skills":`)
	print_character_skills_json(db, char)
	fmt.print(`,"conditions":`)
	print_conditions_json(db, "character", char.id)
	fmt.print(`,"weapon_profs":`)
	print_character_profs_json(db, char.id, "weapon")
	fmt.print(`,"armor_profs":`)
	print_character_profs_json(db, char.id, "armor")
	fmt.print(`,"tool_profs":`)
	print_character_profs_json(db, char.id, "tool")
	fmt.print(`,"spell_slots":`)
	print_character_spell_slots_json(db, char)
	fmt.print(`,"spells":`)
	print_character_spells_json(db, char.id)
	fmt.print(`,"companions":`)
	print_character_companions_json(db, char.id)
	fmt.print(`,"resources":`)
	print_character_resources_json(db, char.id)
	fmt.print(`,"inventory":`)
	print_character_inventory_json(db, char.id)
	fmt.print(`,"abilities":`)
	print_character_abilities_json(db, char.id)
	fmt.println("}")
}

print_save_proficiencies_text :: proc(char: CharacterStats) {
	prof_builder := strings.builder_make(context.temp_allocator)
	first_prof := true
	if char.save_prof_str == 1 { strings.write_string(&prof_builder, "STR"); first_prof = false }
	if char.save_prof_dex == 1 { if !first_prof do strings.write_string(&prof_builder, ", "); strings.write_string(&prof_builder, "DEX"); first_prof = false }
	if char.save_prof_con == 1 { if !first_prof do strings.write_string(&prof_builder, ", "); strings.write_string(&prof_builder, "CON"); first_prof = false }
	if char.save_prof_int == 1 { if !first_prof do strings.write_string(&prof_builder, ", "); strings.write_string(&prof_builder, "INT"); first_prof = false }
	if char.save_prof_wis == 1 { if !first_prof do strings.write_string(&prof_builder, ", "); strings.write_string(&prof_builder, "WIS"); first_prof = false }
	if char.save_prof_cha == 1 { if !first_prof do strings.write_string(&prof_builder, ", "); strings.write_string(&prof_builder, "CHA"); first_prof = false }
	prof_str := strings.to_string(prof_builder)
	if len(prof_str) == 0 do prof_str = "None"
	fmt.printf("  Save Proficiencies: %s\n", prof_str)
}

print_personality_details_text :: proc(char: CharacterStats) {
	if len(char.personality_traits) > 0 {
		fmt.printf("  Personality Traits: %s\n", char.personality_traits)
	}
	if len(char.ideal) > 0 {
		fmt.printf("  Ideal: %s\n", char.ideal)
	}
	if len(char.bond) > 0 {
		fmt.printf("  Bond: %s\n", char.bond)
	}
	if len(char.flaw) > 0 {
		fmt.printf("  Flaw: %s\n", char.flaw)
	}
	if len(char.appearance) > 0 {
		fmt.printf("  Appearance: %s\n", char.appearance)
	}
}

print_identity_line :: proc(char: CharacterStats) {
	faction_str := "None"
	if char.faction_id > 0 {
		if len(char.faction_name) > 0 {
			faction_str = fmt.tprintf("%s (ID: %d)", char.faction_name, char.faction_id)
		} else {
			faction_str = fmt.tprintf("ID: %d", char.faction_id)
		}
	}
	fmt.println("Ruleset: 5.5e / 2024")
	fmt.printf("[%d] %s (%s) Lvl%d HP:%d/%d (Temp: %d) AC:%d Race:%s Speed:%d XP:%d Faction: %s\n",
		char.id, char.name, char.class, char.level, char.current_hp, char.max_hp, char.temp_hp, char.ac, char.race, char.speed,
		char.xp, faction_str,
	)
	gender_str := len(char.gender) > 0 ? char.gender : "Unknown"
	age_str := char.age > 0 ? fmt.tprintf("%d", char.age) : "Unknown"
	fmt.printf("  Identity: Owner: %s | Gender: %s | Age: %s | Alignment: %s | Size: %s | Inspiration: %d | Exhaustion: %d | Spent Hit Dice: %d | Rests: %d Short / %d Long\n",
		char.owner, gender_str, age_str, char.alignment, char.size, char.inspiration, char.exhaustion, char.hit_dice_expended,
		char.short_rests_available, char.long_rests_available,
	)
}

print_campaign_details_line :: proc(char: CharacterStats) {
	loc_str := "None"
	if char.location_id > 0 {
		if len(char.location_name) > 0 {
			loc_str = fmt.tprintf("%s (ID: %d)", char.location_name, char.location_id)
		} else {
			loc_str = fmt.tprintf("ID: %d", char.location_id)
		}
	}
	chapter_str := len(char.chapter_id) > 0 ? char.chapter_id : "None"
	campaign_str := char.campaign_id > 0 ? fmt.tprintf("%d", char.campaign_id) : "None"
	fmt.printf("  Campaign Details: Campaign: %s | Chapter: %s | Location: %s\n",
		campaign_str, chapter_str, loc_str,
	)
}

print_combat_stats_line :: proc(db: ^lib.Db, char: CharacterStats) {
	fmt.printf("  Stats: STR:%d DEX:%d CON:%d INT:%d WIS:%d CHA:%d\n",
		char.str, char.dex, char.con, char.int_, char.wis, char.cha,
	)
	fmt.printf("  Combat Stats: Prof Bonus: +%d | Initiative: +%d | Passive Perception: %d | ", char.proficiency_bonus, char.initiative, char.passive_perception)
	print_spellcasting_stats_text(db, char)
	fmt.printf(" | Darkvision: %dft | Combat: %s\n", char.darkvision, char.combat == 1 ? "YES" : "no")
	
	fmt.printf("  Languages: %s\n", len(char.languages) > 0 ? char.languages : "None")
	if len(char.concentrating_on) > 0 {
		fmt.printf("  Concentrating On: %s\n", char.concentrating_on)
	}
}

print_save_bonuses_text :: proc(char: CharacterStats) {
	str_save := get_ability_modifier(char.str) + (char.save_prof_str == 1 ? char.proficiency_bonus : 0)
	dex_save := get_ability_modifier(char.dex) + (char.save_prof_dex == 1 ? char.proficiency_bonus : 0)
	con_save := get_ability_modifier(char.con) + (char.save_prof_con == 1 ? char.proficiency_bonus : 0)
	int_save := get_ability_modifier(char.int_) + (char.save_prof_int == 1 ? char.proficiency_bonus : 0)
	wis_save := get_ability_modifier(char.wis) + (char.save_prof_wis == 1 ? char.proficiency_bonus : 0)
	cha_save := get_ability_modifier(char.cha) + (char.save_prof_cha == 1 ? char.proficiency_bonus : 0)
	fmt.printf("  Save Bonuses: STR:%+d DEX:%+d CON:%+d INT:%+d WIS:%+d CHA:%+d\n",
		str_save, dex_save, con_save, int_save, wis_save, cha_save,
	)
}

print_money_status_text :: proc(char: CharacterStats) {
	print_save_bonuses_text(char)
	fmt.printf("  Money: GP:%d SP:%d CP:%d PP:%d EP:%d\n", char.gold, char.silver, char.copper, char.platinum, char.electrum)
	fmt.printf("  Status: %s\n", len(char.status_effects) > 0 ? char.status_effects : "None")
	fmt.printf("  Resistances: %s\n", len(char.resistances) > 0 ? char.resistances : "None")
	fmt.printf("  Last Action: %s\n", len(char.last_action) > 0 ? char.last_action : "None")
	fmt.printf("  Party: %s\n", len(char.party) > 0 ? char.party : "None")
	fmt.printf("  Backstory: %s\n", len(char.backstory) > 0 ? char.backstory : "None")
}

character_get_text :: proc(db: ^lib.Db, char: CharacterStats) {
	print_identity_line(char)
	print_campaign_details_line(char)
	print_combat_stats_line(db, char)
	print_save_proficiencies_text(char)
	print_money_status_text(char)
	print_personality_details_text(char)

	print_conditions_text(db, "character", char.id)
	print_character_skills_text(db, char)
	print_character_profs_text(db, char.id, "weapon", "Weapon Proficiencies")
	print_character_profs_text(db, char.id, "armor", "Armor Proficiencies")
	print_character_profs_text(db, char.id, "tool", "Tool Proficiencies")
	print_character_spell_slots_text(db, char)
	print_character_spells_text(db, char.id)
	print_character_companions_text(db, char.id)
	print_character_resources_text(db, char.id)
	print_character_inventory_text(db, char.id)
	print_character_abilities_text(db, char.id)
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
		character_get_json(db, char)
	} else {
		character_get_text(db, char)
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
	sql := fmt.tprintf("SELECT skill_name, proficiency_level, COALESCE(source, '') FROM character_skills WHERE character_id=%d ORDER BY skill_name", char.id)
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
		src := column_text_safe(stmt, 2)

		ability_score := get_skill_ability(char, skill)
		ability_mod := get_ability_modifier(ability_score)
		prof_bonus := get_prof_bonus(char.level)
		total_mod := ability_mod + prof_level * prof_bonus

		prof_str := "None"
		if prof_level == 1 do prof_str = "Proficient"
		if prof_level == 2 do prof_str = "Expertise"

		if len(src) > 0 && prof_level > 0 {
			fmt.printf("    - %s: %s (%+d) [%s]\n", skill, prof_str, total_mod, src)
		} else {
			fmt.printf("    - %s: %s (%+d)\n", skill, prof_str, total_mod)
		}
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



// Normalize a stored reset_condition string ("long_rest", "short_rest", "until_rest", "permanent")
// to a human-readable label ("Long Rest", "Short Rest", etc.) for display.
normalize_reset_condition :: proc(cond: string) -> string {
	switch strings.to_lower(cond, context.temp_allocator) {
	case "long_rest":     return "Long Rest"
	case "short_rest":    return "Short Rest"
	case "until_rest":    return "Until Next Rest"
	case "permanent":     return "Permanent"
	case "":              return "Long Rest"
	}
	return cond
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

		fmt.printf("    - %s: %d/%d (Reset: %s)\n", name, curr_val, max_val, normalize_reset_condition(reset_cond))
	}
}

print_character_profs_json :: proc(db: ^lib.Db, char_id: int, prof_type: string) {
	stmt: ^sqlite.Statement
	table_name := ""
	col_name := ""
	switch prof_type {
	case "weapon":
		table_name = "character_weapon_profs"
		col_name = "weapon_name"
	case "armor":
		table_name = "character_armor_profs"
		col_name = "armor_name"
	case "tool":
		table_name = "character_tool_profs"
		col_name = "tool_name"
	case: return
	}
	sql := fmt.tprintf("SELECT %s FROM %s WHERE character_id=%d ORDER BY %s", col_name, table_name, char_id, col_name)
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
		fmt.sbprintf(&builder, `{{"name":"%s"}}`, escape_json_string(name))
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_character_profs_text :: proc(db: ^lib.Db, char_id: int, prof_type: string, label: string) {
	stmt: ^sqlite.Statement
	table_name := ""
	col_name := ""
	switch prof_type {
	case "weapon":
		table_name = "character_weapon_profs"
		col_name = "weapon_name"
	case "armor":
		table_name = "character_armor_profs"
		col_name = "armor_name"
	case "tool":
		table_name = "character_tool_profs"
		col_name = "tool_name"
	case: return
	}
	sql := fmt.tprintf("SELECT %s FROM %s WHERE character_id=%d ORDER BY %s", col_name, table_name, char_id, col_name)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	has_rows := false
	for sqlite.step(stmt) == .Row {
		if !has_rows {
			fmt.printf("  %s:\n", label)
			has_rows = true
		}
		name := column_text_safe(stmt, 0)
		fmt.printf("    - %s\n", name)
	}
}

print_character_spell_slots_json :: proc(db: ^lib.Db, char: CharacterStats) {
	caster_lvl := get_multiclass_caster_level(db, char.id)
	
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "[")
	first := true
	if caster_lvl > 0 {
		for slot_lvl := 1; slot_lvl <= 9; slot_lvl += 1 {
			max_slots := MULTICLASS_SPELL_SLOTS[caster_lvl][slot_lvl]
			if max_slots <= 0 do continue
			
			used_slots := 0
			stmt: ^sqlite.Statement
			sql := fmt.tprintf("SELECT used_slots FROM character_spell_slots WHERE character_id=%d AND slot_level=%d", char.id, slot_lvl)
			sql_c := cstring(raw_data(sql))
			if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
				defer sqlite.finalize(stmt)
				if sqlite.step(stmt) == .Row {
					used_slots = int(sqlite.column_int(stmt, 0))
				}
			}
			
			if !first do strings.write_string(&builder, ",")
			first = false
			fmt.sbprintf(&builder, `{{"slot_level":%d,"max_slots":%d,"used_slots":%d}}`, slot_lvl, max_slots, used_slots)
		}
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_character_spell_slots_text :: proc(db: ^lib.Db, char: CharacterStats) {
	caster_lvl := get_multiclass_caster_level(db, char.id)
	if caster_lvl <= 0 do return
	
	fmt.println("  Spell Slots:")
	for slot_lvl := 1; slot_lvl <= 9; slot_lvl += 1 {
		max_slots := MULTICLASS_SPELL_SLOTS[caster_lvl][slot_lvl]
		if max_slots <= 0 do continue
		
		used_slots := 0
		stmt: ^sqlite.Statement
		sql := fmt.tprintf("SELECT used_slots FROM character_spell_slots WHERE character_id=%d AND slot_level=%d", char.id, slot_lvl)
		sql_c := cstring(raw_data(sql))
		if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
			defer sqlite.finalize(stmt)
			if sqlite.step(stmt) == .Row {
				used_slots = int(sqlite.column_int(stmt, 0))
			}
		}
		fmt.printf("    Level %d: %d/%d\n", slot_lvl, max_slots - used_slots, max_slots)
	}
}

get_class_spells_group_name :: proc(class_name: string) -> string {
	if class_name == "" do return "Spells:"
	cls_l := strings.to_lower(class_name, context.temp_allocator)
	// Title-case the class name for display
	cls_title := title_case(class_name)
	// Wizard is split at query level into wizard_prepared / wizard_spellbook
	if cls_l == "wizard_prepared" do return "Wizard Prepared:"
	if cls_l == "wizard_spellbook" do return "Wizard Spellbook (not prepared):"
	if cls_l == "wizard" do return "Wizard Spellbook:"
	
	is_prep := (cls_l == "cleric" || cls_l == "druid" || cls_l == "paladin")
	if is_prep do return fmt.tprintf("%s Prepared Spells:", cls_title)
	
	is_known := (cls_l == "bard" || cls_l == "sorcerer" || cls_l == "warlock" || cls_l == "ranger")
	if is_known do return fmt.tprintf("%s Known Spells:", cls_title)
	
	return fmt.tprintf("%s Spells:", cls_title)
}

title_case :: proc(s: string) -> string {
	if len(s) == 0 do return s
	b := strings.builder_make(context.temp_allocator)
	next_upper := true
	for i := 0; i < len(s); i += 1 {
		c := s[i]
		if c == ' ' || c == '-' || c == '_' {
			strings.write_byte(&b, c)
			next_upper = true
		} else if next_upper && c >= 'a' && c <= 'z' {
			strings.write_byte(&b, c - 32)
			next_upper = false
		} else {
			strings.write_byte(&b, c)
			next_upper = false
		}
	}
	return strings.to_string(b)
}

print_character_spells_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT s.id, s.name, s.level, cs.prepared, cs.class_name, COALESCE(cs.source, '') FROM character_spells cs JOIN spells s ON cs.spell_id = s.id WHERE cs.character_id = %d ORDER BY cs.class_name, s.level, s.name",
		char_id,
	)
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
		id := int(sqlite.column_int(stmt, 0))
		name := column_text_safe(stmt, 1)
		level := int(sqlite.column_int(stmt, 2))
		prepared := int(sqlite.column_int(stmt, 3))
		class_name := column_text_safe(stmt, 4)
		source := column_text_safe(stmt, 5)
		fmt.sbprintf(&builder, `{{"id":%d,"name":"%s","level":%d,"prepared":%d,"class_name":"%s","source":"%s"}}`, id, escape_json_string(name), level, prepared, escape_json_string(class_name), escape_json_string(source))
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_character_spells_text :: proc(db: ^lib.Db, char_id: int) {
	// Per PHB multiclass spell preparation rule: you prepare spells per-class
	// as if you were single-classed in that class. Combined caster level only
	// governs how many slots you have total, not which spells each class can
	// prepare. So we check each prepared spell against the spell's class only.
	// Per-class max slot level is queried inline below via get_class_max_slot_level.

	stmt: ^sqlite.Statement
	// Wizard spells are split into wizard_prepared / wizard_spellbook groups at query level.
	// All other classes use their class_name directly.
	// Sort order: non-wizard classes first (alphabetical), then wizard prepared, then wizard spellbook.
	sql := fmt.tprintf(
		`SELECT s.id, s.name, s.level, cs.prepared, cs.class_name,
		  CASE
		    WHEN LOWER(cs.class_name)='wizard' AND cs.prepared=1 THEN 'wizard_prepared'
		    WHEN LOWER(cs.class_name)='wizard' AND cs.prepared=0 THEN 'wizard_spellbook'
		    ELSE cs.class_name
		  END as display_group,
		  COALESCE(cs.source, '') as source
		 FROM character_spells cs
		 JOIN spells s ON cs.spell_id = s.id
		 WHERE cs.character_id = %d
		 ORDER BY display_group, s.level, s.name`,
		char_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	last_group := "___none___"
	has_spells := false
	
	for sqlite.step(stmt) == .Row {
		if !has_spells {
			fmt.println("  Spells:")
			has_spells = true
		}
		
		name := column_text_safe(stmt, 1)
		level := int(sqlite.column_int(stmt, 2))
		prep := int(sqlite.column_int(stmt, 3)) == 1
		class_name := column_text_safe(stmt, 4)
		display_group := column_text_safe(stmt, 5)
		source := column_text_safe(stmt, 6)

		group := get_class_spells_group_name(display_group)
		if group != last_group {
			fmt.printf("    %s\n", group)
			last_group = group
		}

		// In the Wizard Spellbook section, show [prepared] tag if the spell is also prepared.
		// In Wizard Prepared section, no tag needed — the section heading says it all.
		// For all other classes (prepared casters), still show [P] to indicate active preparation.
		group_l := strings.to_lower(display_group, context.temp_allocator)
		prep_tag := ""
		if group_l == "wizard_spellbook" && prep {
			prep_tag = " [P]"
		} else if group_l != "wizard_prepared" && group_l != "wizard_spellbook" && prep {
			prep_tag = " [P]"
		}
		source_tag := ""
		if len(source) > 0 do source_tag = fmt.tprintf(" [%s]", source)

		// Tag prepared spells that exceed the character's spell slots for THIS class.
		// Per 5e multiclass PHB rules, you prepare spells per-class as if you were
		// single-classed in that class. So Cleric 1 cannot prepare 2nd-level Cleric
		// spells even when 2nd-level slots are available from another class.
		// Use class_name (the actual class) not display_group (the section heading).
		over_slot_tag := ""
		if prep && level > 0 && len(class_name) > 0 {
			class_max := get_class_max_slot_level(db, char_id, class_name)
			if level > class_max && class_max > 0 {
				over_slot_tag = fmt.tprintf(" [OVER SLOT - %s max is %d]", class_name, class_max)
			} else if level > class_max && class_max == 0 {
				over_slot_tag = " [INVALID CLASS]"
			}
		}

		fmt.printf("      - %s (Level %d)%s%s%s\n", name, level, prep_tag, source_tag, over_slot_tag)
	}
}

print_character_companions_text :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT name, type, level, current_hp, max_hp, ac FROM companions WHERE character_id=%d ORDER BY id", char_id)
	sql_c := cstring(raw_data(sql))
	
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)
	
	has_companions := false
	for sqlite.step(stmt) == .Row {
		if !has_companions {
			fmt.println("  Companions:")
			has_companions = true
		}
		name := column_text_safe(stmt, 0)
		type_ := column_text_safe(stmt, 1)
		level := int(sqlite.column_int(stmt, 2))
		curr_hp := int(sqlite.column_int(stmt, 3))
		max_hp := int(sqlite.column_int(stmt, 4))
		ac := int(sqlite.column_int(stmt, 5))
		
		fmt.printf("    - %s (Type: %s, Level: %d, HP: %d/%d, AC: %d)\n", name, type_, level, curr_hp, max_hp, ac)
	}
}

print_character_companions_json :: proc(db: ^lib.Db, char_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT id, name, type, level, current_hp, max_hp, ac, attack_bonus, damage_dice, str, dex, con, int_, wis, cha, status_effects, resistances, vulnerabilities, immunities, last_action FROM companions WHERE character_id=%d ORDER BY id", char_id)
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
		id := int(sqlite.column_int(stmt, 0))
		name := column_text_safe(stmt, 1)
		type_ := column_text_safe(stmt, 2)
		level := int(sqlite.column_int(stmt, 3))
		curr_hp := int(sqlite.column_int(stmt, 4))
		max_hp := int(sqlite.column_int(stmt, 5))
		ac := int(sqlite.column_int(stmt, 6))
		atk := int(sqlite.column_int(stmt, 7))
		dmg := column_text_safe(stmt, 8)
		str := int(sqlite.column_int(stmt, 9))
		dex := int(sqlite.column_int(stmt, 10))
		con := int(sqlite.column_int(stmt, 11))
		int_ := int(sqlite.column_int(stmt, 12))
		wis := int(sqlite.column_int(stmt, 13))
		cha := int(sqlite.column_int(stmt, 14))
		effects := column_text_safe(stmt, 15)
		res := column_text_safe(stmt, 16)
		vuln := column_text_safe(stmt, 17)
		imm := column_text_safe(stmt, 18)
		act := column_text_safe(stmt, 19)
		
		fmt.sbprintf(&builder, `{{"id":%d,"character_id":%d,"name":"%s","type":"%s","level":%d,"current_hp":%d,"max_hp":%d,"ac":%d,"attack_bonus":%d,"damage_dice":"%s","str":%d,"dex":%d,"con":%d,"int":%d,"wis":%d,"cha":%d,"status_effects":"%s","resistances":"%s","vulnerabilities":"%s","immunities":"%s","last_action":"%s"}}`,
			id, char_id, escape_json_string(name), escape_json_string(type_), level, curr_hp, max_hp, ac, atk, escape_json_string(dmg),
			str, dex, con, int_, wis, cha,
			escape_json_string(effects), escape_json_string(res), escape_json_string(vuln), escape_json_string(imm), escape_json_string(act),
		)
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

print_conditions_json :: proc(db: ^lib.Db, target_type: string, target_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT name, source, duration_rounds, save_dc, save_ability, applied_at FROM conditions WHERE target_type='%s' AND target_id=%d ORDER BY applied_at", escape_sql(target_type), target_id)
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
		source := column_text_safe(stmt, 1)
		dur := int(sqlite.column_int(stmt, 2))
		dc := int(sqlite.column_int(stmt, 3))
		ability := column_text_safe(stmt, 4)
		applied := column_text_safe(stmt, 5)
		fmt.sbprintf(&builder, `{{"name":"%s","source":"%s","duration_rounds":%d,"save_dc":%d,"save_ability":"%s","applied_at":"%s"}}`,
			escape_json_string(name), escape_json_string(source), dur, dc, escape_json_string(ability), escape_json_string(applied),
		)
	}
	strings.write_string(&builder, "]")
	fmt.print(strings.to_string(builder))
}

format_condition_duration :: proc(dur_type: string, dur_amount: int) -> string {
	dt := strings.to_lower(dur_type, context.temp_allocator)
	switch dt {
	case "concentration":
		if dur_amount > 0 do return fmt.tprintf("Concentration | %d rounds remaining", dur_amount)
		return "Concentration | duration tied to caster"
	case "hours":
		if dur_amount == 1 do return "~1 hour (game time)"
		return fmt.tprintf("~%d hours (game time)", dur_amount)
	case "days":
		if dur_amount == 1 do return "~1 day (game time)"
		return fmt.tprintf("~%d days (game time)", dur_amount)
	case "until_rest", "until rest":
		return "Until next rest"
	case "permanent":
		return "Permanent"
	case "rounds", "":
		if dur_amount > 0 do return fmt.tprintf("%d rounds remaining", dur_amount)
		return "Duration unknown"
	}
	if dur_amount > 0 do return fmt.tprintf("%d %s remaining", dur_amount, dur_type)
	return "Duration unknown"
}

strip_concentration_tag :: proc(source: string) -> string {
	if len(source) == 0 do return source
	out := source
	tokens := []string{"(Concentration)", "(concentration)", "(CONCENTRATION)", "Concentration", "concentration", "CONCENTRATION"}
	changed := true
	for changed {
		changed = false
		for tok in tokens {
			idx := strings.index(out, tok)
			if idx >= 0 {
				end := idx + len(tok)
				for end < len(out) && (out[end] == ' ' || out[end] == ',' || out[end] == '(') {
					end += 1
				}
				for idx > 0 && (out[idx-1] == ' ' || out[idx-1] == ',' || out[idx-1] == ')') {
					idx -= 1
				}
				b := strings.builder_make(context.temp_allocator)
				strings.write_string(&b, out[:idx])
				strings.write_string(&b, out[end:])
				out = strings.to_string(b)
				changed = true
				break
			}
		}
	}
	return strings.trim(out, " \t,()")
}

print_conditions_text :: proc(db: ^lib.Db, target_type: string, target_id: int) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT name, source, duration_rounds, save_dc, save_ability, COALESCE(duration_type, 'rounds') FROM conditions WHERE target_type='%s' AND target_id=%d ORDER BY applied_at", escape_sql(target_type), target_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return
	}
	defer sqlite.finalize(stmt)

	has_rows := false
	for sqlite.step(stmt) == .Row {
		if !has_rows {
			fmt.println("  Active Conditions:")
			has_rows = true
		}
		name := column_text_safe(stmt, 0)
		source := column_text_safe(stmt, 1)
		dur := int(sqlite.column_int(stmt, 2))
		dc := int(sqlite.column_int(stmt, 3))
		ability := column_text_safe(stmt, 4)
		dur_type := column_text_safe(stmt, 5)

		// Strip redundant "Concentration" tag from source when duration_type already conveys it.
		cleaned_source := source
		if strings.to_lower(dur_type, context.temp_allocator) == "concentration" {
			cleaned_source = strip_concentration_tag(source)
		}

		line := fmt.tprintf("    - %s", name)
		if len(cleaned_source) > 0 do line = fmt.tprintf("%s | Source: %s", line, cleaned_source)
		if dc > 0 do line = fmt.tprintf("%s | Escape/Save: %s DC %d", line, strings.to_upper(ability, context.temp_allocator), dc)
		dur_str := format_condition_duration(dur_type, dur)
		line = fmt.tprintf("%s | %s", line, dur_str)
		fmt.println(line)
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

character_set_rests :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-rests <id> <short_rests> <long_rests>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-rests <id> <short_rests> <long_rests>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	shorts := strconv.atoi(args[2])
	longs := strconv.atoi(args[3])

	sql := fmt.tprintf("UPDATE characters SET short_rests_available=%d, long_rests_available=%d WHERE id=%d", shorts, longs, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set rests"}`)
		} else {
			fmt.eprintln("Failed to set rests")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Rests set","id":%d,"short_rests_available":%d,"long_rests_available":%d}}\n`, id, shorts, longs)
	} else {
		fmt.printf("Set rests for character %d to %d Short / %d Long\n", id, shorts, longs)
	}
	return 0
}

character_set_skill :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-skill <char_id> <skill_name> <proficiency_level> [source]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-skill <char_id> <skill_name> <proficiency_level> [source]")
		}
		return 1
	}
	char_id := strconv.atoi(args[1])
	skill_name := args[2]
	prof_level := strconv.atoi(args[3])
	source := len(args) > 4 ? args[4] : ""

	if prof_level < 0 || prof_level > 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Proficiency level must be 0 (none), 1 (proficient), or 2 (expertise)"}`)
		} else {
			fmt.eprintln("Error: Proficiency level must be 0 (none), 1 (proficient), or 2 (expertise)")
		}
		return 1
	}

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO character_skills (character_id, skill_name, proficiency_level, source) VALUES (%d, '%s', %d, '%s')",
		char_id, escape_sql(skill_name), prof_level, escape_sql(source),
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
		fmt.printf(`"success":true,"message":"Skill set","character_id":%d,"skill_name":"%s","proficiency_level":%d,"source":"%s"`, char_id, escape_json_string(skill_name), prof_level, escape_json_string(source))
		fmt.println("}")
	} else {
		if len(source) > 0 {
			fmt.printf("Skill %s set to proficiency level %d [%s] for character %d\n", skill_name, prof_level, source, char_id)
		} else {
			fmt.printf("Skill %s set to proficiency level %d for character %d\n", skill_name, prof_level, char_id)
		}
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
		fmt.printf("Resource %s set to %d/%d (Reset: %s) for character %d\n", resource_name, curr_val, max_val, normalize_reset_condition(reset_condition), char_id)
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
			stmt_chk: ^sqlite.Statement
			sql_chk := fmt.tprintf("SELECT long_rests_available FROM characters WHERE id=%d", char_id)
			sql_chk_c := cstring(raw_data(sql_chk))
			long_avail := 1
			if sqlite.prepare(db.ptr, sql_chk_c, i32(len(sql_chk)), &stmt_chk, nil) == .Ok {
				defer sqlite.finalize(stmt_chk)
				if sqlite.step(stmt_chk) == .Row {
					long_avail = int(sqlite.column_int(stmt_chk, 0))
				}
			}
			if long_avail <= 0 {
				if !db.is_json {
					fmt.println("Warning: You do not have any available long rests left for today. Resting anyway.")
				}
			}

			sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition IN ('long_rest', 'short_rest')", char_id)
			
			// Reset spell slots
			sql_slots := fmt.tprintf("UPDATE character_spell_slots SET used_slots=0 WHERE character_id=%d", char_id)
			lib.db_exec(db, sql_slots)
			// Reset HP to max
			sql_hp := fmt.tprintf("UPDATE characters SET current_hp=max_hp WHERE id=%d", char_id)
			lib.db_exec(db, sql_hp)
			// Regain Hit Dice
			sql_hd := fmt.tprintf("UPDATE characters SET hit_dice_expended = MAX(0, hit_dice_expended - MAX(1, max_hit_dice / 2)) WHERE id=%d", char_id)
			lib.db_exec(db, sql_hd)
			// Decrease exhaustion
			sql_ex := fmt.tprintf("UPDATE characters SET exhaustion = MAX(0, exhaustion - 1) WHERE id=%d", char_id)
			lib.db_exec(db, sql_ex)
			// Reset available short and long rests
			sql_rests := fmt.tprintf("UPDATE characters SET short_rests_available=2, long_rests_available=1 WHERE id=%d", char_id)
			lib.db_exec(db, sql_rests)
		} else if cond == "short_rest" {
			stmt_chk: ^sqlite.Statement
			sql_chk := fmt.tprintf("SELECT short_rests_available FROM characters WHERE id=%d", char_id)
			sql_chk_c := cstring(raw_data(sql_chk))
			short_avail := 2
			if sqlite.prepare(db.ptr, sql_chk_c, i32(len(sql_chk)), &stmt_chk, nil) == .Ok {
				defer sqlite.finalize(stmt_chk)
				if sqlite.step(stmt_chk) == .Row {
					short_avail = int(sqlite.column_int(stmt_chk, 0))
				}
			}
			if short_avail <= 0 {
				if !db.is_json {
					fmt.println("Warning: You do not have any available short rests left for today. Resting anyway.")
				}
			}

			sql = fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition='short_rest'", char_id)
			// Decrement available short rests
			sql_rests := fmt.tprintf("UPDATE characters SET short_rests_available = MAX(0, short_rests_available - 1) WHERE id=%d", char_id)
			lib.db_exec(db, sql_rests)
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

character_set_location :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-location <id> <location_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-location <id> <location_id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	loc_id := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET location_id=%d WHERE id=%d", loc_id, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character location"}`)
		} else {
			fmt.eprintln("Failed to set character location")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Location set","id":%d,"location_id":%d`, id, loc_id)
		fmt.println("}")
	} else {
		fmt.printf("Location set to %d for character %d\n", loc_id, id)
	}
	return 0
}

character_set_chapter :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-chapter <id> <chapter_id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-chapter <id> <chapter_id>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	chapter_id := args[2]

	sql := fmt.tprintf("UPDATE characters SET chapter_id='%s' WHERE id=%d", escape_sql(chapter_id), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character chapter"}`)
		} else {
			fmt.eprintln("Failed to set character chapter")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Chapter set","id":%d,"chapter_id":"%s"`, id, escape_json_string(chapter_id))
		fmt.println("}")
	} else {
		fmt.printf("Chapter set to '%s' for character %d\n", chapter_id, id)
	}
	return 0
}

character_set_owner :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-owner <id> <owner_name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-owner <id> <owner_name>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	owner := args[2]

	sql := fmt.tprintf("UPDATE characters SET owner='%s' WHERE id=%d", escape_sql(owner), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character owner"}`)
		} else {
			fmt.eprintln("Failed to set character owner")
		}
		return 1
	}

	if db.is_json {
		fmt.print("{")
		fmt.printf(`"success":true,"message":"Owner set","id":%d,"owner":"%s"`, id, escape_json_string(owner))
		fmt.println("}")
	} else {
		fmt.printf("Owner set to '%s' for character %d\n", owner, id)
	}
	return 0
}

character_set_gender :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-gender <id> <gender>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-gender <id> <gender>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	gender := args[2]

	sql := fmt.tprintf("UPDATE characters SET gender='%s' WHERE id=%d", escape_sql(gender), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character gender"}`)
		} else {
			fmt.eprintln("Failed to set character gender")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{"success":true,"message":"Gender set to '%s' for character %d"}%s`, escape_json_string(gender), id, "\n")
	} else {
		fmt.printf("Gender set to '%s' for character %d\n", gender, id)
	}
	return 0
}

character_set_age :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-age <id> <age>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-age <id> <age>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	age := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET age=%d WHERE id=%d", age, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set character age"}`)
		} else {
			fmt.eprintln("Failed to set character age")
		}
		return 1
	}
	if db.is_json {
		fmt.printf(`{"success":true,"message":"Age set to %d for character %d"}%s`, age, id, "\n")
	} else {
		fmt.printf("Age set to %d for character %d\n", age, id)
	}
	return 0
}

character_set_proficiency :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-proficiency <id> <bonus>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-proficiency <id> <bonus>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	bonus := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET proficiency_bonus=%d WHERE id=%d", bonus, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set proficiency bonus"}`)
		} else {
			fmt.eprintln("Failed to set proficiency bonus")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Proficiency bonus set","id":%d,"proficiency_bonus":%d}` + "\n", id, bonus)
	} else {
		fmt.printf("Proficiency bonus set to +%d for character %d\n", bonus, id)
	}
	return 0
}

character_set_spellcasting :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-spellcasting <id> <dc> <attack_bonus>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-spellcasting <id> <dc> <attack_bonus>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	dc := strconv.atoi(args[2])
	atk := strconv.atoi(args[3])

	sql := fmt.tprintf("UPDATE characters SET spell_save_dc=%d, spell_attack_bonus=%d WHERE id=%d", dc, atk, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set spellcasting"}`)
		} else {
			fmt.eprintln("Failed to set spellcasting")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Spellcasting set","id":%d,"spell_save_dc":%d,"spell_attack_bonus":%d}` + "\n", id, dc, atk)
	} else {
		fmt.printf("Spellcasting set: DC %d, Attack +%d for character %d\n", dc, atk, id)
	}
	return 0
}

character_set_initiative :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-initiative <id> <modifier>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-initiative <id> <modifier>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	mod := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET initiative=%d WHERE id=%d", mod, id)
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
		fmt.printf("Initiative set to +%d for character %d\n", mod, id)
	}
	return 0
}

character_set_passive_perception :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-passive-perception <id> <value>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-passive-perception <id> <value>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	val := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET passive_perception=%d WHERE id=%d", val, id)
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
		fmt.printf("Passive perception set to %d for character %d\n", val, id)
	}
	return 0
}

character_set_languages :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-languages <id> <csv>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-languages <id> <csv>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	langs := args[2]

	sql := fmt.tprintf("UPDATE characters SET languages='%s' WHERE id=%d", escape_sql(langs), id)
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
		fmt.printf("Languages set to '%s' for character %d\n", langs, id)
	}
	return 0
}

character_set_max_hit_dice :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-max-hit-dice <id> <amount>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-max-hit-dice <id> <amount>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	amount := strconv.atoi(args[2])

	sql := fmt.tprintf("UPDATE characters SET max_hit_dice=%d WHERE id=%d", amount, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set max hit dice"}`)
		} else {
			fmt.eprintln("Failed to set max hit dice")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Max hit dice set","id":%d,"max_hit_dice":%d}` + "\n", id, amount)
	} else {
		fmt.printf("Max hit dice set to %d for character %d\n", amount, id)
	}
	return 0
}

character_set_combat :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-combat <id> <0|1>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-combat <id> <0|1>")
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

	sql := fmt.tprintf("UPDATE characters SET combat=%d WHERE id=%d", state, id)
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
		fmt.printf("Combat %s for character %d\n", state == 1 ? "started" : "ended", id)
	}
	return 0
}

character_set_concentrating :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-concentrating <id> <spell_name_or_blank>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-concentrating <id> <spell_name_or_blank>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	spell := args[2]

	sql := fmt.tprintf("UPDATE characters SET concentrating_on='%s' WHERE id=%d", escape_sql(spell), id)
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
			fmt.printf("Character %d now concentrating on: %s\n", id, spell)
		} else {
			fmt.printf("Character %d concentration cleared\n", id)
		}
	}
	return 0
}

character_add_prof :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character add-prof <id> <weapon|armor|tool> <name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character add-prof <id> <weapon|armor|tool> <name>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	prof_type := args[2]
	name := args[3]

	table_name := ""
	col_name := ""
	switch prof_type {
	case "weapon":
		table_name = "character_weapon_profs"
		col_name = "weapon_name"
	case "armor":
		table_name = "character_armor_profs"
		col_name = "armor_name"
	case "tool":
		table_name = "character_tool_profs"
		col_name = "tool_name"
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Prof type must be weapon, armor, or tool"}`)
		} else {
			fmt.eprintln("Prof type must be weapon, armor, or tool")
		}
		return 1
	}

	sql := fmt.tprintf("INSERT OR REPLACE INTO %s (character_id, %s) VALUES(%d, '%s')", table_name, col_name, id, escape_sql(name))
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add proficiency"}`)
		} else {
			fmt.eprintln("Failed to add proficiency")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Prof added","id":%d,"type":"%s","name":"%s"}` + "\n", id, prof_type, escape_json_string(name))
	} else {
		fmt.printf("Added %s proficiency '%s' to character %d\n", prof_type, name, id)
	}
	return 0
}

character_remove_prof :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character remove-prof <id> <weapon|armor|tool> <name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character remove-prof <id> <weapon|armor|tool> <name>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	prof_type := args[2]
	name := args[3]

	table_name := ""
	col_name := ""
	switch prof_type {
	case "weapon":
		table_name = "character_weapon_profs"
		col_name = "weapon_name"
	case "armor":
		table_name = "character_armor_profs"
		col_name = "armor_name"
	case "tool":
		table_name = "character_tool_profs"
		col_name = "tool_name"
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Prof type must be weapon, armor, or tool"}`)
		} else {
			fmt.eprintln("Prof type must be weapon, armor, or tool")
		}
		return 1
	}

	sql := fmt.tprintf("DELETE FROM %s WHERE character_id=%d AND %s='%s'", table_name, id, col_name, escape_sql(name))
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove proficiency"}`)
		} else {
			fmt.eprintln("Failed to remove proficiency")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Prof removed","id":%d,"type":"%s","name":"%s"}` + "\n", id, prof_type, escape_json_string(name))
	} else {
		fmt.printf("Removed %s proficiency '%s' from character %d\n", prof_type, name, id)
	}
	return 0
}

character_set_spell_slot :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-spell-slot <id> <slot_level> <max> <used>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-spell-slot <id> <slot_level> <max> <used>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	slot_level := strconv.atoi(args[2])
	max_v := strconv.atoi(args[3])
	used_v := strconv.atoi(args[4])

	sql := fmt.tprintf("INSERT OR REPLACE INTO character_spell_slots (character_id, slot_level, max_slots, used_slots) VALUES(%d, %d, %d, %d)", id, slot_level, max_v, used_v)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to set spell slot"}`)
		} else {
			fmt.eprintln("Failed to set spell slot")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Spell slot set","id":%d,"slot_level":%d,"max_slots":%d,"used_slots":%d}` + "\n", id, slot_level, max_v, used_v)
	} else {
		fmt.printf("Character %d spell slot level %d: %d/%d\n", id, slot_level, max_v - used_v, max_v)
	}
	return 0
}

condition_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent condition add <character|npc|creature> <id> <name> [source] [duration_amount] [save_dc] [save_ability] [duration_type]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent condition add <character|npc|creature> <id> <name> [source] [duration_amount] [save_dc] [save_ability] [duration_type]")
			fmt.eprintln("  duration_type: rounds (default), concentration, hours, days, until_rest, permanent")
		}
		return 1
	}
	target_type := args[0]
	if target_type == "char" do target_type = "character"
	target_id := strconv.atoi(args[1])
	name := args[2]
	source := len(args) > 3 ? args[3] : ""
	duration := len(args) > 4 ? strconv.atoi(args[4]) : 0
	save_dc := len(args) > 5 ? strconv.atoi(args[5]) : 0
	save_ability := len(args) > 6 ? args[6] : ""
	duration_type := len(args) > 7 ? args[7] : "rounds"

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO conditions (target_type, target_id, name, source, duration_rounds, save_dc, save_ability, duration_type) VALUES('%s', %d, '%s', '%s', %d, %d, '%s', '%s')",
		escape_sql(target_type), target_id, escape_sql(name), escape_sql(source), duration, save_dc, escape_sql(save_ability), escape_sql(duration_type),
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to add condition"}`)
		} else {
			fmt.eprintln("Failed to add condition")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Condition added","target_type":"%s","target_id":%d,"name":"%s","source":"%s","duration_amount":%d,"duration_type":"%s","save_dc":%d,"save_ability":"%s"}` + "\n",
			escape_json_string(target_type), target_id, escape_json_string(name), escape_json_string(source), duration, escape_json_string(duration_type), save_dc, escape_json_string(save_ability))
	} else {
		fmt.printf("Added condition '%s' to %s %d\n", name, target_type, target_id)
	}
	return 0
}

condition_remove :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent <entity> remove-condition <id> <name>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent <entity> remove-condition <id> <name>")
		}
		return 1
	}
	target_type := args[0]
	if target_type == "char" do target_type = "character"
	target_id := strconv.atoi(args[1])
	name := args[2]

	sql := fmt.tprintf("DELETE FROM conditions WHERE target_type='%s' AND target_id=%d AND name='%s'", escape_sql(target_type), target_id, escape_sql(name))
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Failed to remove condition"}`)
		} else {
			fmt.eprintln("Failed to remove condition")
		}
		return 1
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Condition removed","target_type":"%s","target_id":%d,"name":"%s"}` + "\n", escape_json_string(target_type), target_id, escape_json_string(name))
	} else {
		fmt.printf("Removed condition '%s' from %s %d\n", name, target_type, target_id)
	}
	return 0
}

condition_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent <entity> list-conditions <id>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent <entity> list-conditions <id>")
		}
		return 1
	}
	target_type := args[0]
	if target_type == "char" do target_type = "character"
	target_id := strconv.atoi(args[1])

	if db.is_json {
		print_conditions_json(db, target_type, target_id)
		fmt.println()
	} else {
		print_conditions_text(db, target_type, target_id)
	}
	return 0
}

character_set_darkvision :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character set-darkvision <id> <range_in_feet>"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character set-darkvision <id> <range_in_feet>")
		}
		return 1
	}
	id := strconv.atoi(args[1])
	rng := strconv.atoi(args[2])
	sql := fmt.tprintf("UPDATE characters SET darkvision=%d WHERE id=%d", rng, id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to set darkvision"}`) } else { fmt.eprintln("Failed to set darkvision") }
		return 1
	}
	if db.is_json { fmt.printf(`{"success":true,"message":"Darkvision set","id":%d,"darkvision":%d}` + "\n", id, rng) } else { fmt.printf("Darkvision set to %dft for character %d\n", rng, id) }
	return 0
}

character_set_bond :: proc(db: ^lib.Db, args: []string) -> int {
	return character_set_text_field(db, args, "bond", "Bond")
}

character_set_flaw :: proc(db: ^lib.Db, args: []string) -> int {
	return character_set_text_field(db, args, "flaw", "Flaw")
}

character_set_ideal :: proc(db: ^lib.Db, args: []string) -> int {
	return character_set_text_field(db, args, "ideal", "Ideal")
}

character_set_personality_traits :: proc(db: ^lib.Db, args: []string) -> int {
	return character_set_text_field(db, args, "personality_traits", "Personality Traits")
}

character_set_appearance :: proc(db: ^lib.Db, args: []string) -> int {
	return character_set_text_field(db, args, "appearance", "Appearance")
}

character_set_text_field :: proc(db: ^lib.Db, args: []string, column: string, label: string) -> int {
	if len(args) < 3 {
		if db.is_json {
			fmt.printf(`{"success":false,"error":"Usage: dnd-agent character set-%s <id> <text>"}\n`, column)
		} else {
			fmt.eprintln(fmt.tprintf("Usage: dnd-agent character set-%s <id> <text>", column))
		}
		return 1
	}
	id := strconv.atoi(args[1])
	text := args[2]
	sql := fmt.tprintf("UPDATE characters SET %s='%s' WHERE id=%d", column, escape_sql(text), id)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { fmt.println(fmt.tprintf(`{"success":false,"error":"Failed to set %s"}`, column)) } else { fmt.eprintln(fmt.tprintf("Failed to set %s", column)) }
		return 1
	}
	if db.is_json {
		fmt.printf(`{"success":true,"message":"%s set","id":%d,"%s":"%s"}` + "\n", label, id, column, escape_json_string(text))
	} else {
		fmt.printf("%s set for character %d\n", label, id)
	}
	return 0
}
