package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ActorStats :: struct {
    id: int,
    name: string,
    current_hp: int,
    max_hp: int,
    temp_hp: int,
    ac: int,
    str: int,
    dex: int,
    con: int,
    int_: int,
    wis: int,
    cha: int,
    proficiency: int,
    attack_bonus: int,
    resistances: string,
    vulnerabilities: string,
    immunities: string,
    concentrating: string,
}

get_actor_stats :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> (ActorStats, bool) {
    s: ActorStats
    table := ""
    atk_col := "0"
    switch actor_type {
    case "character": table = "characters"; atk_col = "0"
    case "npc":       table = "npcs";       atk_col = "COALESCE(attack_bonus,0)"
    case "creature":  table = "creatures";  atk_col = "COALESCE(attack_bonus,0)"
    case: return s, false
    }

    stmt: ^sqlite.Statement
    sql := fmt.tprintf(
        "SELECT name, current_hp, max_hp, COALESCE(temp_hp,0), ac, COALESCE(str,10), COALESCE(dex,10), COALESCE(con,10), COALESCE(int_,10), COALESCE(wis,10), COALESCE(cha,10), COALESCE(proficiency_bonus,0), %s, COALESCE(resistances,''), COALESCE(vulnerabilities,''), COALESCE(immunities,''), COALESCE(concentrating_on,'') FROM %s WHERE id=%d",
        atk_col, table, actor_id,
    )
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return s, false
    defer sqlite.finalize(stmt)

    if sqlite.step(stmt) != .Row do return s, false

    s.id = actor_id
    s.name = column_text_safe(stmt, 0)
    s.current_hp = int(sqlite.column_int(stmt, 1))
    s.max_hp = int(sqlite.column_int(stmt, 2))
    s.temp_hp = int(sqlite.column_int(stmt, 3))
    s.ac = int(sqlite.column_int(stmt, 4))
    s.str = int(sqlite.column_int(stmt, 5))
    s.dex = int(sqlite.column_int(stmt, 6))
    s.con = int(sqlite.column_int(stmt, 7))
    s.int_ = int(sqlite.column_int(stmt, 8))
    s.wis = int(sqlite.column_int(stmt, 9))
    s.cha = int(sqlite.column_int(stmt, 10))
    s.proficiency = int(sqlite.column_int(stmt, 11))
    s.attack_bonus = int(sqlite.column_int(stmt, 12))
    s.resistances = column_text_safe(stmt, 13)
    s.vulnerabilities = column_text_safe(stmt, 14)
    s.immunities = column_text_safe(stmt, 15)
    s.concentrating = column_text_safe(stmt, 16)
    return s, true
}

hp_update :: proc(db: ^lib.Db, actor_type: string, actor_id: int, new_hp: int) {
    table := ""
    switch actor_type {
    case "character": table = "characters"
    case "npc":       table = "npcs"
    case "creature":  table = "creatures"
    case: return
    }
    sql := fmt.tprintf("UPDATE %s SET current_hp=%d WHERE id=%d", table, new_hp, actor_id)
    lib.db_exec(db, sql)
}

has_damage_type :: proc(list: string, dtype: string) -> bool {
    if len(list) == 0 do return false
    return strings.contains(strings.to_lower(list), strings.to_lower(dtype))
}

attack_mod :: proc(s: ActorStats, ability: string) -> int {
    mod: int
    switch ability {
    case "str": mod = (s.str - 10) / 2
    case "dex": mod = (s.dex - 10) / 2
    case "con": mod = (s.con - 10) / 2
    case "int": mod = (s.int_ - 10) / 2
    case "wis": mod = (s.wis - 10) / 2
    case "cha": mod = (s.cha - 10) / 2
    }
    return s.proficiency + mod + s.attack_bonus
}

ability_mod :: proc(s: ActorStats, ability: string) -> int {
    switch ability {
    case "str": return (s.str - 10) / 2
    case "dex": return (s.dex - 10) / 2
    case "con": return (s.con - 10) / 2
    case "int": return (s.int_ - 10) / 2
    case "wis": return (s.wis - 10) / 2
    case "cha": return (s.cha - 10) / 2
    }
    return 0
}

get_active_encounter :: proc(db: ^lib.Db, campaign_id: int) -> (int, bool) {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT id FROM combat_encounters WHERE campaign_id=%d AND status='active' ORDER BY id DESC LIMIT 1", campaign_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return 0, false
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) == .Row do return int(sqlite.column_int(stmt, 0)), true
    return 0, false
}

encounter_exists :: proc(db: ^lib.Db, enc_id: int) -> bool {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT 1 FROM combat_encounters WHERE id=%d AND status='active'", enc_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
        row := sqlite.step(stmt) == .Row
        sqlite.finalize(stmt)
        return row
    }
    return false
}

is_participant :: proc(db: ^lib.Db, enc_id: int, actor_type: string, actor_id: int) -> bool {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT 1 FROM combat_participants WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d AND is_active=1", enc_id, escape_sql(actor_type), actor_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
        row := sqlite.step(stmt) == .Row
        sqlite.finalize(stmt)
        return row
    }
    return false
}

get_participant_position :: proc(db: ^lib.Db, enc_id: int, actor_type: string, actor_id: int) -> string {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT position FROM combat_participants WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row {
            pos := column_text_safe(stmt, 0)
            sqlite.finalize(stmt)
            return pos
        }
        sqlite.finalize(stmt)
    }
    return "melee"
}

