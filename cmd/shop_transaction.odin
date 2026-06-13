package cmd

import "core:fmt"
import "core:strings"
import "core:strconv"
import lib "../lib"
import sqlite "ext:sqlite3"

CoinPurse :: struct {
	pp, gp, ep, sp, cp: int,
}

// ----- coin helpers (work for characters and shops) -----

read_coins_from_table :: proc(db: ^lib.Db, table: string, id_col: string, id: int) -> (CoinPurse, bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT platinum, gold, electrum, silver, copper FROM %s WHERE %s=%d", table, id_col, id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return {}, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return CoinPurse{
			pp = int(sqlite.column_int(stmt, 0)),
			gp = int(sqlite.column_int(stmt, 1)),
			ep = int(sqlite.column_int(stmt, 2)),
			sp = int(sqlite.column_int(stmt, 3)),
			cp = int(sqlite.column_int(stmt, 4)),
		}, true
	}
	return {}, false
}

write_coins_to_table :: proc(db: ^lib.Db, table: string, id_col: string, id: int, coins: CoinPurse) -> bool {
	sql := fmt.tprintf(
		"UPDATE %s SET platinum=%d, gold=%d, electrum=%d, silver=%d, copper=%d WHERE %s=%d",
		table, coins.pp, coins.gp, coins.ep, coins.sp, coins.cp, id_col, id,
	)
	return lib.db_exec(db, sql) == lib.Error.None
}

coins_to_copper :: proc(c: CoinPurse) -> int {
	return c.pp * 1000 + c.gp * 100 + c.ep * 50 + c.sp * 10 + c.cp
}

copper_to_coins :: proc(total: int) -> CoinPurse {
	t := total
	c := CoinPurse{}
	c.pp = t / 1000; t %= 1000
	c.gp = t / 100;  t %= 100
	c.ep = t / 50;   t %= 50
	c.sp = t / 10;   t %= 10
	c.cp = t
	return c
}

read_character_coins :: proc(db: ^lib.Db, char_id: int) -> (CoinPurse, bool) {
	return read_coins_from_table(db, "characters", "id", char_id)
}

write_character_coins :: proc(db: ^lib.Db, char_id: int, coins: CoinPurse) -> bool {
	return write_coins_to_table(db, "characters", "id", char_id, coins)
}

read_shop_coins :: proc(db: ^lib.Db, shop_id: int) -> (CoinPurse, bool) {
	return read_coins_from_table(db, "shops", "id", shop_id)
}

write_shop_coins :: proc(db: ^lib.Db, shop_id: int, coins: CoinPurse) -> bool {
	return write_coins_to_table(db, "shops", "id", shop_id, coins)
}

deduct_coins :: proc(db: ^lib.Db, table: string, id_col: string, id: int, amount_cp: int) -> bool {
	coins, ok := read_coins_from_table(db, table, id_col, id)
	if !ok do return false

	total := coins_to_copper(coins)
	if total < amount_cp do return false

	new_coins := copper_to_coins(total - amount_cp)
	return write_coins_to_table(db, table, id_col, id, new_coins)
}

credit_coins :: proc(db: ^lib.Db, table: string, id_col: string, id: int, amount_cp: int) -> bool {
	coins, ok := read_coins_from_table(db, table, id_col, id)
	if !ok do return false

	new_coins := copper_to_coins(coins_to_copper(coins) + amount_cp)
	return write_coins_to_table(db, table, id_col, id, new_coins)
}

// ----- shop browse -----

