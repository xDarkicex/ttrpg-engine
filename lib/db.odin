package lib

import "core:fmt"
import sqlite "ext:sqlite3"

Db :: struct {
	ptr: ^sqlite.Connection,
	is_json: bool,
}

Error :: enum {
	None,
	Open_Failed,
	Exec_Failed,
	Prepare_Failed,
	Step_Failed,
	Not_Found,
}

db_open :: proc(db_path: string) -> (db: Db, err: Error) {
	path_c := cstring(raw_data(db_path))
	if sqlite.open(path_c, &db.ptr) != .Ok {
		return {}, Error.Open_Failed
	}
	return db, nil
}

db_close :: proc(db: ^Db) {
	if db.ptr != nil {
		sqlite.close(db.ptr)
		db.ptr = nil
	}
}

db_exec :: proc(db: ^Db, sql: string) -> Error {
	sql_c := cstring(raw_data(sql))
	result := sqlite.exec(db.ptr, sql_c, nil, nil, nil)
	if result != .Ok {
		return Error.Exec_Failed
	}
	return nil
}

get_db_version :: proc(db: ^Db) -> int {
	stmt: ^sqlite.Statement
	sql := "PRAGMA user_version;"
	sql_c := cstring(raw_data(sql))
	if sqlite.prepare(db.ptr, sql_c, i32(len(sql)), &stmt, nil) != .Ok {
		return 0
	}
	defer sqlite.finalize(stmt)
	if sqlite.step(stmt) == .Row {
		return int(sqlite.column_int(stmt, 0))
	}
	return 0
}

set_db_version :: proc(db: ^Db, version: int) -> Error {
	sql := fmt.tprintf("PRAGMA user_version = %d;", version)
	return db_exec(db, sql)
}

