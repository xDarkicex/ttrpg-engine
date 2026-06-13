package cmd

import "core:fmt"
import "core:math"
import "core:testing"
import lib "../lib"
import sqlite "ext:sqlite3"

// Helper to create an in-memory test DB with wanted schema
setup_test_db :: proc(t: ^testing.T) -> lib.Db {
	db: lib.Db
	path := ":memory:"
	path_c := cstring(raw_data(path))
	if sqlite.open(path_c, &db.ptr) != .Ok {
		testing.expect(t, false, "Failed to open in-memory DB")
		return db
	}
	exec_sql :: proc(db: ^lib.Db, sql: string) {
		sql_c := cstring(raw_data(sql))
		sqlite.exec(db.ptr, sql_c, nil, nil, nil)
	}
	exec_sql(&db, "PRAGMA foreign_keys = ON;")

	schema_sql := `CREATE TABLE IF NOT EXISTS factions (id INTEGER PRIMARY KEY, name TEXT NOT NULL, description TEXT DEFAULT '');
CREATE TABLE IF NOT EXISTS campaigns (id INTEGER PRIMARY KEY, name TEXT, total_elapsed_hours INTEGER DEFAULT 6);
CREATE TABLE IF NOT EXISTS locations (id INTEGER PRIMARY KEY, campaign_id INTEGER DEFAULT 0, name TEXT, parent_id INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS characters (id INTEGER PRIMARY KEY, name TEXT, campaign_id INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS npcs (id INTEGER PRIMARY KEY, name TEXT, campaign_id INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS wanted_heat (
	id INTEGER PRIMARY KEY,
	actor_type TEXT NOT NULL,
	actor_id INTEGER NOT NULL,
	faction_id INTEGER REFERENCES factions(id) ON DELETE CASCADE,
	location_id INTEGER REFERENCES locations(id) ON DELETE CASCADE,
	heat_points INTEGER DEFAULT 0,
	last_decay_hour INTEGER DEFAULT 0,
	notes TEXT DEFAULT '',
	UNIQUE(actor_type, actor_id, faction_id, location_id)
);
CREATE TABLE IF NOT EXISTS crime_log (
	id INTEGER PRIMARY KEY,
	actor_type TEXT NOT NULL,
	actor_id INTEGER NOT NULL,
	faction_id INTEGER REFERENCES factions(id) ON DELETE CASCADE,
	location_id INTEGER REFERENCES locations(id) ON DELETE CASCADE,
	description TEXT NOT NULL,
	severity INTEGER NOT NULL,
	in_game_day INTEGER DEFAULT 0,
	created_at TEXT DEFAULT CURRENT_TIMESTAMP
);`
	exec_sql(&db, schema_sql)

	seed_sql := `INSERT INTO factions (id, name) VALUES(1, 'City Watch');
INSERT INTO campaigns (id, name, total_elapsed_hours) VALUES(1, 'Test', 6);
INSERT INTO locations (id, campaign_id, name, parent_id) VALUES(1, 1, 'Waterdeep', 0);
INSERT INTO locations (id, campaign_id, name, parent_id) VALUES(2, 1, 'Dock Ward', 1);
INSERT INTO locations (id, campaign_id, name, parent_id) VALUES(3, 1, 'Castle Ward', 1);
INSERT INTO characters (id, name, campaign_id) VALUES(1, 'Grimgar', 1);
INSERT INTO characters (id, name, campaign_id) VALUES(2, 'Lyra', 0);
INSERT INTO npcs (id, name, campaign_id) VALUES(1, 'Blacktooth', 1);`
	exec_sql(&db, seed_sql)
	return db
}

// ---------------------------------------------------------------------------
// Pure function tests
// ---------------------------------------------------------------------------

@(test)
test_heat_to_tier :: proc(t: ^testing.T) {
	// Zero / negative
	ti := heat_to_tier(0)
	testing.expect_value(t, ti.tier, 0)
	testing.expect_value(t, ti.label, "Clean")

	ti = heat_to_tier(-5)
	testing.expect_value(t, ti.tier, 0)

	// Tier 1 boundary
	ti = heat_to_tier(1)
	testing.expect_value(t, ti.tier, 1)
	testing.expect_value(t, ti.label, "Suspicious")

	ti = heat_to_tier(15)
	testing.expect_value(t, ti.tier, 1)

	// Tier 2 boundary
	ti = heat_to_tier(16)
	testing.expect_value(t, ti.tier, 2)
	testing.expect_value(t, ti.label, "Wanted")

	ti = heat_to_tier(35)
	testing.expect_value(t, ti.tier, 2)

	// Tier 3 boundary
	ti = heat_to_tier(36)
	testing.expect_value(t, ti.tier, 3)
	testing.expect_value(t, ti.label, "Hunted")

	ti = heat_to_tier(60)
	testing.expect_value(t, ti.tier, 3)

	// Tier 4 boundary
	ti = heat_to_tier(61)
	testing.expect_value(t, ti.tier, 4)
	testing.expect_value(t, ti.label, "Infamous")

	ti = heat_to_tier(85)
	testing.expect_value(t, ti.tier, 4)

	// Tier 5
	ti = heat_to_tier(86)
	testing.expect_value(t, ti.tier, 5)
	testing.expect_value(t, ti.label, "Legendary Fugitive")

	ti = heat_to_tier(500)
	testing.expect_value(t, ti.tier, 5)
}