shop_browse :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop browse <shop_id>"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop browse <shop_id>") }
		return 1
	}
	shop_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT si.item_id, i.name, si.quantity, si.price_gp, i.value_gp, i.item_type FROM shop_inventory si JOIN items i ON si.item_id=i.id WHERE si.shop_id=%d AND si.quantity > 0 ORDER BY i.name",
		shop_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to browse shop"}`) }
		else { fmt.eprintln("Failed to browse shop") }
		return 1
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		fmt.print("[")
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do fmt.print(",")
			first = false
			item_id := sqlite.column_int(stmt, 0)
			name := column_text_safe(stmt, 1)
			qty := sqlite.column_int(stmt, 2)
			price_gp := sqlite.column_double(stmt, 3)
			value_gp := sqlite.column_double(stmt, 4)
			item_type := column_text_safe(stmt, 5)
			effective_price := price_gp if price_gp > 0.0 else value_gp
			fmt.printf(`{{"item_id":%d,"name":"%s","quantity":%d,"price_gp":%.2f,"type":"%s"}}`,
				item_id, name, qty, effective_price, item_type)
		}
		fmt.println("]")
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			item_id := sqlite.column_int(stmt, 0)
			name := column_text_safe(stmt, 1)
			qty := sqlite.column_int(stmt, 2)
			price_gp := sqlite.column_double(stmt, 3)
			value_gp := sqlite.column_double(stmt, 4)
			effective_price := price_gp if price_gp > 0.0 else value_gp
			fmt.printf("  [%d] %s x%d — %.2f gp each\n", item_id, name, qty, effective_price)
		}
		if !has_any do fmt.println("  Shop has no items in stock.")
	}
	return 0
}

// ----- shop stock -----

shop_stock :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop stock <shop_id> <item_id> <quantity> [price_gp]"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop stock <shop_id> <item_id> <quantity> [price_gp]") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	item_id := strconv.atoi(args[2])
	qty := strconv.atoi(args[3])
	price_gp := 0.0
	if len(args) >= 5 {
		price_gp = strconv.parse_f64(args[4]) or_else 0.0
	}

	sql := fmt.tprintf(
		"INSERT OR REPLACE INTO shop_inventory (shop_id, item_id, quantity, price_gp) VALUES(%d, %d, %d, %f)",
		shop_id, item_id, qty, price_gp,
	)
	if lib.db_exec(db, sql) != lib.Error.None {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to stock item"}`) }
		else { fmt.eprintln("Failed to stock item") }
		return 1
	}

	if db.is_json { fmt.printf(`{{"success":true,"message":"Stocked item","shop_id":%d,"item_id":%d,"quantity":%d,"price_gp":%.2f}}` + "\n", shop_id, item_id, qty, price_gp) }
	else { fmt.printf("Stocked item %d in shop %d: qty %d, price %.2f gp\n", item_id, shop_id, qty, price_gp) }
	return 0
}

// ----- shop buy (character pays shop) -----

shop_buy :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop buy <shop_id> <char_id> <item_id> <quantity>"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop buy <shop_id> <char_id> <item_id> <quantity>") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	char_id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	qty := strconv.atoi(args[4])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
"SELECT si.quantity, si.price_gp, i.value_gp, i.name, s.scale FROM shop_inventory si JOIN items i ON si.item_id=i.id JOIN shops s ON si.shop_id=s.id WHERE si.shop_id=%d AND si.item_id=%d",
		shop_id, item_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to look up shop item"}`) }
		else { fmt.eprintln("Failed to look up shop item") }
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json { fmt.println(`{"success":false,"error":"Item not available in shop"}`) }
		else { fmt.eprintln("Item not available in shop") }
		return 1
	}
	stock_qty := int(sqlite.column_int(stmt, 0))
	stock_price := sqlite.column_double(stmt, 1)
	base_value := sqlite.column_double(stmt, 2)
	item_name := column_text_safe(stmt, 3)
	shop_scale := column_text_safe(stmt, 4)
	_, _, max_item := shop_scale_params(shop_scale)
	if max_item > 0 && base_value > f64(max_item) {
		if db.is_json { fmt.println(`{"success":false,"error":"Item value exceeds shop scale limit"}`) }
		else { fmt.eprintln("This shop does not deal in items of that value") }
		return 1
	}

	if stock_qty < qty {
		if db.is_json { fmt.println(`{"success":false,"error":"Insufficient stock"}`) }
		else { fmt.eprintln("Insufficient stock in shop") }
		return 1
	}

	unit_price := stock_price if stock_price > 0.0 else base_value
	total_price_cp := int(unit_price * f64(qty) * 100.0)

	// Character pays shop
	if !deduct_coins(db, "characters", "id", char_id, total_price_cp) {
		if db.is_json { fmt.println(`{"success":false,"error":"Insufficient funds"}`) }
		else { fmt.eprintln("Insufficient funds to purchase") }
		return 1
	}
	credit_coins(db, "shops", "id", shop_id, total_price_cp)

	// Decrement shop stock
	new_qty := stock_qty - qty
	if new_qty <= 0 {
		lib.db_exec(db, fmt.tprintf("DELETE FROM shop_inventory WHERE shop_id=%d AND item_id=%d", shop_id, item_id))
	} else {
		lib.db_exec(db, fmt.tprintf("UPDATE shop_inventory SET quantity=%d WHERE shop_id=%d AND item_id=%d", new_qty, shop_id, item_id))
	}

	inv_sql := fmt.tprintf("INSERT INTO inventory (character_id, item_id, quantity) VALUES(%d, %d, %d)", char_id, item_id, qty)
	lib.db_exec(db, inv_sql)

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Purchased %d x %s","item":"%s","quantity":%d,"total_price_gp":%.2f}}` + "\n",
			qty, item_name, item_name, qty, f64(total_price_cp) / 100.0)
	} else {
		fmt.printf("Bought %d x %s for %.2f gp\n", qty, item_name, f64(total_price_cp) / 100.0)
	}
	return 0
}