get_current_actor :: proc(db: ^lib.Db, enc_id: int, turn: int) -> (string, int, string) {
    stmt: ^sqlite.Statement
    sel_sql := fmt.tprintf("SELECT actor_type, actor_id FROM combat_participants WHERE encounter_id=%d AND is_active=1 ORDER BY sort_order LIMIT 1 OFFSET %d", enc_id, turn)
    sel_c := cstring(raw_data(sel_sql))
    if sqlite.prepare(db.ptr, sel_c, i32(len(sel_sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row {
            atype := column_text_safe(stmt, 0)
            aid := int(sqlite.column_int(stmt, 1))
            sqlite.finalize(stmt)
            s, ok := get_actor_stats(db, atype, aid)
            if ok do return atype, aid, s.name
            return atype, aid, ""
        }
        sqlite.finalize(stmt)
    }
    return "", 0, ""
}

actor_table :: proc(actor_type: string) -> string {
    switch actor_type {
    case "character": return "characters"
    case "npc":       return "npcs"
    case "creature":  return "creatures"
    }
    return ""
}

set_participant_active :: proc(db: ^lib.Db, enc_id: int, actor_type: string, actor_id: int, active: bool) {
    flag := active ? 1 : 0
    sql := fmt.tprintf("UPDATE combat_participants SET is_active=%d WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", flag, enc_id, escape_sql(actor_type), actor_id)
    lib.db_exec(db, sql)
}

get_char_save_prof :: proc(db: ^lib.Db, char_id: int, ability: string) -> int {
    stmt: ^sqlite.Statement
    col := ""
    switch ability {
    case "str": col = "save_prof_str"
    case "dex": col = "save_prof_dex"
    case "con": col = "save_prof_con"
    case "int": col = "save_prof_int"
    case "wis": col = "save_prof_wis"
    case "cha": col = "save_prof_cha"
    case: return 0
    }
    sql := fmt.tprintf("SELECT COALESCE(%s,0) FROM characters WHERE id=%d", col, char_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row {
            val := int(sqlite.column_int(stmt, 0))
            sqlite.finalize(stmt)
            return val
        }
        sqlite.finalize(stmt)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat start <campaign_id> <location_id>
// ---------------------------------------------------------------------------
combat_start :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 3 {
        return print_error(db, "Usage: ttrpg-engine combat start <campaign_id> <location_id>")
    }
    campaign_id := strconv.atoi(args[1])
    location_id := strconv.atoi(args[2])

    if enc_id, ok := get_active_encounter(db, campaign_id); ok {
        if db.is_json {
            fmt.printf(`{{"success":false,"error":"Combat encounter %d is already active. End it first."}}` + "\n", enc_id)
        } else {
            fmt.eprintf("Combat encounter %d is already active. End it first.\n", enc_id)
        }
        return 1
    }

    lib.db_exec(db, fmt.tprintf("INSERT INTO combat_encounters (campaign_id, location_id) VALUES(%d, %d)", campaign_id, location_id))
    enc_id, _ := get_active_encounter(db, campaign_id)

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"campaign_id":%d,"location_id":%d}}` + "\n", enc_id, campaign_id, location_id)
    } else {
        fmt.printf("Combat encounter %d started. Use 'combat join %d ...' to add participants.\n", enc_id, enc_id)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat join <encounter_id> <char|npc|creature> <id> <initiative_roll> [initiative_mod] [position]
// ---------------------------------------------------------------------------
combat_join :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat join <encounter_id> <char|npc|creature> <id> <initiative_roll> [initiative_mod] [position]")
    }
    enc_id := strconv.atoi(args[1])
    actor_type := args[2]
    if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    init_roll, init_ok := roll_initiative(args[4])
    if !init_ok do return print_error(db, "Invalid initiative — expected dice spec like 1d20+3")
    init_mod := 0
    if len(args) >= 6 do init_mod = strconv.atoi(args[5])
    position := "melee"
    if len(args) >= 7 do position = args[6]

    if actor_type != "character" && actor_type != "npc" && actor_type != "creature" {
        return print_error(db, "Actor type must be 'character', 'npc', or 'creature'")
    }
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")

    s, ok := get_actor_stats(db, actor_type, actor_id)
    if !ok do return print_error(db, "Actor not found")
    _ = s

    sql := fmt.tprintf(
        "INSERT OR REPLACE INTO combat_participants (encounter_id, actor_type, actor_id, initiative_roll, initiative_mod, position) VALUES(%d, '%s', %d, %d, %d, '%s')",
        enc_id, escape_sql(actor_type), actor_id, init_roll, init_mod, escape_sql(position),
    )
    if lib.db_exec(db, sql) != lib.Error.None {
        return print_error(db, "Failed to add participant")
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor_type":"%s","actor_id":%d,"initiative":%d}}` + "\n", enc_id, actor_type, actor_id, init_roll)
    } else {
        fmt.printf("Added %s %d to combat %d (initiative %d)\n", actor_type, actor_id, enc_id, init_roll)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat join-all <encounter_id>
// ---------------------------------------------------------------------------
combat_join_all :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 2 {
        return print_error(db, "Usage: ttrpg-engine combat join-all <encounter_id>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")

    stmt: ^sqlite.Statement
    info_sql := fmt.tprintf("SELECT campaign_id, COALESCE(location_id,0) FROM combat_encounters WHERE id=%d", enc_id)
    info_c := cstring(raw_data(info_sql))
    if sqlite.prepare(db.ptr, info_c, i32(len(info_sql)), &stmt, nil) != .Ok do return print_error(db, "Encounter not found")
    if sqlite.step(stmt) != .Row { sqlite.finalize(stmt); return print_error(db, "Encounter not found") }
    campaign_id := int(sqlite.column_int(stmt, 0))
    location_id := int(sqlite.column_int(stmt, 1))
    sqlite.finalize(stmt)

    count := 0

    char_sql := fmt.tprintf("SELECT id, COALESCE(initiative,0) FROM characters WHERE campaign_id=%d AND combat=1", campaign_id)
    char_c := cstring(raw_data(char_sql))
    if sqlite.prepare(db.ptr, char_c, i32(len(char_sql)), &stmt, nil) == .Ok {
        for sqlite.step(stmt) == .Row {
            id := int(sqlite.column_int(stmt, 0))
            init := int(sqlite.column_int(stmt, 1))
            lib.db_exec(db, fmt.tprintf("INSERT OR IGNORE INTO combat_participants (encounter_id, actor_type, actor_id, initiative_roll, initiative_mod) VALUES(%d, 'character', %d, %d, 0)", enc_id, id, init))
            count += 1
        }
        sqlite.finalize(stmt)
    }

    if location_id > 0 {
        cr_sql := fmt.tprintf("SELECT id, COALESCE(initiative,0) FROM creatures WHERE (location_id=%d OR campaign_id=%d) AND combat=1", location_id, campaign_id)
        cr_c := cstring(raw_data(cr_sql))
        if sqlite.prepare(db.ptr, cr_c, i32(len(cr_sql)), &stmt, nil) == .Ok {
            for sqlite.step(stmt) == .Row {
                id := int(sqlite.column_int(stmt, 0))
                init := int(sqlite.column_int(stmt, 1))
                lib.db_exec(db, fmt.tprintf("INSERT OR IGNORE INTO combat_participants (encounter_id, actor_type, actor_id, initiative_roll, initiative_mod) VALUES(%d, 'creature', %d, %d, 0)", enc_id, id, init))
                count += 1
            }
            sqlite.finalize(stmt)
        }
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"participants_added":%d}}` + "\n", enc_id, count)
    } else {
        fmt.printf("Added %d participants to combat %d. Run 'combat init %d' to lock turn order.\n", count, enc_id, enc_id)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat init <encounter_id>
// ---------------------------------------------------------------------------
combat_init :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 2 {
        return print_error(db, "Usage: ttrpg-engine combat init <encounter_id>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")

    stmt: ^sqlite.Statement
    sel_sql := fmt.tprintf("SELECT id FROM combat_participants WHERE encounter_id=%d ORDER BY initiative_roll DESC, initiative_mod DESC", enc_id)
    sel_c := cstring(raw_data(sel_sql))
    if sqlite.prepare(db.ptr, sel_c, i32(len(sel_sql)), &stmt, nil) != .Ok do return print_error(db, "No participants")
    defer sqlite.finalize(stmt)

    order := 0
    for sqlite.step(stmt) == .Row {
        pid := int(sqlite.column_int(stmt, 0))
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET sort_order=%d WHERE id=%d", order, pid))
        order += 1
    }
    if order == 0 do return print_error(db, "No participants in encounter. Use 'combat join' first.")

    lib.db_exec(db, fmt.tprintf("UPDATE combat_encounters SET round=1, turn_index=0 WHERE id=%d", enc_id))

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"participants":%d,"round":1}}` + "\n", enc_id, order)
    } else {
        fmt.printf("Combat %d initialized: %d participants, turn order locked.\n", enc_id, order)
        combat_status(db, args) // reuse status display
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat next <encounter_id>
// ---------------------------------------------------------------------------
combat_next :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 2 {
        return print_error(db, "Usage: ttrpg-engine combat next <encounter_id>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")

    stmt: ^sqlite.Statement
    info_sql := fmt.tprintf("SELECT round, turn_index FROM combat_encounters WHERE id=%d", enc_id)
    info_c := cstring(raw_data(info_sql))
    if sqlite.prepare(db.ptr, info_c, i32(len(info_sql)), &stmt, nil) != .Ok do return print_error(db, "Encounter not found")
    if sqlite.step(stmt) != .Row { sqlite.finalize(stmt); return print_error(db, "Encounter not found") }
    round := int(sqlite.column_int(stmt, 0))
    turn := int(sqlite.column_int(stmt, 1))
    sqlite.finalize(stmt)

    cnt_sql := fmt.tprintf("SELECT COUNT(*) FROM combat_participants WHERE encounter_id=%d AND is_active=1", enc_id)
    cnt_c := cstring(raw_data(cnt_sql))
    count := 0
    if sqlite.prepare(db.ptr, cnt_c, i32(len(cnt_sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row do count = int(sqlite.column_int(stmt, 0))
        sqlite.finalize(stmt)
    }
    if count == 0 do return print_error(db, "No active participants")

    next_turn := turn + 1
    next_round := round
    if next_turn >= count {
        next_turn = 0
        next_round = round + 1
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET reaction_used=0 WHERE encounter_id=%d", enc_id))
    }

    lib.db_exec(db, fmt.tprintf("UPDATE combat_encounters SET round=%d, turn_index=%d WHERE id=%d", next_round, next_turn, enc_id))

    // Reset action/bonus for the new current actor
    atype, aid, _ := get_current_actor(db, enc_id, next_turn)
    if len(atype) > 0 {
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET action_used=0, bonus_action_used=0, attacks_used=0, movement_used=0 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(atype), aid))
    }

    ctype, cid, cname := get_current_actor(db, enc_id, next_turn)
    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"round":%d,"turn":%d,"current_actor":{"type":"%s","id":%d,"name":"%s"}}}` + "\n", enc_id, next_round, next_turn + 1, ctype, cid, escape_json_string(cname))
    } else {
        fmt.printf("Round %d, turn %d: %s (%s %d)\n", next_round, next_turn + 1, cname, ctype, cid)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <attack_roll> [ability] [adv|disadv]
// ---------------------------------------------------------------------------
combat_attack :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 7 {
        return print_error(db, "Usage: ttrpg-engine combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <attack_roll> [ability] [adv|disadv]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    att_type := args[2]; if att_type == "char" do att_type = "character"
    att_id := strconv.atoi(args[3])
    tgt_type := args[4]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[5])
    att_roll, att_ok := resolve_attack_roll(args[6])
    if !att_ok do return print_error(db, "Invalid attack roll — expected dice spec like d20+5")
    ability := "str"
    if len(args) >= 8 do ability = args[7]
    advantage := 0
    if len(args) >= 9 {
        if args[8] == "adv" || args[8] == "advantage" do advantage = 1
        else if args[8] == "disadv" || args[8] == "disadvantage" do advantage = -1
    }

    if !is_participant(db, enc_id, att_type, att_id) do return print_error(db, "Attacker is not in this combat")
    if !is_participant(db, enc_id, tgt_type, tgt_id) do return print_error(db, "Target is not in this combat")

    att_s, _ := get_actor_stats(db, att_type, att_id)
    tgt_s, _ := get_actor_stats(db, tgt_type, tgt_id)

    mod := attack_mod(att_s, ability)
    cover := 0
    if get_participant_position(db, enc_id, tgt_type, tgt_id) == "cover" do cover = 2
    total := att_roll + mod + cover
    hit := total >= tgt_s.ac

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"attacker":"%s","target":"%s","attack_roll":%d,"modifier":%d,"cover":%d,"total":%d,"target_ac":%d,"hit":%s}}` + "\n",
            enc_id, escape_json_string(att_s.name), escape_json_string(tgt_s.name), att_roll, mod, cover, total, tgt_s.ac, hit ? "true" : "false")
    } else {
        adv_str := ""
        if advantage == 1 { adv_str = " with advantage" } else if advantage == -1 { adv_str = " with disadvantage" }
        fmt.printf("%s attacks %s%s: %d + %d", att_s.name, tgt_s.name, adv_str, att_roll, mod)
        if cover > 0 do fmt.printf(" + %d (cover)", cover)
        fmt.printf(" = %d vs AC %d -> %s\n", total, tgt_s.ac, hit ? "HIT" : "MISS")
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat damage <encounter_id> <target_type> <target_id> <amount> <type> [source]
// ---------------------------------------------------------------------------
combat_damage :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 6 {
        return print_error(db, "Usage: ttrpg-engine combat damage <encounter_id> <target_type> <target_id> <amount> <type> [source]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    tgt_type := args[2]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[3])
    amount, amt_ok := resolve_amount(args[4])
    if !amt_ok do return print_error(db, "Invalid damage amount — expected dice spec like 2d6+3 or 8d6")
    dmg_type := args[5]
    source := ""; if len(args) >= 7 do source = args[6]

    if !is_participant(db, enc_id, tgt_type, tgt_id) do return print_error(db, "Target not in combat")
    s, _ := get_actor_stats(db, tgt_type, tgt_id)

    modified := amount
    status_str := ""
    if has_damage_type(s.immunities, dmg_type) { modified = 0; status_str = " (IMMUNE)" }
    else if has_damage_type(s.resistances, dmg_type) { modified = amount / 2; status_str = " (resistant)" }
    else if has_damage_type(s.vulnerabilities, dmg_type) { modified = amount * 2; status_str = " (vulnerable)" }

    remaining := modified
    table := actor_table(tgt_type)
    if s.temp_hp > 0 {
        if remaining <= s.temp_hp {
            lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp = temp_hp - %d WHERE id=%d", table, remaining, tgt_id))
            remaining = 0
        } else {
            remaining -= s.temp_hp
            lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp=0 WHERE id=%d", table, tgt_id))
        }
    }
    new_hp := s.current_hp - remaining
    hp_update(db, tgt_type, tgt_id, new_hp)

    conc_msg := ""
    if len(s.concentrating) > 0 && remaining > 0 {
        conc_passed, conc_log := roll_concentration_save(db, enc_id, tgt_type, tgt_id, remaining)
        _ = conc_passed
        conc_msg = fmt.tprintf(" | %s", conc_log)
    }
    death_msg := ""
    if new_hp <= 0 {
        set_participant_active(db, enc_id, tgt_type, tgt_id, false)
        if tgt_type == "character" do death_msg = " | Unconscious — death saves needed"
        else do death_msg = " | Killed"
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"target":"%s","raw_damage":%d,"modified_damage":%d,"type":"%s","new_hp":%d,"max_hp":%d}}` + "\n",
            enc_id, escape_json_string(s.name), amount, modified, dmg_type, new_hp, s.max_hp)
    } else {
        src_str := ""; if len(source) > 0 do src_str = fmt.tprintf(" from %s", source)
        fmt.printf("%s takes %d %s damage%s%s -> %d/%d HP%s%s\n", s.name, amount, dmg_type, status_str, src_str, new_hp, s.max_hp, conc_msg, death_msg)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat save <encounter_id> <actor_type> <actor_id> <ability> <save_roll> [dc] [adv|disadv]
// ---------------------------------------------------------------------------
combat_save :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 6 {
        return print_error(db, "Usage: ttrpg-engine combat save <encounter_id> <actor_type> <actor_id> <ability> <save_roll> [dc] [adv|disadv]")
    }
    enc_id := strconv.atoi(args[1])
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    ability := args[4]
    save_roll, save_ok := resolve_save_roll(args[5])
    if !save_ok do return print_error(db, "Invalid save roll — expected dice spec like d20")
    dc := 10; if len(args) >= 7 do dc = strconv.atoi(args[6])
    advantage := 0
    if len(args) >= 8 {
        if args[7] == "adv" || args[7] == "advantage" do advantage = 1
        else if args[7] == "disadv" || args[7] == "disadvantage" do advantage = -1
    }

    s, _ := get_actor_stats(db, actor_type, actor_id)
    mod := ability_mod(s, ability)
    prof := 0
    if actor_type == "character" do prof = get_char_save_prof(db, actor_id, ability)
    proficiency_bonus := prof * s.proficiency
    total := save_roll + mod + proficiency_bonus
    passed := total >= dc

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","ability":"%s","roll":%d,"mod":%d,"proficiency":%d,"total":%d,"dc":%d,"passed":%s}}` + "\n",
            enc_id, escape_json_string(s.name), ability, save_roll, mod, proficiency_bonus, total, dc, passed ? "true" : "false")
    } else {
        adv_str := ""
        if advantage == 1 { adv_str = " with advantage" } else if advantage == -1 { adv_str = " with disadvantage" }
        fmt.printf("%s %s save%s: %d + %d", s.name, ability, adv_str, save_roll, mod)
        if prof > 0 do fmt.printf(" + %d (prof)", proficiency_bonus)
        fmt.printf(" = %d vs DC %d -> %s\n", total, dc, passed ? "PASS" : "FAIL")
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat move <encounter_id> <actor_type> <actor_id> <position>
// ---------------------------------------------------------------------------
combat_move :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat move <encounter_id> <actor_type> <actor_id> <position>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    position := args[4]

    if !is_participant(db, enc_id, actor_type, actor_id) do return print_error(db, "Actor not in combat")

    old_pos := get_participant_position(db, enc_id, actor_type, actor_id)
    lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET position='%s' WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", escape_sql(position), enc_id, escape_sql(actor_type), actor_id))

    s, _ := get_actor_stats(db, actor_type, actor_id)
    flee_msg := ""
    if old_pos == "melee" && (position == "ranged" || position == "fleeing") do flee_msg = " | Opportunity attack possible"

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","old_position":"%s","new_position":"%s"}}` + "\n", enc_id, escape_json_string(s.name), old_pos, position)
    } else {
        fmt.printf("%s moves from %s to %s.%s\n", s.name, old_pos, position, flee_msg)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]