@(test)
test_compute_decay_hours :: proc(t: ^testing.T) {
	// No decay when last_hour is 0 (never set)
	result := compute_decay_hours(100, 0, 1000)
	testing.expect_value(t, result, 100)

	// No decay when no time has passed
	result = compute_decay_hours(100, 100, 100)
	testing.expect_value(t, result, 100)

	// No decay when heat is 0
	result = compute_decay_hours(0, 100, 200)
	testing.expect_value(t, result, 0)

	// ~14 days (half-life): 50 * e^(-0.05*14) ≈ 25
	result = compute_decay_hours(50, 0 + 6, 0 + 6 + 336)
	testing.expect_value(t, result, 24) // int(50 * e^(-0.05*14)) = int(24.8) = 24

	// ~28 days: 50 * e^(-0.05*28) ≈ 12
	result = compute_decay_hours(50, 0 + 6, 0 + 6 + 672)
	testing.expect_value(t, result, 12) // int(50 * e^(-0.05*28)) = int(12.3) = 12

	// Very long time should approach 0
	result = compute_decay_hours(100, 0 + 6, 0 + 6 + 8760) // 1 year
	testing.expect(t, result >= 0 && result <= 1, "Should decay to near zero after a year")
}

@(test)
test_validate_wanted_actor :: proc(t: ^testing.T) {
	at, ok := validate_wanted_actor("char")
	testing.expect(t, ok)
	testing.expect_value(t, at, "character")

	at, ok = validate_wanted_actor("character")
	testing.expect(t, ok)
	testing.expect_value(t, at, "character")

	at, ok = validate_wanted_actor("npc")
	testing.expect(t, ok)
	testing.expect_value(t, at, "npc")

	_, ok = validate_wanted_actor("creature")
	testing.expect(t, !ok, "creature should not be valid")

	_, ok = validate_wanted_actor("")
	testing.expect(t, !ok, "empty string should not be valid")
}

// ---------------------------------------------------------------------------
// DB-backed tests
// ---------------------------------------------------------------------------

@(test)
test_get_current_hours_for_actor :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Character with campaign (total_elapsed_hours = 6)
	hours, ok := get_current_hours_for_actor(&db, "character", 1)
	testing.expect(t, ok)
	testing.expect_value(t, hours, 6)

	// Character without campaign (campaign_id = 0)
	hours, ok = get_current_hours_for_actor(&db, "character", 2)
	testing.expect(t, !ok || hours == 0, "Character without campaign should return 0 or not ok")

	// NPC with campaign
	hours, ok = get_current_hours_for_actor(&db, "npc", 1)
	testing.expect(t, ok)
	testing.expect_value(t, hours, 6)

	// Invalid actor type
	_, ok = get_current_hours_for_actor(&db, "creature", 1)
	testing.expect(t, !ok, "Invalid actor type should return false")
}

@(test)
test_get_parent_location_id :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Dock Ward (id=2) has parent Waterdeep (id=1)
	parent := get_parent_location_id(&db, 2)
	testing.expect_value(t, parent, 1)

	// Waterdeep (id=1) has no parent (0)
	parent = get_parent_location_id(&db, 1)
	testing.expect_value(t, parent, 0)

	// Non-existent location
	parent = get_parent_location_id(&db, 999)
	testing.expect_value(t, parent, 0)
}

@(test)
test_query_wanted_heat :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// No row yet
	heat, last_hour, found := query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, !found, "Should not find non-existent heat row")
	testing.expect_value(t, heat, 0)

	// Insert a row directly
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,50,100)")

	heat, last_hour, found = query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found, "Should find inserted heat row")
	testing.expect_value(t, heat, 50)
	testing.expect_value(t, last_hour, 100)
}

@(test)
test_get_effective_heat_direct :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Insert heat at Waterdeep (location 1)
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,50,100)")

	raw, decayed, source, tier_info, found := get_effective_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found)
	testing.expect_value(t, raw, 50)
	testing.expect_value(t, source, 1)
	testing.expect_value(t, tier_info.tier, 3)
}

@(test)
test_get_effective_heat_inherited :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Insert heat at Waterdeep (location 1), query at Dock Ward (location 2, child)
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,25,100)")

	raw, decayed, source, tier_info, found := get_effective_heat(&db, "character", 1, 1, 2)
	testing.expect(t, found)
	testing.expect_value(t, raw, 25)
	testing.expect_value(t, source, 1) // Inherited from Waterdeep
	testing.expect_value(t, tier_info.tier, 2) // Wanted
}

@(test)
test_get_effective_heat_override :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Insert heat at Waterdeep (parent)
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,50,100)")
	// Insert explicit override at Dock Ward (child) — e.g., protected by thieves guild
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,2,0,100)")

	raw, decayed, source, tier_info, found := get_effective_heat(&db, "character", 1, 1, 2)
	testing.expect(t, found)
	testing.expect_value(t, raw, 0)
	testing.expect_value(t, source, 2) // From Dock Ward override, not parent
	testing.expect_value(t, tier_info.tier, 0) // Clean
}