// ----- shop sell (shop pays character) -----

shop_sell :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop sell <shop_id> <char_id> <item_id> <quantity>"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop sell <shop_id> <char_id> <item_id> <quantity>") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	char_id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	qty := strconv.atoi(args[4])

	stmt: ^sqlite.Statement
	check_sql := fmt.tprintf(
		"SELECT inv.quantity, i.value_gp, i.name FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.character_id=%d AND inv.item_id=%d",
		char_id, item_id,
	)
	check_sql_c := cstring(raw_data(check_sql))
	if sqlite.prepare(db.ptr, check_sql_c, i32(len(check_sql)), &stmt, nil) != .Ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to check inventory"}`) }
		else { fmt.eprintln("Failed to check inventory") }
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json { fmt.println(`{"success":false,"error":"Item not in character inventory"}`) }
		else { fmt.eprintln("Item not in character inventory") }
		return 1
	}
	owned_qty := int(sqlite.column_int(stmt, 0))
	base_value := sqlite.column_double(stmt, 1)
	item_name := column_text_safe(stmt, 2)

	if owned_qty < qty {
		if db.is_json { fmt.println(`{"success":false,"error":"Insufficient quantity owned"}`) }
		else { fmt.eprintln("Insufficient quantity in inventory") }
		return 1
	}

	_, buyback_pct, _ := shop_scale_params(read_shop_scale(db, shop_id))
	sell_price_cp := int(base_value * f64(qty) * f64(buyback_pct))

	// Shop pays character
	if !deduct_coins(db, "shops", "id", shop_id, sell_price_cp) {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop has insufficient funds to buy"}`) }
		else { fmt.eprintln("Shop has insufficient funds to buy this item") }
		return 1
	}
	credit_coins(db, "characters", "id", char_id, sell_price_cp)

	// Remove from character inventory
	remove_sql := fmt.tprintf("UPDATE inventory SET quantity=quantity-%d WHERE character_id=%d AND item_id=%d", qty, char_id, item_id)
	lib.db_exec(db, remove_sql)
	lib.db_exec(db, "DELETE FROM inventory WHERE quantity <= 0")

	// Add to shop stock
	stock_sql := fmt.tprintf(
		"INSERT INTO shop_inventory (shop_id, item_id, quantity, price_gp) VALUES(%d, %d, %d, 0.0) ON CONFLICT(shop_id, item_id) DO UPDATE SET quantity=quantity+%d",
		shop_id, item_id, qty, qty,
	)
	lib.db_exec(db, stock_sql)

	if db.is_json {
		fmt.printf(`{{"success":true,"message":"Sold %d x %s","item":"%s","quantity":%d,"sell_price_gp":%.2f}}` + "\n",
			qty, item_name, item_name, qty, f64(sell_price_cp) / 100.0)
	} else {
		fmt.printf("Sold %d x %s for %.2f gp\n", qty, item_name, f64(sell_price_cp) / 100.0)
	}
	return 0
}

// ----- shop money management (DM sets shop treasury) -----

