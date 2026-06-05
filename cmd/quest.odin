package cmd

import "core:fmt"
import "core:strconv"
import "core:strings"
import lib "../lib"
import sqlite "ext:sqlite3"

// v18: quest tracking for AI campaign continuity.
// Quests track what the party is supposed to be doing, with step-by-step
// objectives and linked actors. The get-story-state command includes
// active quests in the context packet.

quest_add :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: dnd-agent quest add <campaign_id> <name> [description] [quest_giver_npc_id] [reward] [chapter]")
	}

	campaign_id := strconv.atoi(args[1])
	name := args[2]
	description := parse_opt_string(args, 3, "")
	giver_sql := parse_opt_id(args, 4)
	reward := parse_opt_string(args, 5, "")
	chapter := parse_opt_string(args, 6, "")

	sql := fmt.tprintf(
		"INSERT INTO quests (campaign_id, name, description, quest_giver_npc_id, reward_description, chapter) VALUES (%d, '%s', '%s', %s, '%s', '%s')",
		campaign_id, escape_sql(name), escape_sql(description), giver_sql, escape_sql(reward), escape_sql(chapter),
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to create quest")
	}

	quest_id := get_last_insert_id(db)
	if db.is_json {
		fmt.printf(`{"success":true,"message":"Quest created","quest_id":%d}`+"\n", quest_id)
	} else {
		fmt.printf("Quest #%d created: %s\n", quest_id, name)
	}
	return 0
}

quest_add_objective :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: dnd-agent quest add-objective <quest_id> <description> [sort_order]")
	}

	quest_id := strconv.atoi(args[1])
	description := args[2]
	sort_order := parse_opt_int(args, 3, 0)

	sql := fmt.tprintf(
		"INSERT INTO quest_objectives (quest_id, description, sort_order) VALUES (%d, '%s', %d)",
		quest_id, escape_sql(description), sort_order,
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to add objective")
	}

	obj_id := get_last_insert_id(db)
	if db.is_json {
		fmt.printf(`{"success":true,"message":"Objective added","objective_id":%d}`+"\n", obj_id)
	} else {
		fmt.printf("Objective #%d added to quest %d\n", obj_id, quest_id)
	}
	return 0
}

quest_complete_objective :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: dnd-agent quest complete-objective <objective_id>")
	}

	obj_id := strconv.atoi(args[1])
	sql := fmt.tprintf("UPDATE quest_objectives SET status='complete' WHERE id=%d", obj_id)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to complete objective")
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Objective completed","objective_id":%d}`+"\n", obj_id)
	} else {
		fmt.printf("Objective #%d marked complete\n", obj_id)
	}
	return 0
}

quest_set_status :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 3 {
		return print_error(db, "Usage: dnd-agent quest set-status <quest_id> <active|completed|failed|abandoned>")
	}

	quest_id := strconv.atoi(args[1])
	status := args[2]

	if status != "active" && status != "completed" && status != "failed" && status != "abandoned" {
		return print_error(db, "Status must be: active, completed, failed, or abandoned")
	}

	sql := fmt.tprintf("UPDATE quests SET status='%s' WHERE id=%d", escape_sql(status), quest_id)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to update quest status")
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Quest status updated","quest_id":%d,"status":"%s"}`+"\n", quest_id, status)
	} else {
		fmt.printf("Quest #%d status: %s\n", quest_id, status)
	}
	return 0
}

quest_add_actor :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 4 {
		return print_error(db, "Usage: dnd-agent quest add-actor <quest_id> <char|npc> <actor_id> [role]")
	}

	quest_id := strconv.atoi(args[1])
	actor_id := strconv.atoi(args[3])
	actor_type, type_ok := validate_actor_type(args[2])
	if !type_ok {
		return print_error(db, "Actor type must be 'char' or 'npc'")
	}

	if !check_actor_exists(db, actor_type, actor_id) {
		err_msg := fmt.tprintf("%s with ID %d not found", actor_type, actor_id)
		return print_error(db, err_msg)
	}

	role := parse_opt_string(args, 4, "participant")

	sql := fmt.tprintf(
		"INSERT OR IGNORE INTO quest_actors (quest_id, actor_type, actor_id, role) VALUES (%d, '%s', %d, '%s')",
		quest_id, actor_type, actor_id, escape_sql(role),
	)

	if lib.db_exec(db, sql) != .None {
		return print_error(db, "Failed to link actor to quest")
	}

	if db.is_json {
		fmt.printf(`{"success":true,"message":"Linked %s %d to quest %d as %s"}`+"\n", actor_type, actor_id, quest_id, role)
	} else {
		fmt.printf("Linked %s %d to quest %d as %s\n", actor_type, actor_id, quest_id, role)
	}
	return 0
}

