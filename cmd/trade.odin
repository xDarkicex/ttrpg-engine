package cmd

import "core:fmt"
import "core:strconv"
import lib "../lib"
import sqlite "ext:sqlite3"

/*
trade_character transfers items and optional coins between two player
characters. Both participants must exist and the sender must own the item.

Usage: ttrpg-engine trade <from_char_id> <to_char_id> <item_id> <quantity> [gp] [sp] [cp] [pp] [ep]
*/
trade_character :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { usage_error(db, "Usage: ttrpg-engine trade <from_char_id> <to_char_id> <item_id> <quantity> [gp] [sp] [cp] [pp] [ep]") }
		else { fmt.eprintln("Usage: ttrpg-engine trade <from_char_id> <to_char_id> <item_id> <quantity> [gp] [sp] [cp] [pp] [ep]") }
		return 1
	}
	from_id := strconv.atoi(args[0])
	to_id := strconv.atoi(args[1])
	item_id := strconv.atoi(args[2])
	qty := strconv.atoi(args[3])

	// Verify both characters exist
	if !character_exists(db, from_id) {
		if db.is_json { usage_error(db, "Sender character not found") }
		else { fmt.eprintln("Sender character not found") }
		return 1
	}
	if !character_exists(db, to_id) {
		if db.is_json { usage_error(db, "Recipient character not found") }
		else { fmt.eprintln("Recipient character not found") }
		return 1
	}

	// Check sender owns the item
	stmt: ^sqlite.Statement
	check_sql := fmt.tprintf(
		"SELECT inv.quantity, i.name FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d AND inv.item_id=%d",
		from_id, item_id,
	)
	check_sql_c := cstring(raw_data(check_sql))
	if sqlite.prepare(db.ptr, check_sql_c, i32(len(check_sql)), &stmt, nil) != .Ok {
		if db.is_json { usage_error(db, "Failed to check inventory") }
		else { fmt.eprintln("Failed to check inventory") }
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json { usage_error(db, "Sender does not own this item") }
		else { fmt.eprintln("Sender does not own this item") }
		return 1
	}
	owned_qty := int(sqlite.column_int(stmt, 0))
	item_name := column_text_safe(stmt, 1)

	if owned_qty < qty {
		if db.is_json { usage_error(db, "Sender has insufficient quantity") }
		else { fmt.eprintln("Sender has insufficient quantity") }
		return 1
	}

	// Parse optional coin amounts (gp, sp, cp, pp, ep)
	gp := 0; sp := 0; cp := 0; pp := 0; ep := 0
	if len(args) >= 5 do gp = strconv.atoi(args[4])
	if len(args) >= 6 do sp = strconv.atoi(args[5])
	if len(args) >= 7 do cp = strconv.atoi(args[6])
	if len(args) >= 8 do pp = strconv.atoi(args[7])
	if len(args) >= 9 do ep = strconv.atoi(args[8])

	total_coins_cp := pp * 1000 + gp * 100 + ep * 50 + sp * 10 + cp

	// Remove item from sender
	remove_sql := fmt.tprintf("UPDATE inventory SET quantity=quantity-%d WHERE character_id=%d AND item_id=%d", qty, from_id, item_id)
	lib.db_exec(db, remove_sql)
	lib.db_exec(db, "DELETE FROM inventory WHERE quantity <= 0")

	// Add item to recipient
	add_sql := fmt.tprintf("INSERT INTO inventory (character_id, item_id, quantity) VALUES(%d, %d, %d)", to_id, item_id, qty)
	lib.db_exec(db, add_sql)

	// Transfer coins if any
	coin_msg := ""
	if total_coins_cp > 0 {
		deduct_coins(db, "characters", "id", from_id, total_coins_cp)
		credit_coins(db, "characters", "id", to_id, total_coins_cp)
		coin_msg = fmt.tprintf(", %d gp, %d sp, %d cp", gp, sp, cp)
	}

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Trade complete","from_char_id":%d,"to_char_id":%d,"item":"%s","quantity":%d,"gp":%d,"sp":%d,"cp":%d,"pp":%d,"ep":%d}}` + "\n",
			from_id, to_id, item_name, qty, gp, sp, cp, pp, ep)
	} else {
		fmt.printf("Trade: %s x%d from character %d to %d%s\n", item_name, qty, from_id, to_id, coin_msg)
	}
	return 0
}

character_exists :: proc(db: ^lib.Db, char_id: int) -> bool {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT 1 FROM characters WHERE id=%d", char_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return false
	}
	defer sqlite.finalize(stmt)
	return sqlite.step(stmt) == .Row
}