// ---------------------------------------------------------------------------
combat_condition :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]")
    }
    _ = strconv.atoi(args[1]) // enc_id validated by condition_add context
    tgt_type := args[2]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := args[3]
    name := args[4]
    dur_str: string
    save_dc_str: string
    save_ability: string

    if len(args) >= 6 do dur_str = args[5]
    else do dur_str = "0"
    if len(args) >= 7 do save_dc_str = args[6]
    else do save_dc_str = "0"
    if len(args) >= 8 do save_ability = args[7]
    else do save_ability = ""

    cond_args: [9]string = {tgt_type, fmt.tprintf("%d", tgt_id), name, "", dur_str, save_dc_str, save_ability, "rounds", ""}
    // Trim to non-empty tail
    cond_slice: [dynamic]string
    for i := 0; i < 8; i += 1 {
        append(&cond_slice, cond_args[i])
    }
    return condition_add(db, cond_slice[:])
}

// ---------------------------------------------------------------------------
// combat death-save <character_id> <roll>
// ---------------------------------------------------------------------------
combat_death_save :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 3 {
        return print_error(db, "Usage: ttrpg-engine combat death-save <character_id> <roll>")
    }
    char_id := strconv.atoi(args[1])
    roll, roll_ok := resolve_attack_roll(args[2])
    if !roll_ok do return print_error(db, "Invalid death save — expected dice spec like d20")

    stmt: ^sqlite.Statement
    sel_sql := fmt.tprintf("SELECT death_saves_success, death_saves_failure, current_hp FROM characters WHERE id=%d", char_id)
    sel_c := cstring(raw_data(sel_sql))
    if sqlite.prepare(db.ptr, sel_c, i32(len(sel_sql)), &stmt, nil) != .Ok do return print_error(db, "Character not found")
    if sqlite.step(stmt) != .Row { sqlite.finalize(stmt); return print_error(db, "Character not found") }
    successes := int(sqlite.column_int(stmt, 0))
    failures := int(sqlite.column_int(stmt, 1))
    hp := int(sqlite.column_int(stmt, 2))
    sqlite.finalize(stmt)

    if hp > 0 do return print_error(db, "Character is not at 0 HP")

    if roll == 20 {
        hp_update(db, "character", char_id, 1)
        lib.db_exec(db, fmt.tprintf("UPDATE characters SET death_saves_success=0, death_saves_failure=0 WHERE id=%d", char_id))
        if db.is_json { fmt.printf(`{{"success":true,"character_id":%d,"roll":20,"result":"nat20","hp":1}}` + "\n", char_id) }
        else { fmt.printf("Natural 20! Character %d regains 1 HP.\n", char_id) }
        return 0
    }
    if roll == 1 { failures += 2 }
    else if roll >= 10 { successes += 1 }
    else { failures += 1 }

    lib.db_exec(db, fmt.tprintf("UPDATE characters SET death_saves_success=%d, death_saves_failure=%d WHERE id=%d", successes, failures, char_id))

    outcome := ""
    if successes >= 3 {
        outcome = " — STABILIZED"
        lib.db_exec(db, fmt.tprintf("UPDATE characters SET death_saves_success=0, death_saves_failure=0 WHERE id=%d", char_id))
    } else if failures >= 3 {
        outcome = " — DEAD"
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"character_id":%d,"roll":%d,"successes":%d,"failures":%d}}` + "\n", char_id, roll, successes, failures)
    } else {
        fmt.printf("Death save %d: %d successes, %d failures%s\n", roll, successes, failures, outcome)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]
// ---------------------------------------------------------------------------
combat_react :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    reaction := args[4]

    if !is_participant(db, enc_id, actor_type, actor_id) do return print_error(db, "Actor not in combat")

    stmt: ^sqlite.Statement
    chk_sql := fmt.tprintf("SELECT reaction_used FROM combat_participants WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id)
    chk_c := cstring(raw_data(chk_sql))
    if sqlite.prepare(db.ptr, chk_c, i32(len(chk_sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row && int(sqlite.column_int(stmt, 0)) != 0 {
            sqlite.finalize(stmt)
            return print_error(db, "Reaction already used this round")
        }
        sqlite.finalize(stmt)
    }

    lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET reaction_used=1 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id))

    s, _ := get_actor_stats(db, actor_type, actor_id)
    tgt_name := ""
    if len(args) >= 7 {
        tt := args[5]; if tt == "char" do tt = "character"
        ti := strconv.atoi(args[6])
        ts, tok := get_actor_stats(db, tt, ti)
        if tok do tgt_name = ts.name
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","reaction":"%s","target":"%s"}}` + "\n", enc_id, escape_json_string(s.name), reaction, escape_json_string(tgt_name))
    } else {
        ts := ""; if len(tgt_name) > 0 do ts = fmt.tprintf(" targeting %s", tgt_name)
        fmt.printf("%s uses reaction: %s%s.\n", s.name, reaction, ts)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat ready <encounter_id> <actor_type> <actor_id> "<action>" <trigger>
// ---------------------------------------------------------------------------
combat_ready :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 6 {
        return print_error(db, "Usage: ttrpg-engine combat ready <encounter_id> <actor_type> <actor_id> \"<action>\" <trigger>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    action_text := args[4]
    trigger := args[5]

    if !is_participant(db, enc_id, actor_type, actor_id) do return print_error(db, "Actor not in combat")

    readied := fmt.tprintf("%s | trigger: %s", action_text, trigger)
    lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET readied_action='%s', action_used=1 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", escape_sql(readied), enc_id, escape_sql(actor_type), actor_id))

    s, _ := get_actor_stats(db, actor_type, actor_id)
    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","readied":"%s","trigger":"%s"}}` + "\n", enc_id, escape_json_string(s.name), escape_json_string(action_text), escape_json_string(trigger))
    } else {
        fmt.printf("%s readies action: \"%s\" (trigger: %s)\n", s.name, action_text, trigger)
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat status <encounter_id>
// ---------------------------------------------------------------------------
combat_status :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 2 {
        return print_error(db, "Usage: ttrpg-engine combat status <encounter_id>")
    }
    enc_id := strconv.atoi(args[1])

    stmt: ^sqlite.Statement
    info_sql := fmt.tprintf("SELECT round, turn_index, status, campaign_id, COALESCE(location_id,0) FROM combat_encounters WHERE id=%d", enc_id)
    info_c := cstring(raw_data(info_sql))
    if sqlite.prepare(db.ptr, info_c, i32(len(info_sql)), &stmt, nil) != .Ok do return print_error(db, "Encounter not found")
    if sqlite.step(stmt) != .Row { sqlite.finalize(stmt); return print_error(db, "Encounter not found") }
    round := int(sqlite.column_int(stmt, 0))
    turn_idx := int(sqlite.column_int(stmt, 1))
    enc_status := column_text_safe(stmt, 2)
    campaign_id := int(sqlite.column_int(stmt, 3))
    location_id := int(sqlite.column_int(stmt, 4))
    sqlite.finalize(stmt)

    if db.is_json {
        fmt.print(`{"success":true`)
        fmt.printf(`,"encounter_id":%d,"round":%d,"turn":%d,"status":"%s","campaign_id":%d,"location_id":%d`,
            enc_id, round, turn_idx + 1, enc_status, campaign_id, location_id)
        fmt.print(`,"participants":[`)
    } else {
        fmt.println("================================================================================")
        fmt.printf("COMBAT STATUS — Round %d, Turn %d  (Status: %s)\n", round, turn_idx + 1, enc_status)
        fmt.println("================================================================================")
    }

    part_sql := fmt.tprintf("SELECT actor_type, actor_id, initiative_roll, sort_order, is_active, position, reaction_used, action_used, bonus_action_used, readied_action FROM combat_participants WHERE encounter_id=%d ORDER BY sort_order", enc_id)
    part_c := cstring(raw_data(part_sql))
    if sqlite.prepare(db.ptr, part_c, i32(len(part_sql)), &stmt, nil) == .Ok {
        defer sqlite.finalize(stmt)
        first := true
        for sqlite.step(stmt) == .Row {
            atype := column_text_safe(stmt, 0)
            aid := int(sqlite.column_int(stmt, 1))
            init := int(sqlite.column_int(stmt, 2))
            order := int(sqlite.column_int(stmt, 3))
            active := int(sqlite.column_int(stmt, 4)) != 0
            pos := column_text_safe(stmt, 5)
            react := int(sqlite.column_int(stmt, 6)) != 0
            act := int(sqlite.column_int(stmt, 7)) != 0
            ba := int(sqlite.column_int(stmt, 8)) != 0
            readied := column_text_safe(stmt, 9)

            s, _ := get_actor_stats(db, atype, aid)
            is_current := active && order == turn_idx

            if db.is_json {
                if !first do fmt.print(",")
                first = false
                fmt.printf(`{"actor_type":"%s","actor_id":%d,"name":"%s","initiative":%d,"sort_order":%d,"is_active":%s,"is_current":%s,"position":"%s","hp":%d,"max_hp":%d,"ac":%d,"reaction_used":%s,"action_used":%s,"bonus_action_used":%s,"readied_action":"%s"}`,
                    atype, aid, escape_json_string(s.name), init, order,
                    active ? "true" : "false", is_current ? "true" : "false",
                    pos, s.current_hp, s.max_hp, s.ac,
                    react ? "true" : "false", act ? "true" : "false", ba ? "true" : "false",
                    escape_json_string(readied))
            } else {
                marker := is_current ? ">" : " "
                dead := !active ? " [DOWN]" : ""
                flags := ""
                if act do flags = fmt.aprintf("%s [action]", flags)
                if ba do flags = fmt.aprintf("%s [BA]", flags)
                if react do flags = fmt.aprintf("%s [react]", flags)
                if len(readied) > 0 do flags = fmt.aprintf("%s [readied]", flags)
                fmt.printf("  %s #%d %s  HP:%d/%d AC:%d  %s%s%s\n",
                    marker, order + 1, s.name, s.current_hp, s.max_hp, s.ac, pos, dead, flags)
            }
        }
    }

    if db.is_json { fmt.print(`]}` + "\n") } else { fmt.println() }
    return 0
}

// ---------------------------------------------------------------------------
// combat end <encounter_id>
// ---------------------------------------------------------------------------
combat_end :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 2 {
        return print_error(db, "Usage: ttrpg-engine combat end <encounter_id>")
    }
    enc_id := strconv.atoi(args[1])

    lib.db_exec(db, fmt.tprintf("UPDATE combat_encounters SET status='ended' WHERE id=%d", enc_id))

    stmt: ^sqlite.Statement
    part_sql := fmt.tprintf("SELECT DISTINCT actor_id FROM combat_participants WHERE encounter_id=%d AND actor_type='character'", enc_id)
    part_c := cstring(raw_data(part_sql))
    if sqlite.prepare(db.ptr, part_c, i32(len(part_sql)), &stmt, nil) == .Ok {
        for sqlite.step(stmt) == .Row {
            char_id := int(sqlite.column_int(stmt, 0))
            lib.db_exec(db, fmt.tprintf("UPDATE characters SET combat=0 WHERE id=%d", char_id))
        }
        sqlite.finalize(stmt)
    }

    cnt_sql := fmt.tprintf("SELECT COUNT(*) FROM combat_participants WHERE encounter_id=%d", enc_id)
    cnt_c := cstring(raw_data(cnt_sql))
    count := 0
    if sqlite.prepare(db.ptr, cnt_c, i32(len(cnt_sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row do count = int(sqlite.column_int(stmt, 0))
        sqlite.finalize(stmt)
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"status":"ended","participants":%d}}` + "\n", enc_id, count)
    } else {
        fmt.printf("Combat encounter %d ended (%d participants).\n", enc_id, count)
    }
    return 0
}

// ---------------------------------------------------------------------------
// JSON / Text export for campaign get-story-state
// ---------------------------------------------------------------------------

print_json_combat :: proc(db: ^lib.Db, campaign_id: int) {
    stmt: ^sqlite.Statement
    enc_sql := fmt.tprintf("SELECT id, round, turn_index, COALESCE(location_id,0) FROM combat_encounters WHERE campaign_id=%d AND status='active' ORDER BY id DESC LIMIT 1", campaign_id)
    enc_c := cstring(raw_data(enc_sql))
    if sqlite.prepare(db.ptr, enc_c, i32(len(enc_sql)), &stmt, nil) != .Ok { fmt.print("null"); return }
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) != .Row { fmt.print("null"); return }

    enc_id := int(sqlite.column_int(stmt, 0))
    round := int(sqlite.column_int(stmt, 1))
    turn_idx := int(sqlite.column_int(stmt, 2))
    location_id := int(sqlite.column_int(stmt, 3))

    fmt.printf(`{"encounter_id":%d,"round":%d,"turn":%d,"location_id":%d,"current_turn":`, enc_id, round, turn_idx + 1, location_id)
    ctype, cid, cname := get_current_actor(db, enc_id, turn_idx)
    fmt.printf(`{"actor_type":"%s","actor_id":%d,"name":"%s"}`, ctype, cid, escape_json_string(cname))
    fmt.print(`,"participants":[`)

    part_sql := fmt.tprintf("SELECT actor_type, actor_id, initiative_roll, sort_order, is_active, position, reaction_used, action_used, bonus_action_used, readied_action FROM combat_participants WHERE encounter_id=%d ORDER BY sort_order", enc_id)
    part_c := cstring(raw_data(part_sql))
    if sqlite.prepare(db.ptr, part_c, i32(len(part_sql)), &stmt, nil) == .Ok {
        defer sqlite.finalize(stmt)
        first := true
        for sqlite.step(stmt) == .Row {
            if !first do fmt.print(",")
            first = false
            atype := column_text_safe(stmt, 0)
            aid := int(sqlite.column_int(stmt, 1))
            init := int(sqlite.column_int(stmt, 2))
            order := int(sqlite.column_int(stmt, 3))
            active := int(sqlite.column_int(stmt, 4)) != 0
            pos := column_text_safe(stmt, 5)
            react := int(sqlite.column_int(stmt, 6)) != 0
            act := int(sqlite.column_int(stmt, 7)) != 0
            ba := int(sqlite.column_int(stmt, 8)) != 0
            readied := column_text_safe(stmt, 9)
            s, _ := get_actor_stats(db, atype, aid)
            fmt.printf(`{"actor_type":"%s","actor_id":%d,"name":"%s","initiative":%d,"sort_order":%d,"is_active":%s,"is_current":%s,"position":"%s","hp":%d,"max_hp":%d,"ac":%d,"reaction_used":%s,"action_used":%s,"bonus_action_used":%s,"readied_action":"%s"}`,
                atype, aid, escape_json_string(s.name), init, order,
                active ? "true" : "false", (active && order == turn_idx) ? "true" : "false",
                pos, s.current_hp, s.max_hp, s.ac,
                react ? "true" : "false", act ? "true" : "false", ba ? "true" : "false",
                escape_json_string(readied))
        }
    }
    fmt.print(`]}`)
}

print_text_combat :: proc(db: ^lib.Db, campaign_id: int) {
    stmt: ^sqlite.Statement
    enc_sql := fmt.tprintf("SELECT id, round, turn_index FROM combat_encounters WHERE campaign_id=%d AND status='active' ORDER BY id DESC LIMIT 1", campaign_id)
    enc_c := cstring(raw_data(enc_sql))
    if sqlite.prepare(db.ptr, enc_c, i32(len(enc_sql)), &stmt, nil) != .Ok do return
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) != .Row do return

    enc_id := int(sqlite.column_int(stmt, 0))
    round := int(sqlite.column_int(stmt, 1))
    turn_idx := int(sqlite.column_int(stmt, 2))

    fmt.println("--------------------------------------------------------------------------------")
    fmt.printf("COMBAT — Round %d, Turn %d\n", round, turn_idx + 1)
    fmt.println("--------------------------------------------------------------------------------")

    part_sql := fmt.tprintf("SELECT actor_type, actor_id, initiative_roll, sort_order, is_active, position, reaction_used, action_used, readied_action FROM combat_participants WHERE encounter_id=%d ORDER BY sort_order", enc_id)
    part_c := cstring(raw_data(part_sql))
    if sqlite.prepare(db.ptr, part_c, i32(len(part_sql)), &stmt, nil) == .Ok {
        defer sqlite.finalize(stmt)
        for sqlite.step(stmt) == .Row {
            atype := column_text_safe(stmt, 0)
            aid := int(sqlite.column_int(stmt, 1))
            order := int(sqlite.column_int(stmt, 3))
            active := int(sqlite.column_int(stmt, 4)) != 0
            pos := column_text_safe(stmt, 5)
            react := int(sqlite.column_int(stmt, 6)) != 0
            readied := column_text_safe(stmt, 8)
            s, _ := get_actor_stats(db, atype, aid)
            marker := (active && order == turn_idx) ? " >" : "  "
            dead := !active ? " [DOWN]" : ""
            flags := ""
            if react do flags = " [react used]"
            if len(readied) > 0 do flags = fmt.aprintf("%s [readied]", flags)
            fmt.printf("  %s #%d %s  HP:%d/%d AC:%d  %s%s%s\n",
                marker, order + 1, s.name, s.current_hp, s.max_hp, s.ac, pos, dead, flags)
        }
    }
    fmt.println()
}

// ---------------------------------------------------------------------------
// Integration helpers — weapon lookup, skill mapping, multiattack, spell slots
// ---------------------------------------------------------------------------

get_equipped_weapon :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> (damage_dice: string, damage_type: string, magic_bonus: int, found: bool) {
    id_col := ""
    switch actor_type {
    case "character": id_col = "character_id"
    case "npc":       id_col = "npc_id"
    case "creature":  id_col = "creature_id"
    case: return "", "", 0, false
    }

    stmt: ^sqlite.Statement
    sql := fmt.tprintf(
        "SELECT i.damage_dice, i.damage_type, i.name, i.properties, i.description FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.%s=%d AND inv.equipped=1 AND (i.damage_dice != '' OR i.item_type='weapon') LIMIT 1",
        id_col, actor_id,
    )
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return "", "", 0, false
    defer sqlite.finalize(stmt)

    if sqlite.step(stmt) != .Row do return "", "", 0, false

    damage_dice = column_text_safe(stmt, 0)
    damage_type = column_text_safe(stmt, 1)
    name := column_text_safe(stmt, 2)
    props := column_text_safe(stmt, 3)
    desc := column_text_safe(stmt, 4)

    magic_bonus = get_string_magic_bonus(name)
    if magic_bonus == 0 do magic_bonus = get_string_magic_bonus(props)
    if magic_bonus == 0 do magic_bonus = get_string_magic_bonus(desc)

    return damage_dice, damage_type, magic_bonus, true
}

skill_ability :: proc(skill: string) -> string {
    switch strings.to_lower(skill) {
    case "athletics":      return "str"
    case "acrobatics", "sleight of hand", "stealth": return "dex"
    case "arcana", "history", "investigation", "nature", "religion": return "int"
    case "animal handling", "insight", "medicine", "perception", "survival": return "wis"
    case "deception", "intimidation", "performance", "persuasion": return "cha"
    }
    return "wis"
}

get_multiattack_count :: proc(db: ^lib.Db, actor_type: string, actor_id: int) -> int {
    table := ""
    switch actor_type {
    case "creature": table = "creatures"
    case "npc":      table = "npcs"
    case: return 1
    }

    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT COALESCE(multiattack_count,1) FROM %s WHERE id=%d", table, actor_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return 1
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) == .Row do return int(sqlite.column_int(stmt, 0))
    return 1
}

check_action_economy :: proc(db: ^lib.Db, enc_id: int, actor_type: string, actor_id: int, is_bonus: bool) -> bool {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT action_used, bonus_action_used, attacks_used FROM combat_participants WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return false
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) != .Row do return false

    action_used := int(sqlite.column_int(stmt, 0)) != 0
    bonus_used := int(sqlite.column_int(stmt, 1)) != 0
    attacks_used := int(sqlite.column_int(stmt, 2))

    if is_bonus {
        return !bonus_used
    }

    if action_used {
        max_attacks := get_multiattack_count(db, actor_type, actor_id)
        if attacks_used >= max_attacks do return false
    }
    return true
}

mark_action_used :: proc(db: ^lib.Db, enc_id: int, actor_type: string, actor_id: int, is_bonus: bool) {
    if is_bonus {
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET bonus_action_used=1 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id))
    } else {
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET action_used=1, attacks_used=attacks_used+1 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id))
    }
}

get_spell_slot_available :: proc(db: ^lib.Db, char_id: int, slot_level: int) -> (available: int, ok: bool) {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf("SELECT max_slots, used_slots FROM character_spell_slots WHERE character_id=%d AND slot_level=%d", char_id, slot_level)
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return 0, false
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) != .Row do return 0, false
    max_slots := int(sqlite.column_int(stmt, 0))
    used := int(sqlite.column_int(stmt, 1))
    return max_slots - used, true
}

consume_spell_slot :: proc(db: ^lib.Db, char_id: int, slot_level: int) -> bool {
    avail, ok := get_spell_slot_available(db, char_id, slot_level)
    if !ok || avail < 1 do return false
    sql := fmt.tprintf("UPDATE character_spell_slots SET used_slots = used_slots + 1 WHERE character_id=%d AND slot_level=%d", char_id, slot_level)
    lib.db_exec(db, sql)
    return true
}

get_character_spell :: proc(db: ^lib.Db, char_id: int, spell_name: string) -> (spell_id: int, prepared: bool, found: bool) {
    stmt: ^sqlite.Statement
    sql := fmt.tprintf(
        "SELECT cs.spell_id, cs.prepared FROM character_spells cs JOIN spells s ON cs.spell_id=s.id WHERE cs.character_id=%d AND LOWER(s.name)=LOWER('%s')",
        char_id, escape_sql(spell_name),
    )
    sql_c := cstring(raw_data(sql))
    if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok do return 0, false, false
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) == .Row {
        return int(sqlite.column_int(stmt, 0)), int(sqlite.column_int(stmt, 1)) != 0, true
    }
    return 0, false, false
}

// ---------------------------------------------------------------------------
// combat cast <encounter_id> <caster_type> <caster_id> <spell_name> <slot_level> <target_type> <target_id> [save_ability] [damage_dice] [dc_override]
// ---------------------------------------------------------------------------
combat_cast :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 8 {
        return print_error(db, "Usage: ttrpg-engine combat cast <encounter_id> <caster_type> <caster_id> <spell_name> <slot_level> <target_type> <target_id> [save_ability] [damage_dice] [dc_override]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    caster_type := args[2]; if caster_type == "char" do caster_type = "character"
    caster_id := strconv.atoi(args[3])
    spell_name := args[4]
    slot_level := strconv.atoi(args[5])
    tgt_type := args[6]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[7])
    save_ability := ""; if len(args) >= 9 do save_ability = args[8]
    damage_dice := ""; if len(args) >= 10 do damage_dice = args[9]
    dc_override := 0; if len(args) >= 11 do dc_override = strconv.atoi(args[10])

    if !is_participant(db, enc_id, caster_type, caster_id) do return print_error(db, "Caster is not in this combat")
    if !is_participant(db, enc_id, tgt_type, tgt_id) do return print_error(db, "Target is not in this combat")

    is_bonus := false
    if caster_type == "character" {
        _, prepared, spell_found := get_character_spell(db, caster_id, spell_name)
        if !spell_found do return print_error(db, "Spell not known by this character")
        if !prepared do return print_error(db, "Spell not prepared")

        if slot_level > 0 {
            avail, slot_ok := get_spell_slot_available(db, caster_id, slot_level)
            if !slot_ok || avail < 1 do return print_error(db, "No spell slots available at that level")
        }
    }

    if !check_action_economy(db, enc_id, caster_type, caster_id, is_bonus) {
        return print_error(db, "Action already used this turn")
    }

    mark_action_used(db, enc_id, caster_type, caster_id, is_bonus)

    if caster_type == "character" && slot_level > 0 {
        if !consume_spell_slot(db, caster_id, slot_level) {
            return print_error(db, "Failed to consume spell slot")
        }
    }

    caster_s, _ := get_actor_stats(db, caster_type, caster_id)
    tgt_s, _ := get_actor_stats(db, tgt_type, tgt_id)

    spell_attack := 0
    spell_dc := 0

    if caster_type == "character" {
        char, char_ok := fetch_character_stats(db, caster_id)
        if char_ok {
            spell_attack = char.spell_attack_bonus
            spell_dc = char.spell_save_dc
        }
    } else {
        spell_attack = caster_s.attack_bonus
        best_mod := ability_mod(caster_s, "int")
        if m := ability_mod(caster_s, "wis"); m > best_mod do best_mod = m
        if m := ability_mod(caster_s, "cha"); m > best_mod do best_mod = m
        spell_dc = 8 + caster_s.proficiency + best_mod
    }

    if dc_override > 0 do spell_dc = dc_override

    if len(save_ability) > 0 {
        tgt_mod := ability_mod(tgt_s, save_ability)
        tgt_prof := 0
        if tgt_type == "character" do tgt_prof = get_char_save_prof(db, tgt_id, save_ability)
        save_roll, _ := resolve_attack_roll("d20")
        save_total := save_roll + tgt_mod + tgt_prof * tgt_s.proficiency
        passed := save_total >= spell_dc

        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"caster":"%s","spell":"%s","slot_level":%d,"target":"%s","save_ability":"%s","save_roll":%d,"save_dc":%d,"passed":%s,"spell_dc":%d}}` + "\n",
                enc_id, escape_json_string(caster_s.name), escape_json_string(spell_name), slot_level, escape_json_string(tgt_s.name), save_ability, save_total, spell_dc, passed ? "true" : "false", spell_dc)
        } else {
            fmt.printf("%s casts %s (level %d) on %s: %s save %d vs DC %d → %s\n",
                caster_s.name, spell_name, slot_level, tgt_s.name, save_ability, save_total, spell_dc, passed ? "FAILS" : "PASSES")
        }
    } else {
        att_roll, _ := resolve_attack_roll("d20")
        total := att_roll + spell_attack
        hit := total >= tgt_s.ac

        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"caster":"%s","spell":"%s","slot_level":%d,"target":"%s","attack_roll":%d,"spell_attack_bonus":%d,"total":%d,"target_ac":%d,"hit":%s}}` + "\n",
                enc_id, escape_json_string(caster_s.name), escape_json_string(spell_name), slot_level, escape_json_string(tgt_s.name), att_roll, spell_attack, total, tgt_s.ac, hit ? "true" : "false")
        } else {
            fmt.printf("%s casts %s (level %d) on %s: %d + %d = %d vs AC %d → %s\n",
                caster_s.name, spell_name, slot_level, tgt_s.name, att_roll, spell_attack, total, tgt_s.ac, hit ? "HIT" : "MISS")
        }
    }

    // Track concentration
    stmt: ^sqlite.Statement
    spell_sql := fmt.tprintf("SELECT duration FROM spells WHERE LOWER(name)=LOWER('%s')", escape_sql(spell_name))
    spell_c := cstring(raw_data(spell_sql))
    if sqlite.prepare(db.ptr, spell_c, i32(len(spell_sql)), &stmt, nil) == .Ok {
        if sqlite.step(stmt) == .Row {
            duration := column_text_safe(stmt, 0)
            if strings.contains(strings.to_lower(duration), "concentration") {
                table := actor_table(caster_type)
                if len(table) > 0 {
                    lib.db_exec(db, fmt.tprintf("UPDATE %s SET concentrating_on='%s' WHERE id=%d", table, escape_sql(spell_name), caster_id))
                    if !db.is_json do fmt.printf("  %s is now concentrating on %s.\n", caster_s.name, spell_name)
                }
            }
        }
        sqlite.finalize(stmt)
    }

    return 0
}

// ---------------------------------------------------------------------------
// combat check <encounter_id> <actor_type> <actor_id> <skill_name> [dc] [target_type] [target_id]
// ---------------------------------------------------------------------------
combat_check :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat check <encounter_id> <actor_type> <actor_id> <skill_name> [dc] [target_type] [target_id]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    skill_name := args[4]
    dc := 0; if len(args) >= 6 do dc = strconv.atoi(args[5])
    contest_type := ""; if len(args) >= 7 do contest_type = args[6]; if contest_type == "char" do contest_type = "character"
    contest_id := 0; if len(args) >= 8 do contest_id = strconv.atoi(args[7])

    if !is_participant(db, enc_id, actor_type, actor_id) do return print_error(db, "Actor not in combat")

    s, _ := get_actor_stats(db, actor_type, actor_id)
    ability := skill_ability(skill_name)
    mod := ability_mod(s, ability)

    prof_level := 0
    if actor_type == "character" {
        stmt: ^sqlite.Statement
        sk_sql := fmt.tprintf("SELECT proficiency_level FROM character_skills WHERE character_id=%d AND LOWER(skill_name)=LOWER('%s')", actor_id, escape_sql(skill_name))
        sk_c := cstring(raw_data(sk_sql))
        if sqlite.prepare(db.ptr, sk_c, i32(len(sk_sql)), &stmt, nil) == .Ok {
            if sqlite.step(stmt) == .Row do prof_level = int(sqlite.column_int(stmt, 0))
            sqlite.finalize(stmt)
        }
    }

    prof_bonus := s.proficiency * prof_level
    roll, _ := resolve_attack_roll("d20")
    total := roll + mod + prof_bonus

    if contest_id > 0 && len(contest_type) > 0 {
        cs, c_ok := get_actor_stats(db, contest_type, contest_id)
        if !c_ok do return print_error(db, "Contest target not found")

        c_mod := ability_mod(cs, ability)
        c_prof_level := 0
        if contest_type == "character" {
            stmt: ^sqlite.Statement
            sk_sql := fmt.tprintf("SELECT proficiency_level FROM character_skills WHERE character_id=%d AND LOWER(skill_name)=LOWER('%s')", contest_id, escape_sql(skill_name))
            sk_c := cstring(raw_data(sk_sql))
            if sqlite.prepare(db.ptr, sk_c, i32(len(sk_sql)), &stmt, nil) == .Ok {
                if sqlite.step(stmt) == .Row do c_prof_level = int(sqlite.column_int(stmt, 0))
                sqlite.finalize(stmt)
            }
        }
        c_prof_bonus := cs.proficiency * c_prof_level
        c_roll, _ := resolve_attack_roll("d20")
        c_total := c_roll + c_mod + c_prof_bonus

        success := total > c_total
        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","skill":"%s","roll":%d,"mod":%d,"prof":%d,"total":%d,"contest_actor":"%s","contest_roll":%d,"contest_mod":%d,"contest_prof":%d,"contest_total":%d,"won":%s}}` + "\n",
                enc_id, escape_json_string(s.name), skill_name, roll, mod, prof_bonus, total,
                escape_json_string(cs.name), c_roll, c_mod, c_prof_bonus, c_total, success ? "true" : "false")
        } else {
            fmt.printf("%s %s check: %d + %d + %d = %d vs %s %d + %d + %d = %d → %s\n",
                s.name, skill_name, roll, mod, prof_bonus, total,
                cs.name, c_roll, c_mod, c_prof_bonus, c_total, success ? "SUCCESS" : "FAILURE")
        }
    } else {
        passed := total >= dc
        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","skill":"%s","ability":"%s","roll":%d,"mod":%d,"prof":%d,"total":%d,"dc":%d,"passed":%s}}` + "\n",
                enc_id, escape_json_string(s.name), skill_name, ability, roll, mod, prof_bonus, total, dc, passed ? "true" : "false")
        } else {
            dc_str := dc > 0 ? fmt.tprintf(" vs DC %d", dc) : ""
            fmt.printf("%s %s check (%s): %d + %d + %d = %d%s → %s\n",
                s.name, skill_name, ability, roll, mod, prof_bonus, total, dc_str,
                dc > 0 ? (passed ? "PASS" : "FAIL") : fmt.tprintf("%d", total))
        }
    }
    return 0
}