quest_list :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: dnd-agent quest list <campaign_id> [status]")
	}

	campaign_id := strconv.atoi(args[1])
	status_filter := parse_opt_string(args, 2, "")

	stmt: ^sqlite.Statement
	sql: string
	if len(status_filter) > 0 {
		sql = fmt.tprintf(
			"SELECT q.id, q.name, q.status, q.quest_giver_npc_id, n.name, q.reward_description, q.chapter FROM quests q LEFT JOIN npcs n ON q.quest_giver_npc_id = n.id WHERE q.campaign_id=%d AND q.status='%s' ORDER BY q.id",
			campaign_id, escape_sql(status_filter),
		)
	} else {
		sql = fmt.tprintf(
			"SELECT q.id, q.name, q.status, q.quest_giver_npc_id, n.name, q.reward_description, q.chapter FROM quests q LEFT JOIN npcs n ON q.quest_giver_npc_id = n.id WHERE q.campaign_id=%d ORDER BY q.id",
			campaign_id,
		)
	}

	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Failed to list quests")
	}
	defer sqlite.finalize(stmt)

	if db.is_json {
		builder := strings.builder_make(context.temp_allocator)
		strings.write_byte(&builder, '[')
		first := true
		for sqlite.step(stmt) == .Row {
			if !first do strings.write_byte(&builder, ',')
			first = false
			q_id := int(sqlite.column_int(stmt, 0))
			giver_id := int(sqlite.column_int(stmt, 3))
			giver_name := column_text_safe(stmt, 4)
			giver_id_str := giver_id > 0 ? fmt.tprintf("%d", giver_id) : "null"
			giver_name_str := len(giver_name) > 0 ? fmt.tprintf(`"%s"`, escape_json_string(giver_name)) : "null"

			strings.write_string(&builder, "{")
			fmt.sbprintf(&builder, `"id":%d,"name":"%s","status":"%s","quest_giver_npc_id":%s,"quest_giver_name":%s,"reward_description":"%s","chapter":"%s"`,
				q_id,
				escape_json_string(column_text_safe(stmt, 1)),
				column_text_safe(stmt, 2),
				giver_id_str,
				giver_name_str,
				escape_json_string(column_text_safe(stmt, 5)),
				column_text_safe(stmt, 6),
			)
			strings.write_string(&builder, `,"objectives":`)
			print_json_quest_objectives(&builder, db, q_id)
			strings.write_string(&builder, "}")
		}
		strings.write_byte(&builder, ']')
		fmt.println(strings.to_string(builder))
	} else {
		has_any := false
		for sqlite.step(stmt) == .Row {
			has_any = true
			q_id := int(sqlite.column_int(stmt, 0))
			name := column_text_safe(stmt, 1)
			status := column_text_safe(stmt, 2)
			giver_id := int(sqlite.column_int(stmt, 3))
			reward := column_text_safe(stmt, 5)
			ch := column_text_safe(stmt, 6)

			fmt.printf("[%d] [%s] %s\n", q_id, status, name)
			if giver_id > 0 {
				fmt.printf("  Quest giver: %s (#%d)\n", column_text_safe(stmt, 4), giver_id)
			}
			if len(ch) > 0 || len(reward) > 0 {
				fmt.printf("  Chapter: %s | Reward: %s\n", ch, reward)
			}
			fmt.println()
		}
		if !has_any do fmt.println("No quests found.")
	}
	return 0
}