@(test)
test_get_effective_heat_not_found :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// No heat at location or any parent
	_, _, _, tier_info, found := get_effective_heat(&db, "character", 1, 1, 3)
	testing.expect(t, !found)
	testing.expect_value(t, tier_info.tier, 0) // Clean
}

@(test)
test_get_effective_heat_with_decay :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Campaign starts at hour 6. Set heat at hour 6 with last_decay_hour = 6.
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,50,6)")
	// Advance campaign time by 336 hours (14 days)
	lib.db_exec(&db, "UPDATE campaigns SET total_elapsed_hours = 342") // 6 + 336

	raw, decayed, source, tier_info, found := get_effective_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found)
	testing.expect_value(t, raw, 50)
	testing.expect_value(t, decayed, 24) // ~half after 14 days
	testing.expect_value(t, tier_info.tier, 2) // Wanted
}

// ---------------------------------------------------------------------------
// Integration tests for CLI procs
// ---------------------------------------------------------------------------

@(test)
test_wanted_crime_creates_heat :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Simulate CLI: args = ["crime", "char", "1", "1", "1", "25", "Stole a horse"]
	args := []string{"crime", "char", "1", "1", "1", "25", "Stole a horse"}
	rc := wanted_crime(&db, args)
	testing.expect_value(t, rc, 0)

	// Verify wanted_heat row
	heat, _, found := query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found, "crime should create heat row")
	testing.expect_value(t, heat, 25)

	// Verify crime_log row
	stmt: ^sqlite.Statement
	check_sql := "SELECT description, severity FROM crime_log WHERE actor_type='character' AND actor_id=1"
	check_c := cstring(raw_data(check_sql))
	testing.expect(t, sqlite.prepare(db.ptr, check_c, i32(len(check_sql)), &stmt, nil) == .Ok)
	defer sqlite.finalize(stmt)
	testing.expect(t, sqlite.step(stmt) == .Row)
	testing.expect_value(t, string(sqlite.column_text(stmt, 0)), "Stole a horse")
	testing.expect_value(t, int(sqlite.column_int(stmt, 1)), 25)
}

@(test)
test_wanted_crime_accumulates :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// First crime
	lib.db_exec(&db, "INSERT INTO wanted_heat (actor_type, actor_id, faction_id, location_id, heat_points, last_decay_hour) VALUES('character',1,1,1,25,6)")

	// Second crime
	args := []string{"crime", "char", "1", "1", "1", "15", "Assaulted a guard"}
	rc := wanted_crime(&db, args)
	testing.expect_value(t, rc, 0)

	heat, _, found := query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found)
	testing.expect_value(t, heat, 40) // 25 + 15
}

@(test)
test_wanted_crime_actor_without_campaign :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Lyra (id=2) has campaign_id=0
	args := []string{"crime", "char", "2", "1", "1", "10", "Petty theft"}
	rc := wanted_crime(&db, args)
	testing.expect_value(t, rc, 0) // Should succeed even without campaign

	heat, _, found := query_wanted_heat(&db, "character", 2, 1, 1)
	testing.expect(t, found)
	testing.expect_value(t, heat, 10)
}

@(test)
test_wanted_set_and_clear :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Set heat
	args_set := []string{"set", "char", "1", "1", "1", "75"}
	rc := wanted_set(&db, args_set)
	testing.expect_value(t, rc, 0)

	heat, _, found := query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, found)
	testing.expect_value(t, heat, 75)

	// Clear heat
	args_clear := []string{"clear", "char", "1", "1", "1"}
	rc = wanted_clear(&db, args_clear)
	testing.expect_value(t, rc, 0)

	_, _, found = query_wanted_heat(&db, "character", 1, 1, 1)
	testing.expect(t, !found, "Heat should be cleared after wanted clear")
}

@(test)
test_wanted_crime_with_npc :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	args := []string{"crime", "npc", "1", "1", "2", "30", "Extortion"}
	rc := wanted_crime(&db, args)
	testing.expect_value(t, rc, 0)

	heat, _, found := query_wanted_heat(&db, "npc", 1, 1, 2)
	testing.expect(t, found)
	testing.expect_value(t, heat, 30)
}

@(test)
test_wanted_invalid_actor_type :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	args := []string{"crime", "creature", "1", "1", "1", "10", "test"}
	rc := wanted_crime(&db, args)
	testing.expect(t, rc != 0, "Should fail with invalid actor type")
}

@(test)
test_wanted_missing_args :: proc(t: ^testing.T) {
	db := setup_test_db(t)
	defer sqlite.close(db.ptr)

	// Too few args for crime
	args := []string{"crime", "char", "1"}
	rc := wanted_crime(&db, args)
	testing.expect(t, rc != 0, "Should fail with missing args")

	// Too few args for get
	args_get := []string{"get", "char"}
	rc = wanted_get(&db, args_get)
	testing.expect(t, rc != 0, "Should fail with missing args")
}
