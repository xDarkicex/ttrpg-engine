package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

// Hit die size by D&D 5e class name (lowercase key).
class_hit_die :: proc(class_name: string) -> int {
	switch strings.to_lower(class_name) {
	case "barbarian":       return 12
	case "fighter", "paladin", "ranger": return 10
	case "artificer", "cleric", "druid", "monk", "rogue", "warlock": return 8
	case "sorcerer", "wizard": return 6
	}
	return 8 // default d8
}

// Average rounded up: d6→4, d8→5, d10→6, d12→7
hit_die_average :: proc(die: int) -> int {
	switch die {
	case 6:  return 4
	case 8:  return 5
	case 10: return 6
	case 12: return 7
	}
	return 5
}

// Heal a character by spending hit dice during a short rest.
// Returns total HP healed (before capping at max_hp).
short_rest_heal :: proc(db: ^lib.Db, char_id: int, hit_dice_count: int) -> (int, bool) {
	// Find the character's largest hit die from their classes
	stmt: ^sqlite.Statement
	cls_sql := fmt.tprintf("SELECT class_name FROM character_classes WHERE character_id=%d", char_id)
	cls_c := cstring(raw_data(cls_sql))
	best_die := 8 // default d8
	if sqlite.prepare(db.ptr, cls_c, i32(len(cls_sql)), &stmt, nil) == .Ok {
		for sqlite.step(stmt) == .Row {
			die := class_hit_die(column_text_safe(stmt, 0))
			if die > best_die do best_die = die
		}
		sqlite.finalize(stmt)
	}

	// Get current character HP and CON
	hp_sql := fmt.tprintf("SELECT current_hp, max_hp, con, hit_dice_expended, max_hit_dice FROM characters WHERE id=%d", char_id)
	hp_c := cstring(raw_data(hp_sql))
	if sqlite.prepare(db.ptr, hp_c, i32(len(hp_sql)), &stmt, nil) != .Ok do return 0, false
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row do return 0, false

	current_hp := int(sqlite.column_int(stmt, 0))
	max_hp := int(sqlite.column_int(stmt, 1))
	con := int(sqlite.column_int(stmt, 2))
	expended := int(sqlite.column_int(stmt, 3))
	max_dice := int(sqlite.column_int(stmt, 4))

	available := max_dice - expended
	if available <= 0 do return 0, false
	dice_to_spend := hit_dice_count
	if dice_to_spend > available do dice_to_spend = available

	con_mod := (con - 10) / 2
	avg_per_die := hit_die_average(best_die)
	heal_per_die := avg_per_die + con_mod
	if heal_per_die < 1 do heal_per_die = 1

	total_heal := dice_to_spend * heal_per_die
	new_hp := current_hp + total_heal
	if new_hp > max_hp do new_hp = max_hp
	new_expended := expended + dice_to_spend

	update_sql := fmt.tprintf("UPDATE characters SET current_hp=%d, hit_dice_expended=%d WHERE id=%d", new_hp, new_expended, char_id)
	lib.db_exec(db, update_sql)

	return new_hp - current_hp, true
}

rest_short :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: dnd-agent rest short <character_id> <hit_dice_count>")
	}
	char_id := strconv.atoi(args[1])
	hit_dice_count := strconv.atoi(args[2])
	dice_count := hit_dice_count
	if dice_count < 0 do dice_count = 0

	// Check short_rests_available
	stmt: ^sqlite.Statement
	chk_sql := fmt.tprintf("SELECT short_rests_available FROM characters WHERE id=%d", char_id)
	chk_c := cstring(raw_data(chk_sql))
	short_avail := 2
	if sqlite.prepare(db.ptr, chk_c, i32(len(chk_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row do short_avail = int(sqlite.column_int(stmt, 0))
		sqlite.finalize(stmt)
	}
	if short_avail <= 0 {
		if !db.is_json do fmt.println("Warning: No short rests available. Resting anyway.")
	}

	// Heal via hit dice
	healed, ok := short_rest_heal(db, char_id, dice_count)
	_ = ok // heal returns false if no dice available, silently proceed

	// Reset short-rest resources
	reset_sql := fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition='short_rest'", char_id)
	lib.db_exec(db, reset_sql)

	// Decrement short_rests_available
	dec_sql := fmt.tprintf("UPDATE characters SET short_rests_available = MAX(0, short_rests_available - 1) WHERE id=%d", char_id)
	lib.db_exec(db, dec_sql)

	// Clear conditions that end on short or long rest
	cond_sql := fmt.tprintf("DELETE FROM conditions WHERE target_type='character' AND target_id=%d AND duration_type IN ('short_rest', 'until_rest')", char_id)
	lib.db_exec(db, cond_sql)

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Short rest completed","character_id":%d,"hp_healed":%d,"hit_dice_spent":%d}}` + "\n", char_id, healed, dice_count)
	} else {
		fmt.printf("Short rest: character %d healed %d HP, spent %d hit dice.\n", char_id, healed, dice_count)
	}
	return 0
}

rest_long :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: dnd-agent rest long <character_id>")
	}
	char_id := strconv.atoi(args[1])

	// Check long_rests_available
	stmt: ^sqlite.Statement
	chk_sql := fmt.tprintf("SELECT long_rests_available FROM characters WHERE id=%d", char_id)
	chk_c := cstring(raw_data(chk_sql))
	long_avail := 1
	if sqlite.prepare(db.ptr, chk_c, i32(len(chk_sql)), &stmt, nil) == .Ok {
		if sqlite.step(stmt) == .Row do long_avail = int(sqlite.column_int(stmt, 0))
		sqlite.finalize(stmt)
	}
	if long_avail <= 0 {
		if !db.is_json do fmt.println("Warning: No long rests available. Resting anyway.")
	}

	// Full heal + clear temp HP
	lib.db_exec(db, fmt.tprintf("UPDATE characters SET current_hp=max_hp, temp_hp=0 WHERE id=%d", char_id))

	// Recover half expended hit dice (minimum 1)
	lib.db_exec(db, fmt.tprintf("UPDATE characters SET hit_dice_expended = MAX(0, hit_dice_expended - MAX(1, max_hit_dice / 2)) WHERE id=%d", char_id))

	// Decrease exhaustion by 1
	lib.db_exec(db, fmt.tprintf("UPDATE characters SET exhaustion = MAX(0, exhaustion - 1) WHERE id=%d", char_id))

	// Reset resources (long_rest and short_rest conditions)
	lib.db_exec(db, fmt.tprintf("UPDATE character_resources SET current_amount=max_amount WHERE character_id=%d AND reset_condition IN ('long_rest', 'short_rest')", char_id))

	// Reset spell slots
	lib.db_exec(db, fmt.tprintf("UPDATE character_spell_slots SET used_slots=0 WHERE character_id=%d", char_id))

	// Reset available rests
	lib.db_exec(db, fmt.tprintf("UPDATE characters SET short_rests_available=2, long_rests_available=1 WHERE id=%d", char_id))

	// Clear conditions that end on short or long rest
	lib.db_exec(db, fmt.tprintf("DELETE FROM conditions WHERE target_type='character' AND target_id=%d AND duration_type IN ('short_rest', 'long_rest', 'until_rest')", char_id))

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Long rest completed","character_id":%d}}` + "\n", char_id)
	} else {
		fmt.printf("Long rest: character %d fully healed, resources and spell slots reset.\n", char_id)
	}
	return 0
}