// ---------------------------------------------------------------------------
// combat strike <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> [ability] [bonus_action]
// Auto-looks-up equipped weapon, rolls attack + damage in one command.
// ---------------------------------------------------------------------------
combat_strike :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 6 {
        return print_error(db, "Usage: ttrpg-engine combat strike <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> [ability] [bonus_action]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    att_type := args[2]; if att_type == "char" do att_type = "character"
    att_id := strconv.atoi(args[3])
    tgt_type := args[4]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[5])
    ability := ""; if len(args) >= 7 do ability = args[6]
    is_bonus := false; if len(args) >= 8 && (args[7] == "bonus" || args[7] == "ba") do is_bonus = true

    if !is_participant(db, enc_id, att_type, att_id) do return print_error(db, "Attacker is not in this combat")
    if !is_participant(db, enc_id, tgt_type, tgt_id) do return print_error(db, "Target is not in this combat")

    if !check_action_economy(db, enc_id, att_type, att_id, is_bonus) {
        return print_error(db, is_bonus ? "Bonus action already used" : "No actions remaining this turn")
    }

    att_s, _ := get_actor_stats(db, att_type, att_id)
    tgt_s, _ := get_actor_stats(db, tgt_type, tgt_id)

    dmg_dice, dmg_type, magic_bonus, has_weapon := get_equipped_weapon(db, att_type, att_id)

    if len(ability) == 0 && has_weapon {
        ability = "str"
        id_col := att_type == "character" ? "character_id" : att_type == "npc" ? "npc_id" : "creature_id"
        stmt: ^sqlite.Statement
        prop_sql := fmt.tprintf("SELECT i.properties FROM inventory inv JOIN items i ON inv.item_id=i.id WHERE inv.%s=%d AND inv.equipped=1 AND (i.damage_dice != '' OR i.item_type='weapon') LIMIT 1", id_col, att_id)
        prop_c := cstring(raw_data(prop_sql))
        if sqlite.prepare(db.ptr, prop_c, i32(len(prop_sql)), &stmt, nil) == .Ok {
            if sqlite.step(stmt) == .Row {
                props := column_text_safe(stmt, 0)
                if strings.contains(strings.to_lower(props), "finesse") {
                    dex_mod := (att_s.dex - 10) / 2
                    str_mod := (att_s.str - 10) / 2
                    if dex_mod >= str_mod do ability = "dex"
                } else if strings.contains(strings.to_lower(props), "ranged") {
                    ability = "dex"
                }
            }
            sqlite.finalize(stmt)
        }
    }
    if len(ability) == 0 do ability = "str"

    mod := attack_mod(att_s, ability)
    cover := 0
    if get_participant_position(db, enc_id, tgt_type, tgt_id) == "cover" do cover = 2

    att_roll, _ := resolve_attack_roll("d20")
    total := att_roll + mod + cover + magic_bonus
    hit := total >= tgt_s.ac

    mark_action_used(db, enc_id, att_type, att_id, is_bonus)

    if !hit {
        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"attacker":"%s","target":"%s","attack_roll":%d,"modifier":%d,"total":%d,"target_ac":%d,"hit":false}}` + "\n",
                enc_id, escape_json_string(att_s.name), escape_json_string(tgt_s.name), att_roll, mod, total, tgt_s.ac)
        } else {
            fmt.printf("%s attacks %s: %d + %d = %d vs AC %d → MISS\n",
                att_s.name, tgt_s.name, att_roll, mod, total, tgt_s.ac)
        }
        return 0
    }

    // Roll damage
    ab_mod := (att_s.str - 10) / 2
    if ability == "dex" do ab_mod = (att_s.dex - 10) / 2

    if has_weapon {
        dmg, _ := resolve_amount(dmg_dice)
        dmg += ab_mod + magic_bonus

        modified := dmg
        status_str := ""
        if has_damage_type(tgt_s.immunities, dmg_type) { modified = 0; status_str = " (IMMUNE)" }
        else if has_damage_type(tgt_s.resistances, dmg_type) { modified = dmg / 2; status_str = " (resistant)" }
        else if has_damage_type(tgt_s.vulnerabilities, dmg_type) { modified = dmg * 2; status_str = " (vulnerable)" }

        remaining := modified
        table := actor_table(tgt_type)
        if tgt_s.temp_hp > 0 {
            if remaining <= tgt_s.temp_hp {
                lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp = temp_hp - %d WHERE id=%d", table, remaining, tgt_id))
                remaining = 0
            } else {
                remaining -= tgt_s.temp_hp
                lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp=0 WHERE id=%d", table, tgt_id))
            }
        }
        new_hp := tgt_s.current_hp - remaining
        hp_update(db, tgt_type, tgt_id, new_hp)

        conc_msg := ""
        if len(tgt_s.concentrating) > 0 && remaining > 0 {
            conc_passed, conc_log := roll_concentration_save(db, enc_id, tgt_type, tgt_id, remaining)
            _ = conc_passed
            conc_msg = fmt.tprintf(" | %s", conc_log)
        }
        death_msg := ""
        if new_hp <= 0 {
            set_participant_active(db, enc_id, tgt_type, tgt_id, false)
            if tgt_type == "character" do death_msg = " | Unconscious — death saves needed"
            else do death_msg = " | Killed"
        }

        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"attacker":"%s","target":"%s","attack_roll":%d,"modifier":%d,"total":%d,"target_ac":%d,"hit":true,"damage_dice":"%s","damage":%d,"damage_type":"%s","modified_damage":%d,"new_hp":%d,"max_hp":%d}}` + "\n",
                enc_id, escape_json_string(att_s.name), escape_json_string(tgt_s.name), att_roll, mod, total, tgt_s.ac, dmg_dice, dmg, dmg_type, modified, new_hp, tgt_s.max_hp)
        } else {
            fmt.printf("%s hits %s: %d + %d = %d vs AC %d → HIT | %d %s%s → %d/%d HP%s%s\n",
                att_s.name, tgt_s.name, att_roll, mod, total, tgt_s.ac, dmg, dmg_type, status_str, new_hp, tgt_s.max_hp, conc_msg, death_msg)
        }
    } else {
        unarmed := 1 + ab_mod
        if unarmed < 1 do unarmed = 1

        remaining := unarmed
        table := actor_table(tgt_type)
        if tgt_s.temp_hp > 0 {
            if remaining <= tgt_s.temp_hp {
                lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp = temp_hp - %d WHERE id=%d", table, remaining, tgt_id))
                remaining = 0
            } else {
                remaining -= tgt_s.temp_hp
                lib.db_exec(db, fmt.tprintf("UPDATE %s SET temp_hp=0 WHERE id=%d", table, tgt_id))
            }
        }
        new_hp := tgt_s.current_hp - remaining
        hp_update(db, tgt_type, tgt_id, new_hp)

        death_msg := ""
        if new_hp <= 0 {
            set_participant_active(db, enc_id, tgt_type, tgt_id, false)
            if tgt_type == "character" do death_msg = " | Unconscious — death saves needed"
            else do death_msg = " | Killed"
        }

        if db.is_json {
            fmt.printf(`{{"success":true,"encounter_id":%d,"attacker":"%s","target":"%s","attack_roll":%d,"modifier":%d,"total":%d,"target_ac":%d,"hit":true,"damage":%d,"damage_type":"bludgeoning","new_hp":%d,"max_hp":%d}}` + "\n",
                enc_id, escape_json_string(att_s.name), escape_json_string(tgt_s.name), att_roll, mod, total, tgt_s.ac, unarmed, new_hp, tgt_s.max_hp)
        } else {
            fmt.printf("%s hits %s with unarmed strike: %d bludgeoning → %d/%d HP%s\n",
                att_s.name, tgt_s.name, unarmed, new_hp, tgt_s.max_hp, death_msg)
        }
    }
    return 0
}