shop_add_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop add-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop add-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])
	pp := 0; if len(args) >= 6 do pp = strconv.atoi(args[5])
	ep := 0; if len(args) >= 7 do ep = strconv.atoi(args[6])

	total_cp := pp * 1000 + gp * 100 + ep * 50 + sp * 10 + cp
	if !credit_coins(db, "shops", "id", shop_id, total_cp) {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to add money"}`) }
		else { fmt.eprintln("Failed to add money to shop") }
		return 1
	}

	if db.is_json { fmt.printf(`{{"success":true,"message":"Added money to shop","shop_id":%d,"gold":%d,"silver":%d,"copper":%d}}` + "\n", shop_id, gp, sp, cp) }
	else { fmt.printf("Added %d GP, %d SP, %d CP to shop %d\n", gp, sp, cp, shop_id) }
	return 0
}

shop_remove_money :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 5 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop remove-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop remove-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	gp := strconv.atoi(args[2])
	sp := strconv.atoi(args[3])
	cp := strconv.atoi(args[4])
	pp := 0; if len(args) >= 6 do pp = strconv.atoi(args[5])
	ep := 0; if len(args) >= 7 do ep = strconv.atoi(args[6])

	total_cp := pp * 1000 + gp * 100 + ep * 50 + sp * 10 + cp
	if !deduct_coins(db, "shops", "id", shop_id, total_cp) {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop has insufficient funds"}`) }
		else { fmt.eprintln("Shop has insufficient funds") }
		return 1
	}

	if db.is_json { fmt.printf(`{{"success":true,"message":"Removed money from shop","shop_id":%d,"gold":%d,"silver":%d,"copper":%d}}` + "\n", shop_id, gp, sp, cp) }
	else { fmt.printf("Removed %d GP, %d SP, %d CP from shop %d\n", gp, sp, cp, shop_id) }
	return 0
}

// Show shop details including treasury and proprietor
shop_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop get <shop_id>"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop get <shop_id>") }
		return 1
	}
	shop_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT s.name, s.description, s.npc_id, s.scale, s.open_hours, s.gold, s.silver, s.copper, s.platinum, s.electrum, l.name FROM shops s JOIN locations l ON s.location_id=l.id WHERE s.id=%d",
		shop_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to get shop"}`) }
		else { fmt.eprintln("Failed to get shop") }
		return 1
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop not found"}`) }
		else { fmt.eprintln("Shop not found") }
		return 1
	}

	shop_name := column_text_safe(stmt, 0)
	desc := column_text_safe(stmt, 1)
	npc_id := int(sqlite.column_int(stmt, 2))
	scale := column_text_safe(stmt, 3)
	hours := column_text_safe(stmt, 4)
	s_gp := int(sqlite.column_int(stmt, 5))
	s_sp := int(sqlite.column_int(stmt, 6))
	s_cp := int(sqlite.column_int(stmt, 7))
	s_pp := int(sqlite.column_int(stmt, 8))
	s_ep := int(sqlite.column_int(stmt, 9))
	loc_name := column_text_safe(stmt, 10)

	if db.is_json {
		fmt.printf(`{{"id":%d,"name":"%s","description":"%s","location":"%s","npc_id":%d,"scale":"%s","open_hours":"%s","treasury":{"platinum":%d,"gold":%d,"electrum":%d,"silver":%d,"copper":%d}}}` + "\n",
			shop_id, shop_name, desc, loc_name, npc_id, scale, hours, s_pp, s_gp, s_ep, s_sp, s_cp)
	} else {
		fmt.printf("[%d] %s\n", shop_id, shop_name)
		fmt.printf("  Location: %s | Scale: %s | Hours: %s\n", loc_name, scale, hours)
		fmt.printf("  Owner NPC: %d\n", npc_id)
		fmt.printf("  Treasury: %d PP, %d GP, %d EP, %d SP, %d CP\n", s_pp, s_gp, s_ep, s_sp, s_cp)
		if len(desc) > 0 do fmt.printf("  %s\n", desc)
	}
	return 0
}

// ----- shop scale economy -----