quest_get :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 2 {
		return print_error(db, "Usage: dnd-agent quest get <quest_id>")
	}

	quest_id := strconv.atoi(args[1])

	stmt: ^sqlite.Statement
	sql := fmt.tprintf(
		"SELECT q.id, q.campaign_id, q.name, q.description, q.quest_giver_npc_id, n.name, q.status, q.reward_description, q.chapter, q.created_at FROM quests q LEFT JOIN npcs n ON q.quest_giver_npc_id = n.id WHERE q.id=%d",
		quest_id,
	)
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return print_error(db, "Quest not found")
	}
	defer sqlite.finalize(stmt)

	if sqlite.step(stmt) != .Row {
		return print_error(db, "Quest not found")
	}

	q_id := int(sqlite.column_int(stmt, 0))
	camp_id := int(sqlite.column_int(stmt, 1))
	q_name := column_text_safe(stmt, 2)
	q_desc := column_text_safe(stmt, 3)
	giver_id := int(sqlite.column_int(stmt, 4))
	giver_name := column_text_safe(stmt, 5)
	status := column_text_safe(stmt, 6)
	reward := column_text_safe(stmt, 7)
	chapter := column_text_safe(stmt, 8)
	created := column_text_safe(stmt, 9)

	if db.is_json {
		giver_id_str := giver_id > 0 ? fmt.tprintf("%d", giver_id) : "null"
		giver_name_str := len(giver_name) > 0 ? fmt.tprintf(`"%s"`, escape_json_string(giver_name)) : "null"

		fmt.printf(`{"id":%d,"campaign_id":%d,"name":"%s","description":"%s","quest_giver_npc_id":%s,"quest_giver_name":%s,"status":"%s","reward_description":"%s","chapter":"%s","created_at":"%s"`,
			q_id, camp_id,
			escape_json_string(q_name),
			escape_json_string(q_desc),
			giver_id_str,
			giver_name_str,
			status,
			escape_json_string(reward),
			chapter,
			created,
		)
		fmt.print(`,"objectives":`)
		builder := strings.builder_make(context.temp_allocator)
		print_json_quest_objectives(&builder, db, quest_id)
		fmt.print(strings.to_string(builder))
		fmt.print(`,"actors":`)
		builder2 := strings.builder_make(context.temp_allocator)
		print_json_quest_actors(&builder2, db, quest_id)
		fmt.print(strings.to_string(builder2))
		fmt.println(`}`)
	} else {
		fmt.printf("Quest #%d: %s\n", q_id, q_name)
		fmt.printf("  Status: %s | Chapter: %s | Campaign: %d\n", status, chapter, camp_id)
		fmt.printf("  Reward: %s\n", reward)
		fmt.printf("  Created: %s\n", created)
		if len(q_desc) > 0 {
			fmt.printf("  Description: %s\n", q_desc)
		}
		if giver_id > 0 {
			fmt.printf("  Quest giver: %s (#%d)\n", giver_name, giver_id)
		}

		fmt.println("  Objectives:")
		obj_stmt: ^sqlite.Statement
		obj_sql := fmt.tprintf("SELECT id, description, status, sort_order FROM quest_objectives WHERE quest_id=%d ORDER BY sort_order, id", quest_id)
		obj_c := cstring(raw_data(obj_sql))
		if sqlite.prepare(db.ptr, obj_c, i32(len(obj_sql)), &obj_stmt, nil) == .Ok {
			for sqlite.step(obj_stmt) == .Row {
				done := column_text_safe(obj_stmt, 2) == "complete" ? "x" : " "
				fmt.printf("    [%s] #%d %s\n", done, sqlite.column_int(obj_stmt, 0), column_text_safe(obj_stmt, 1))
			}
			sqlite.finalize(obj_stmt)
		}

		fmt.println("  Actors:")
		act_stmt: ^sqlite.Statement
		act_sql := fmt.tprintf("SELECT actor_type, actor_id, role FROM quest_actors WHERE quest_id=%d ORDER BY actor_type, actor_id", quest_id)
		act_c := cstring(raw_data(act_sql))
		if sqlite.prepare(db.ptr, act_c, i32(len(act_sql)), &act_stmt, nil) == .Ok {
			has_actors := false
			for sqlite.step(act_stmt) == .Row {
				has_actors = true
				a_type := column_text_safe(act_stmt, 0)
				a_id := int(sqlite.column_int(act_stmt, 1))
				a_role := column_text_safe(act_stmt, 2)
				a_name := get_actor_name(db, a_type, a_id)
				fmt.printf("    %s #%d (%s) — %s\n", a_type, a_id, a_name, a_role)
			}
			if !has_actors do fmt.println("    None")
			sqlite.finalize(act_stmt)
		}
	}
	return 0
}