// ---------------------------------------------------------------------------
// Concentration auto-roll — called from combat_damage and combat_strike
// ---------------------------------------------------------------------------
roll_concentration_save :: proc(db: ^lib.Db, enc_id: int, tgt_type: string, tgt_id: int, damage_taken: int) -> (passed: bool, log_msg: string) {
    s, ok := get_actor_stats(db, tgt_type, tgt_id)
    if !ok || len(s.concentrating) == 0 || damage_taken <= 0 do return true, ""

    dc := damage_taken / 2
    if dc < 10 do dc = 10

    con_mod := ability_mod(s, "con")
    prof := 0
    if tgt_type == "character" do prof = get_char_save_prof(db, tgt_id, "con")
    prof_bonus := prof * s.proficiency

    roll, _ := resolve_attack_roll("d20")
    total := roll + con_mod + prof_bonus
    passed = total >= dc

    if passed {
        log_msg = fmt.tprintf("Concentration DC %d: %d + %d + %d = %d → MAINTAINED (%s)",
            dc, roll, con_mod, prof_bonus, total, s.concentrating)
    } else {
        table := actor_table(tgt_type)
        if len(table) > 0 {
            lib.db_exec(db, fmt.tprintf("UPDATE %s SET concentrating_on='' WHERE id=%d", table, tgt_id))
        }
        log_msg = fmt.tprintf("Concentration DC %d: %d + %d + %d = %d → BROKEN (was: %s)",
            dc, roll, con_mod, prof_bonus, total, s.concentrating)
    }
    return
}