shop_scale_params :: proc(scale: string) -> (treasury_gp: int, buyback_pct: int, max_item_value_gp: int) {
	switch scale {
	case "low":    return 50, 30, 50
	case "mid":    return 500, 50, 500
	case "high":   return 2000, 60, 5000
	case "luxury": return 10000, 70, 0
	}
	return 500, 50, 500  // default to mid
}

read_shop_scale :: proc(db: ^lib.Db, shop_id: int) -> string {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT scale FROM shops WHERE id=%d", shop_id)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return "mid"
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return strings.clone(column_text_safe(stmt, 0), context.temp_allocator)
	}
	return "mid"
}

// ----- haggle / barter -----

HaggleContext :: struct {
	npc_id: int,
	in_game_day: int,
	stock_qty: int,
	unit_price: f64,
	item_name: string,
}

// O(1) single-query lookup for all haggle prerequisites.
lookup_haggle_context :: proc(db: ^lib.Db, shop_id: int, item_id: int) -> (ctx: HaggleContext, ok: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT s.npc_id, COALESCE(c.in_game_day, 0), si.quantity, si.price_gp, i.value_gp, i.name FROM shops s JOIN locations l ON s.location_id=l.id LEFT JOIN campaigns c ON l.campaign_id=c.id JOIN shop_inventory si ON si.shop_id=s.id JOIN items i ON si.item_id=i.id WHERE s.id=%d AND si.item_id=%d",
		shop_id, item_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return {}, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) != .Row {
		return {}, false
	}

	ctx.npc_id = int(sqlite.column_int(stmt, 0))
	ctx.in_game_day = int(sqlite.column_int(stmt, 1))
	ctx.stock_qty = int(sqlite.column_int(stmt, 2))
	stock_price := sqlite.column_double(stmt, 3)
	base_value := sqlite.column_double(stmt, 4)
	ctx.unit_price = stock_price if stock_price > 0.0 else base_value
	ctx.item_name = strings.clone(column_text_safe(stmt, 5), context.temp_allocator)
	return ctx, true
}

compute_haggle_dc :: proc(discount_pct: int, fail_streak: int, npc_standing: int) -> int {
	dc := 10 + (discount_pct / 5) + (fail_streak * 2) - (npc_standing / 20)
	if dc < 5 do return 5
	return dc
}

get_persuasion_mod :: proc(db: ^lib.Db, char_id: int) -> (int, bool) {
	stmt: ^sqlite.Statement
	cha_sql := fmt.tprintf("SELECT cha FROM characters WHERE id=%d", char_id)
	cha_sql_c := cstring(raw_data(cha_sql))
	if sqlite.prepare(db.ptr, cha_sql_c, i32(len(cha_sql)), &stmt, nil) != .Ok {
		return 0, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) != .Row {
		return 0, false
	}
	cha := int(sqlite.column_int(stmt, 0))

	skill_stmt: ^sqlite.Statement
	skill_sql := fmt.tprintf("SELECT proficiency_level FROM character_skills WHERE character_id=%d AND LOWER(skill_name)='persuasion'", char_id)
	skill_sql_c := cstring(raw_data(skill_sql))
	if sqlite.prepare(db.ptr, skill_sql_c, i32(len(skill_sql)), &skill_stmt, nil) != .Ok {
		return 0, false
	}
	defer sqlite.finalize(skill_stmt)
	prof_level := 0
	if sqlite.step(skill_stmt) == .Row {
		prof_level = int(sqlite.column_int(skill_stmt, 0))
	}

	total_level := 0
	lvl_stmt: ^sqlite.Statement
	lvl_sql := fmt.tprintf("SELECT COALESCE(SUM(level), 0) FROM character_classes WHERE character_id=%d", char_id)
	lvl_sql_c := cstring(raw_data(lvl_sql))
	if sqlite.prepare(db.ptr, lvl_sql_c, i32(len(lvl_sql)), &lvl_stmt, nil) == .Ok {
		if sqlite.step(lvl_stmt) == .Row {
			total_level = int(sqlite.column_int(lvl_stmt, 0))
		}
		sqlite.finalize(lvl_stmt)
	}

	cha_mod := get_ability_modifier(cha)
	prof_bonus := get_prof_bonus(total_level)
	return cha_mod + prof_level * prof_bonus, true
}