db_init_schema :: proc(db: ^Db) -> Error {
	fk_err := db_exec(db, "PRAGMA foreign_keys = ON;")
	if fk_err != Error.None do return fk_err

	current_version := get_db_version(db)

	if current_version < 1 {
		schema := `
		CREATE TABLE IF NOT EXISTS characters (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			current_hp INTEGER DEFAULT 0,
			max_hp INTEGER DEFAULT 1,
			temp_hp INTEGER DEFAULT 0,
			death_saves_success INTEGER DEFAULT 0,
			death_saves_failure INTEGER DEFAULT 0,
			exhaustion INTEGER DEFAULT 0,
			hit_dice_expended INTEGER DEFAULT 0,
			backstory TEXT DEFAULT '',
			owner TEXT DEFAULT 'dm',
			created_at TEXT DEFAULT CURRENT_TIMESTAMP,
			str INTEGER DEFAULT 10,
			dex INTEGER DEFAULT 10,
			con INTEGER DEFAULT 10,
			int_ INTEGER DEFAULT 10,
			wis INTEGER DEFAULT 10,
			cha INTEGER DEFAULT 10,
			save_prof_str INTEGER DEFAULT 0,
			save_prof_dex INTEGER DEFAULT 0,
			save_prof_con INTEGER DEFAULT 0,
			save_prof_int INTEGER DEFAULT 0,
			save_prof_wis INTEGER DEFAULT 0,
			save_prof_cha INTEGER DEFAULT 0,
			ac INTEGER DEFAULT 10,
			race TEXT DEFAULT 'human',
			speed INTEGER DEFAULT 30,
			status_effects TEXT DEFAULT '',
			resistances TEXT DEFAULT '',
			vulnerabilities TEXT DEFAULT '',
			immunities TEXT DEFAULT '',
			gold INTEGER DEFAULT 0,
			silver INTEGER DEFAULT 0,
			copper INTEGER DEFAULT 0,
			platinum INTEGER DEFAULT 0,
			electrum INTEGER DEFAULT 0,
			inspiration INTEGER DEFAULT 0,
			alignment TEXT DEFAULT 'neutral',
			size TEXT DEFAULT 'medium',
			xp INTEGER DEFAULT 0,
			faction_id INTEGER DEFAULT 0,
			campaign_id INTEGER DEFAULT 0,
			last_action TEXT DEFAULT '',
			party TEXT DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS items (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			description TEXT DEFAULT '',
			item_type TEXT DEFAULT 'misc',
			damage_dice TEXT DEFAULT '',
			damage_type TEXT DEFAULT '',
			ac_bonus INTEGER DEFAULT 0,
			properties TEXT DEFAULT '',
			weight REAL DEFAULT 0.0,
			value_gp REAL DEFAULT 0.0
		);
		CREATE TABLE IF NOT EXISTS inventory (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			npc_id INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			creature_id INTEGER REFERENCES creatures(id) ON DELETE CASCADE,
			item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
			quantity INTEGER DEFAULT 1,
			equipped INTEGER DEFAULT 0,
			attuned INTEGER DEFAULT 0
		);
		CREATE TABLE IF NOT EXISTS npcs (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			current_hp INTEGER DEFAULT 0,
			max_hp INTEGER DEFAULT 1,
			dm_notes TEXT DEFAULT '',
			campaign_id INTEGER DEFAULT 0,
			gold INTEGER DEFAULT 0,
			silver INTEGER DEFAULT 0,
			copper INTEGER DEFAULT 0,
			ac INTEGER DEFAULT 10,
			status_effects TEXT DEFAULT '',
			resistances TEXT DEFAULT '',
			vulnerabilities TEXT DEFAULT '',
			immunities TEXT DEFAULT '',
			story_role TEXT DEFAULT '',
			daily_role TEXT DEFAULT '',
			backstory TEXT DEFAULT '',
			faction_id INTEGER DEFAULT 0,
			last_action TEXT DEFAULT '',
			location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
			str INTEGER DEFAULT 10,
			dex INTEGER DEFAULT 10,
			con INTEGER DEFAULT 10,
			int_ INTEGER DEFAULT 10,
			wis INTEGER DEFAULT 10,
			cha INTEGER DEFAULT 10
		);
		CREATE TABLE IF NOT EXISTS campaigns (
			id INTEGER PRIMARY KEY, name TEXT NOT NULL, chapter TEXT DEFAULT '',
			session_num INTEGER DEFAULT 0, created_at TEXT DEFAULT CURRENT_TIMESTAMP
		);
		CREATE TABLE IF NOT EXISTS spells (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			level INTEGER DEFAULT 0,
			school TEXT DEFAULT '',
			casting_time TEXT DEFAULT '',
			range TEXT DEFAULT '',
			components TEXT DEFAULT '',
			duration TEXT DEFAULT '',
			description TEXT DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS character_spells (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			spell_id INTEGER REFERENCES spells(id) ON DELETE CASCADE,
			prepared INTEGER DEFAULT 0,
			UNIQUE(character_id, spell_id)
		);
		CREATE TABLE IF NOT EXISTS features (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			source TEXT DEFAULT '',
			description TEXT DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS character_features (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			feature_id INTEGER REFERENCES features(id) ON DELETE CASCADE,
			UNIQUE(character_id, feature_id)
		);
		CREATE TABLE IF NOT EXISTS companions (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			name TEXT NOT NULL,
			type TEXT DEFAULT 'familiar',
			level INTEGER DEFAULT 1,
			max_hp INTEGER DEFAULT 10,
			current_hp INTEGER DEFAULT 10,
			ac INTEGER DEFAULT 10,
			attack_bonus INTEGER DEFAULT 0,
			damage_dice TEXT DEFAULT '1d4',
			str INTEGER DEFAULT 10,
			dex INTEGER DEFAULT 10,
			con INTEGER DEFAULT 10,
			int_ INTEGER DEFAULT 10,
			wis INTEGER DEFAULT 10,
			cha INTEGER DEFAULT 10,
			status_effects TEXT DEFAULT '',
			resistances TEXT DEFAULT '',
			vulnerabilities TEXT DEFAULT '',
			immunities TEXT DEFAULT '',
			last_action TEXT DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS character_classes (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			class_name TEXT NOT NULL,
			level INTEGER DEFAULT 1,
			UNIQUE(character_id, class_name)
		);
		CREATE TABLE IF NOT EXISTS factions (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			description TEXT DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS npc_relationships (
			id INTEGER PRIMARY KEY,
			npc_id_1 INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			npc_id_2 INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			friendship_level INTEGER DEFAULT 0,
			notes TEXT DEFAULT '',
			UNIQUE(npc_id_1, npc_id_2)
		);
		CREATE TABLE IF NOT EXISTS creatures (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			current_hp INTEGER DEFAULT 10,
			max_hp INTEGER DEFAULT 10,
			ac INTEGER DEFAULT 10,
			status_effects TEXT DEFAULT '',
			resistances TEXT DEFAULT '',
			vulnerabilities TEXT DEFAULT '',
			immunities TEXT DEFAULT '',
			attacks TEXT DEFAULT '',
			story_role TEXT DEFAULT '',
			last_action TEXT DEFAULT '',
			campaign_id INTEGER DEFAULT 0,
			location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
			str INTEGER DEFAULT 10,
			dex INTEGER DEFAULT 10,
			con INTEGER DEFAULT 10,
			int_ INTEGER DEFAULT 10,
			wis INTEGER DEFAULT 10,
			cha INTEGER DEFAULT 10,
			gold INTEGER DEFAULT 0,
			silver INTEGER DEFAULT 0,
			copper INTEGER DEFAULT 0,
			platinum INTEGER DEFAULT 0,
			electrum INTEGER DEFAULT 0
		);
		CREATE TABLE IF NOT EXISTS class_specialties (
			id INTEGER PRIMARY KEY,
			class_name TEXT NOT NULL,
			level INTEGER DEFAULT 1,
			ability_name TEXT NOT NULL,
			description TEXT DEFAULT '',
			UNIQUE(class_name, level, ability_name)
		);
		CREATE TABLE IF NOT EXISTS locations (
			id INTEGER PRIMARY KEY,
			campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			chapter TEXT DEFAULT '',
			is_current INTEGER DEFAULT 0,
			UNIQUE(campaign_id, name)
		);
		CREATE TABLE IF NOT EXISTS faction_standings (
			id INTEGER PRIMARY KEY,
			faction_id INTEGER REFERENCES factions(id) ON DELETE CASCADE,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			standing INTEGER DEFAULT 0,
			notes TEXT DEFAULT '',
			UNIQUE(faction_id, character_id)
		);
		CREATE TABLE IF NOT EXISTS story_actions (
			id INTEGER PRIMARY KEY,
			campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
			location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
			description TEXT NOT NULL,
			standing_faction_id INTEGER REFERENCES factions(id) ON DELETE SET NULL,
			standing_impact INTEGER DEFAULT 0,
			story_progression INTEGER DEFAULT 1,
			status TEXT DEFAULT 'completed',
			created_at TEXT DEFAULT CURRENT_TIMESTAMP
		);
		CREATE TABLE IF NOT EXISTS story_action_actors (
			id INTEGER PRIMARY KEY,
			action_id INTEGER REFERENCES story_actions(id) ON DELETE CASCADE,
			actor_type TEXT NOT NULL,
			actor_id INTEGER NOT NULL,
			UNIQUE(action_id, actor_type, actor_id)
		);
		CREATE TABLE IF NOT EXISTS character_skills (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			skill_name TEXT NOT NULL,
			proficiency_level INTEGER DEFAULT 1,
			UNIQUE(character_id, skill_name)
		);
		CREATE TABLE IF NOT EXISTS character_resources (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			resource_name TEXT NOT NULL,
			max_amount INTEGER DEFAULT 0,
			current_amount INTEGER DEFAULT 0,
			reset_condition TEXT DEFAULT 'long_rest',
			UNIQUE(character_id, resource_name)
		);
		CREATE TABLE IF NOT EXISTS npc_features (
			id INTEGER PRIMARY KEY,
			npc_id INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			feature_id INTEGER REFERENCES features(id) ON DELETE CASCADE,
			UNIQUE(npc_id, feature_id)
		);
		CREATE TABLE IF NOT EXISTS creature_features (
			id INTEGER PRIMARY KEY,
			creature_id INTEGER REFERENCES creatures(id) ON DELETE CASCADE,
			feature_id INTEGER REFERENCES features(id) ON DELETE CASCADE,
			UNIQUE(creature_id, feature_id)
		);
		`
		err := db_exec(db, schema)
		if err != Error.None do return err

		set_version_err := set_db_version(db, 1)
		if set_version_err != Error.None do return set_version_err
	}

	current_version = get_db_version(db)
	if current_version < 2 {
		db_exec(db, "ALTER TABLE npcs ADD COLUMN str INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN dex INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN con INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN int_ INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN wis INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN cha INTEGER DEFAULT 10;")

		set_version_err := set_db_version(db, 2)
		if set_version_err != Error.None do return set_version_err
	}

	current_version = get_db_version(db)
	if current_version < 3 {
		db_exec(db, "ALTER TABLE creatures ADD COLUMN campaign_id INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;")

		set_version_err := set_db_version(db, 3)
		if set_version_err != Error.None do return set_version_err
	}

	current_version = get_db_version(db)
	if current_version < 4 {
		db_exec(db, "ALTER TABLE creatures ADD COLUMN str INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN dex INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN con INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN int_ INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN wis INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN cha INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN gold INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN silver INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN copper INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN platinum INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN electrum INTEGER DEFAULT 0;")

		db_exec(db, `CREATE TABLE IF NOT EXISTS npc_features (
			id INTEGER PRIMARY KEY,
			npc_id INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			feature_id INTEGER REFERENCES features(id) ON DELETE CASCADE,
			UNIQUE(npc_id, feature_id)
		);`)

		db_exec(db, `CREATE TABLE IF NOT EXISTS creature_features (
			id INTEGER PRIMARY KEY,
			creature_id INTEGER REFERENCES creatures(id) ON DELETE CASCADE,
			feature_id INTEGER REFERENCES features(id) ON DELETE CASCADE,
			UNIQUE(creature_id, feature_id)
		);`)

		set_version_err := set_db_version(db, 4)
		if set_version_err != Error.None do return set_version_err
	}

	current_version = get_db_version(db)
	if current_version < 5 {
		db_exec(db, "ALTER TABLE characters ADD COLUMN location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN chapter_id TEXT DEFAULT '';")

		set_version_err := set_db_version(db, 5)
		if set_version_err != Error.None do return set_version_err
	}

	current_version = get_db_version(db)
	if current_version < 6 {
		// Character: combat + spellcasting + initiative + perception + languages + max hit dice
		db_exec(db, "ALTER TABLE characters ADD COLUMN proficiency_bonus INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN spell_save_dc INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN spell_attack_bonus INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN initiative INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN passive_perception INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN languages TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE characters ADD COLUMN max_hit_dice INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE characters ADD COLUMN concentrating_on TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE characters ADD COLUMN combat INTEGER DEFAULT 0;")

		// NPC: CR + attack + initiative + perception + languages + combat
		db_exec(db, "ALTER TABLE npcs ADD COLUMN cr INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN attack_bonus INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN damage_dice TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN damage_type TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN initiative INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN passive_perception INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN languages TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN concentrating_on TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE npcs ADD COLUMN combat INTEGER DEFAULT 0;")

		// Creature: structured attack + CR + initiative + perception + reactions + legendary + combat
		db_exec(db, "ALTER TABLE creatures ADD COLUMN attack_bonus INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN damage_dice TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN damage_type TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN challenge_rating INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN initiative INTEGER DEFAULT 0;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN passive_perception INTEGER DEFAULT 10;")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN reactions TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN legendary_actions TEXT DEFAULT '';")
		db_exec(db, "ALTER TABLE creatures ADD COLUMN combat INTEGER DEFAULT 0;")

		// Junction tables for proficiencies
		db_exec(db, `CREATE TABLE IF NOT EXISTS character_weapon_profs (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			weapon_name TEXT NOT NULL,
			UNIQUE(character_id, weapon_name)
		);`)
		db_exec(db, `CREATE TABLE IF NOT EXISTS character_armor_profs (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			armor_name TEXT NOT NULL,
			UNIQUE(character_id, armor_name)
		);`)
		db_exec(db, `CREATE TABLE IF NOT EXISTS character_tool_profs (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			tool_name TEXT NOT NULL,
			UNIQUE(character_id, tool_name)
		);`)

		// Junction table for NPC skills (creatures don't get skills)
		db_exec(db, `CREATE TABLE IF NOT EXISTS npc_skills (
			id INTEGER PRIMARY KEY,
			npc_id INTEGER REFERENCES npcs(id) ON DELETE CASCADE,
			skill_name TEXT NOT NULL,
			modifier INTEGER DEFAULT 0,
			UNIQUE(npc_id, skill_name)
		);`)

		// Spell slots (track max + used per level for each character)
		db_exec(db, `CREATE TABLE IF NOT EXISTS character_spell_slots (
			id INTEGER PRIMARY KEY,
			character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE,
			slot_level INTEGER NOT NULL,
			max_slots INTEGER DEFAULT 0,
			used_slots INTEGER DEFAULT 0,
			UNIQUE(character_id, slot_level)
		);`)

		set_version_err := set_db_version(db, 6)
		if set_version_err != Error.None do return set_version_err
	}

	return Error.None
}

// last_insert_rowid not available in this sqlite3 binding