// ---------------------------------------------------------------------------
// combat use-feature <encounter_id> <actor_type> <actor_id> <feature_name>
// ---------------------------------------------------------------------------
combat_use_feature :: proc(db: ^lib.Db, args: []string) -> int {
    if len(args) < 5 {
        return print_error(db, "Usage: ttrpg-engine combat use-feature <encounter_id> <actor_type> <actor_id> <feature_name>")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    feature_name := args[4]

    if !is_participant(db, enc_id, actor_type, actor_id) do return print_error(db, "Actor not in combat")

    s, _ := get_actor_stats(db, actor_type, actor_id)

    // Look up feature
    stmt: ^sqlite.Statement
    feat_sql := fmt.tprintf("SELECT id, source, description FROM features WHERE LOWER(name)=LOWER('%s')", escape_sql(feature_name))
    feat_c := cstring(raw_data(feat_sql))
    if sqlite.prepare(db.ptr, feat_c, i32(len(feat_sql)), &stmt, nil) != .Ok do return print_error(db, "Feature not found in library")
    defer sqlite.finalize(stmt)
    if sqlite.step(stmt) != .Row do return print_error(db, "Feature not found in library")
    feat_id := int(sqlite.column_int(stmt, 0))
    feat_source := column_text_safe(stmt, 1)
    sqlite.finalize(stmt)

    // Verify actor has this feature (characters only for now)
    has_feature := false
    if actor_type == "character" {
        chk_stmt: ^sqlite.Statement
        chk_sql := fmt.tprintf("SELECT 1 FROM character_features WHERE character_id=%d AND feature_id=%d", actor_id, feat_id)
        chk_c := cstring(raw_data(chk_sql))
        if sqlite.prepare(db.ptr, chk_c, i32(len(chk_sql)), &chk_stmt, nil) == .Ok {
            has_feature = sqlite.step(chk_stmt) == .Row
            sqlite.finalize(chk_stmt)
        }
    } else {
        // NPCs and creatures always "have" their listed features
        has_feature = true
    }
    if !has_feature do return print_error(db, "Actor does not have this feature")

    // Try to match and consume a resource
    resource_name := ""
    feature_lower := strings.to_lower(feature_name)
    switch {
    case strings.contains(feature_lower, "rage"):
        resource_name = "Rage"
    case strings.contains(feature_lower, "ki") || strings.contains(feature_lower, "flurry of blows") || strings.contains(feature_lower, "stunning strike") || strings.contains(feature_lower, "step of the wind") || strings.contains(feature_lower, "patient defense"):
        resource_name = "Ki Points"
    case strings.contains(feature_lower, "bardic inspiration"):
        resource_name = "Bardic Inspiration"
    case strings.contains(feature_lower, "channel divinity") || strings.contains(feature_lower, "turn undead"):
        resource_name = "Channel Divinity"
    case strings.contains(feature_lower, "action surge"):
        resource_name = "Action Surge"
    case strings.contains(feature_lower, "second wind"):
        resource_name = "Second Wind"
    case strings.contains(feature_lower, "arcane recovery"):
        resource_name = "Arcane Recovery"
    case strings.contains(feature_lower, "sorcery points") || strings.contains(feature_lower, "metamagic"):
        resource_name = "Sorcery Points"
    case strings.contains(feature_lower, "wild shape"):
        resource_name = "Wild Shape"
    case strings.contains(feature_lower, "lay on hands"):
        resource_name = "Lay on Hands"
    case strings.contains(feature_lower, "divine sense"):
        resource_name = "Divine Sense"
    }

    resource_consumed := false
    before_amount := 0
    after_amount := 0

    if len(resource_name) > 0 && actor_type == "character" {
        res_stmt: ^sqlite.Statement
        res_sql := fmt.tprintf("SELECT current_amount FROM character_resources WHERE character_id=%d AND resource_name='%s'", actor_id, escape_sql(resource_name))
        res_c := cstring(raw_data(res_sql))
        if sqlite.prepare(db.ptr, res_c, i32(len(res_sql)), &res_stmt, nil) == .Ok {
            if sqlite.step(res_stmt) == .Row {
                before_amount = int(sqlite.column_int(res_stmt, 0))
                sqlite.finalize(res_stmt)
                if before_amount > 0 {
                    lib.db_exec(db, fmt.tprintf("UPDATE character_resources SET current_amount = current_amount - 1 WHERE character_id=%d AND resource_name='%s'", actor_id, escape_sql(resource_name)))
                    after_amount = before_amount - 1
                    resource_consumed = true
                }
            } else {
                sqlite.finalize(res_stmt)
            }
        }
    }

    // Apply mechanical effects for known features
    effect_msg := ""
    feat_lower := strings.to_lower(feature_name)

    if strings.contains(feat_lower, "rage") {
        // Query current status effects from the actor's table
        table := actor_table(actor_type)
        current_effects := ""
        if len(table) > 0 {
            se_stmt: ^sqlite.Statement
            se_sql := fmt.tprintf("SELECT COALESCE(status_effects,'') FROM %s WHERE id=%d", table, actor_id)
            se_c := cstring(raw_data(se_sql))
            if sqlite.prepare(db.ptr, se_c, i32(len(se_sql)), &se_stmt, nil) == .Ok {
                if sqlite.step(se_stmt) == .Row do current_effects = column_text_safe(se_stmt, 0)
                sqlite.finalize(se_stmt)
            }
            new_effects := current_effects
            if len(new_effects) > 0 && !strings.contains(strings.to_lower(new_effects), "rage") {
                new_effects = fmt.tprintf("%s, rage", new_effects)
            } else if len(new_effects) == 0 {
                new_effects = "rage"
            }
            lib.db_exec(db, fmt.tprintf("UPDATE %s SET status_effects='%s' WHERE id=%d", table, escape_sql(new_effects), actor_id))
        }
        effect_msg = "B/P/S resistance active, +2 damage to STR melee attacks"
    } else if strings.contains(feat_lower, "action surge") {
        // Grant an extra action by resetting action_used
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET action_used=0, attacks_used=0 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(actor_type), actor_id))
        effect_msg = "Extra action granted — action_used and attacks_used reset"
    } else if strings.contains(feat_lower, "second wind") {
        // Heal 1d10 + fighter level
        char, char_ok := fetch_character_stats(db, actor_id)
        if char_ok {
            heal_roll, _ := resolve_amount("1d10")
            heal_total := heal_roll + char.level
            new_hp := s.current_hp + heal_total
            if new_hp > s.max_hp do new_hp = s.max_hp
            hp_update(db, actor_type, actor_id, new_hp)
            effect_msg = fmt.tprintf("Healed %d HP (1d10=%d + level %d)", heal_total, heal_roll, char.level)
        }
    } else if strings.contains(feat_lower, "ki") || strings.contains(feat_lower, "flurry of blows") || strings.contains(feat_lower, "patient defense") || strings.contains(feat_lower, "step of the wind") {
        effect_msg = "Ki point spent"
    } else if strings.contains(feat_lower, "divine smite") {
        effect_msg = "Spell slot must be consumed separately via combat cast"
    }

    if db.is_json {
        fmt.printf(`{{"success":true,"encounter_id":%d,"actor":"%s","feature":"%s","resource":"%s","resource_consumed":%s,"remaining":%d,"effect":"%s"}}` + "\n",
            enc_id, escape_json_string(s.name), escape_json_string(feature_name), resource_name, resource_consumed ? "true" : "false", after_amount, escape_json_string(effect_msg))
    } else {
        res_str := ""
        if resource_consumed {
            res_str = fmt.tprintf(" (%s: %d → %d)", resource_name, before_amount, after_amount)
        } else if len(resource_name) > 0 {
            res_str = fmt.tprintf(" (%s: no uses remaining)", resource_name)
        }
        eff_str := ""
        if len(effect_msg) > 0 do eff_str = fmt.tprintf(" — %s", effect_msg)
        fmt.printf("%s uses %s%s%s\n", s.name, feature_name, res_str, eff_str)
    }
    return 0
}