get_or_init_haggle_attempts :: proc(db: ^lib.Db, shop_id: int, char_id: int, in_game_day: int) -> (attempts_used: int, fail_streak: int, ok: bool) {
	stmt: ^sqlite.Statement
	sql := fmt.tprintf("SELECT attempts_used, fail_streak FROM haggle_attempts WHERE shop_id=%d AND character_id=%d AND in_game_day=%d", shop_id, char_id, in_game_day)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0, 0, false
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0)), int(sqlite.column_int(stmt, 1)), true
	}
	lib.db_exec(db, fmt.tprintf("INSERT OR IGNORE INTO haggle_attempts (shop_id, character_id, in_game_day, attempts_used, fail_streak) VALUES(%d, %d, %d, 0, 0)", shop_id, char_id, in_game_day))
	return 0, 0, true
}

update_npc_standing :: proc(db: ^lib.Db, char_id: int, npc_id: int, delta: int) -> bool {
	current := get_npc_standing(db, char_id, npc_id)
	new_standing := current + delta
	sql := fmt.tprintf("INSERT OR REPLACE INTO character_npc_standings (character_id, npc_id, standing) VALUES(%d, %d, %d)", char_id, npc_id, new_standing)
	return lib.db_exec(db, sql) == lib.Error.None
}

// execute_haggle_purchase completes the discounted transaction after a successful haggle roll.
execute_haggle_purchase :: proc(db: ^lib.Db, shop_id: int, char_id: int, item_id: int, qty: int, discount_pct: int, stock_qty: int, unit_price: f64, in_game_day: int, attempts_used: int) -> (ok: bool, total_price_cp: int) {
	discount_mult := f64(100 - discount_pct) / 100.0
	total_price_cp = int(unit_price * discount_mult * f64(qty) * 100.0)

	if !deduct_coins(db, "characters", "id", char_id, total_price_cp) {
		return false, 0
	}
	credit_coins(db, "shops", "id", shop_id, total_price_cp)

	new_qty := stock_qty - qty
	if new_qty <= 0 {
		lib.db_exec(db, fmt.tprintf("DELETE FROM shop_inventory WHERE shop_id=%d AND item_id=%d", shop_id, item_id))
	} else {
		lib.db_exec(db, fmt.tprintf("UPDATE shop_inventory SET quantity=%d WHERE shop_id=%d AND item_id=%d", new_qty, shop_id, item_id))
	}

	inv_sql := fmt.tprintf("INSERT INTO inventory (character_id, item_id, quantity) VALUES(%d, %d, %d)", char_id, item_id, qty)
	lib.db_exec(db, inv_sql)

	lib.db_exec(db, fmt.tprintf("UPDATE haggle_attempts SET attempts_used=%d, fail_streak=0 WHERE shop_id=%d AND character_id=%d AND in_game_day=%d", attempts_used + 1, shop_id, char_id, in_game_day))
	return true, total_price_cp
}

// record_haggle_failure updates attempts and optionally damages NPC standing on a critical fail.
record_haggle_failure :: proc(db: ^lib.Db, shop_id: int, char_id: int, npc_id: int, in_game_day: int, attempts_used: int, fail_streak: int, crit: bool) -> (new_attempts: int, standing_delta: int) {
	new_attempts = attempts_used + 1
	new_streak := fail_streak + 1
	standing_delta = 0

	if crit {
		d4_val, _ := resolve_amount("1d4")
		standing_delta = -d4_val
		update_npc_standing(db, char_id, npc_id, standing_delta)
	}

	lib.db_exec(db, fmt.tprintf("UPDATE haggle_attempts SET attempts_used=%d, fail_streak=%d WHERE shop_id=%d AND character_id=%d AND in_game_day=%d", new_attempts, new_streak, shop_id, char_id, in_game_day))
	return
}

