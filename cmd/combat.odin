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
        return print_error(db, "Usage: dnd-agent combat start <campaign_id> <location_id>")
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
        return print_error(db, "Usage: dnd-agent combat join <encounter_id> <char|npc|creature> <id> <initiative_roll> [initiative_mod] [position]")
    }
    enc_id := strconv.atoi(args[1])
    actor_type := args[2]
    if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    init_roll := strconv.atoi(args[4])
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
        return print_error(db, "Usage: dnd-agent combat join-all <encounter_id>")
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
        return print_error(db, "Usage: dnd-agent combat init <encounter_id>")
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
        return print_error(db, "Usage: dnd-agent combat next <encounter_id>")
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
        lib.db_exec(db, fmt.tprintf("UPDATE combat_participants SET action_used=0, bonus_action_used=0 WHERE encounter_id=%d AND actor_type='%s' AND actor_id=%d", enc_id, escape_sql(atype), aid))
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
        return print_error(db, "Usage: dnd-agent combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <attack_roll> [ability] [adv|disadv]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    att_type := args[2]; if att_type == "char" do att_type = "character"
    att_id := strconv.atoi(args[3])
    tgt_type := args[4]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[5])
    att_roll := strconv.atoi(args[6])
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
        return print_error(db, "Usage: dnd-agent combat damage <encounter_id> <target_type> <target_id> <amount> <type> [source]")
    }
    enc_id := strconv.atoi(args[1])
    if !encounter_exists(db, enc_id) do return print_error(db, "Encounter not found or not active")
    tgt_type := args[2]; if tgt_type == "char" do tgt_type = "character"
    tgt_id := strconv.atoi(args[3])
    amount := strconv.atoi(args[4])
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
        dc := remaining / 2; if dc < 10 do dc = 10
        conc_msg = fmt.tprintf(" | Concentration DC %d (%s)", dc, s.concentrating)
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
        return print_error(db, "Usage: dnd-agent combat save <encounter_id> <actor_type> <actor_id> <ability> <save_roll> [dc] [adv|disadv]")
    }
    enc_id := strconv.atoi(args[1])
    actor_type := args[2]; if actor_type == "char" do actor_type = "character"
    actor_id := strconv.atoi(args[3])
    ability := args[4]
    save_roll := strconv.atoi(args[5])
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
        return print_error(db, "Usage: dnd-agent combat move <encounter_id> <actor_type> <actor_id> <position>")
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
        return print_error(db, "Usage: dnd-agent combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]")
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
        return print_error(db, "Usage: dnd-agent combat death-save <character_id> <roll>")
    }
    char_id := strconv.atoi(args[1])
    roll := strconv.atoi(args[2])

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
        return print_error(db, "Usage: dnd-agent combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]")
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
        return print_error(db, "Usage: dnd-agent combat ready <encounter_id> <actor_type> <actor_id> \"<action>\" <trigger>")
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
        return print_error(db, "Usage: dnd-agent combat status <encounter_id>")
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
        return print_error(db, "Usage: dnd-agent combat end <encounter_id>")
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