shop_haggle :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 6 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: ttrpg-engine shop haggle <shop_id> <char_id> <item_id> <quantity> <discount_pct>"}`) }
		else { fmt.eprintln("Usage: ttrpg-engine shop haggle <shop_id> <char_id> <item_id> <quantity> <discount_pct>") }
		return 1
	}
	shop_id := strconv.atoi(args[1])
	char_id := strconv.atoi(args[2])
	item_id := strconv.atoi(args[3])
	qty := strconv.atoi(args[4])
	discount_pct := strconv.atoi(args[5])

	if discount_pct < 0 || discount_pct > 50 {
		if db.is_json { fmt.println(`{"success":false,"error":"Discount must be between 0 and 50 percent"}`) }
		else { fmt.eprintln("Discount must be between 0 and 50 percent") }
		return 1
	}

	ctx, ctx_ok := lookup_haggle_context(db, shop_id, item_id)
	if !ctx_ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop or item not found"}`) }
		else { fmt.eprintln("Shop or item not found") }
		return 1
	}
	if ctx.npc_id <= 0 {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop has no owner to haggle with"}`) }
		else { fmt.eprintln("Shop has no owner to haggle with") }
		return 1
	}
	if ctx.stock_qty < qty {
		if db.is_json { fmt.println(`{"success":false,"error":"Insufficient stock"}`) }
		else { fmt.eprintln("Insufficient stock in shop") }
		return 1
	}

	attempts_used, fail_streak, att_ok := get_or_init_haggle_attempts(db, shop_id, char_id, ctx.in_game_day)
	if !att_ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Failed to check haggle attempts"}`) }
		else { fmt.eprintln("Failed to check haggle attempts") }
		return 1
	}
	if attempts_used >= 3 {
		if db.is_json { fmt.println(`{"success":false,"error":"Shop owner refuses to haggle further today"}`) }
		else { fmt.eprintln("Shop owner refuses to haggle further today") }
		return 1
	}

	persuasion, pers_ok := get_persuasion_mod(db, char_id)
	if !pers_ok {
		if db.is_json { fmt.println(`{"success":false,"error":"Character not found"}`) }
		else { fmt.eprintln("Character not found") }
		return 1
	}

	npc_standing := get_npc_standing(db, char_id, ctx.npc_id)
	lib.db_exec(db, fmt.tprintf("UPDATE character_npc_standings SET last_interaction_day=%d WHERE character_id=%d AND npc_id=%d", ctx.in_game_day, char_id, ctx.npc_id))
	dc := compute_haggle_dc(discount_pct, fail_streak, npc_standing)

	_, total, _, _ := resolve_d20("d20")
	total += persuasion

	if total >= dc {
		ok, price_cp := execute_haggle_purchase(db, shop_id, char_id, item_id, qty, discount_pct, ctx.stock_qty, ctx.unit_price, ctx.in_game_day, attempts_used)
		if !ok {
			if db.is_json { fmt.println(`{"success":false,"error":"Insufficient funds for discounted price"}`) }
			else { fmt.eprintln("Insufficient funds even with discount") }
			return 1
		}
		remaining := 2 - attempts_used
		if db.is_json {
			fmt.printf(`{{"success":true,"result":"success","roll":%d,"dc":%d,"discount_pct":%d,"total_price_gp":%.2f,"attempts_remaining":%d}}` + "\n", total, dc, discount_pct, f64(price_cp) / 100.0, remaining)
		} else {
			fmt.printf("Haggle success! %d%% off — %d x %s for %.2f gp. (%d attempts left)\n", discount_pct, qty, ctx.item_name, f64(price_cp) / 100.0, remaining)
		}
		return 0
	}

	// Failure path
	crit := (dc - total >= 10)
	new_attempts, standing_delta := record_haggle_failure(db, shop_id, char_id, ctx.npc_id, ctx.in_game_day, attempts_used, fail_streak, crit)
	remaining := 3 - new_attempts

	if db.is_json {
		fmt.printf(`{{"success":true,"result":"failure","roll":%d,"dc":%d,"critical":%s,"attempts_remaining":%d,"standing_delta":%d}}` + "\n", total, dc, crit ? "true" : "false", remaining, standing_delta)
	} else {
		crit_text := ""
		if crit do crit_text = fmt.tprintf(" Critical fail! Standing with NPC reduced by %d.", -standing_delta)
		fmt.printf("Haggle failed — rolled %d vs DC %d.%s %d attempts left.\n", total, dc, crit_text, remaining)
	}
	return 0
}
