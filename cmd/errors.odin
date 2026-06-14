package cmd

import "core:fmt"
import lib "../lib"

// Error codes are stable, machine-readable identifiers. Agents should
// branch on `code`, not on the human-readable `error` string. The `error`
// string is prompt-shaped: it explains what went wrong and often tells
// the agent what to do next (which command to call, what argument to fix).
//
// Codes follow the pattern `<DOMAIN>_<SPECIFIC_STATE>` and are
// SCREAMING_SNAKE_CASE. Adding a new code is backwards-compatible;
// renaming or removing a code is a breaking change for agent consumers.

Error_Code :: enum {
	// --- Generic ---
	USAGE,                      // Missing or invalid arguments
	VALIDATION,                 // Argument passed but value is out of range or wrong shape
	NOT_FOUND,                  // Entity ID doesn't exist
	CONFLICT,                   // Uniqueness constraint violated
	DB_ERROR,                   // Database operation failed (lock, I/O, schema)
	INTERNAL,                   // Catch-all for unexpected failures

	// --- Combat ---
	COMBAT_NOT_FOUND,
	COMBAT_ALREADY_ACTIVE,
	COMBAT_NOT_ACTIVE,
	COMBAT_NOT_IN_ENCOUNTER,
	COMBAT_TURN_ADVANCE_FAILED,
	COMBAT_NO_ACTIONS_REMAIN,
	COMBAT_NO_REACTIONS_REMAIN,
	COMBAT_ATTACK_RESOLVE_FAILED,
	COMBAT_DAMAGE_APPLY_FAILED,
	COMBAT_INVALID_POSITION,
	COMBAT_REQUIRES_INIT,

	// --- Combat / Spellcasting ---
	SPELL_NOT_FOUND,
	SPELL_NOT_KNOWN,
	SPELL_NOT_PREPARED,
	SPELL_SLOT_EXHAUSTED,
	SPELL_SLOT_LEVEL_INVALID,
	SPELL_NO_CONCENTRATION,
	SPELL_CANNOT_CONCENTRATE,

	// --- Character state ---
	CHARACTER_NOT_FOUND,
	CHARACTER_DEAD,             // HP = 0, cannot act
	CHARACTER_NO_HP,
	CHARACTER_NO_TEMP_HP,
	CHARACTER_INSURVIVABLE,     // damage would take HP below -max_hp

	// --- NPC state ---
	NPC_NOT_FOUND,

	// --- Creature state ---
	CREATURE_NOT_FOUND,

	// --- Combat / Conditions ---
	CONDITION_NOT_FOUND,
	CONDITION_ALREADY_PRESENT,

	// --- Resource / Rest ---
	RESOURCE_NOT_FOUND,
	RESOURCE_EXHAUSTED,
	NO_HIT_DICE,
	NO_SHORT_RESTS_REMAIN,
	NO_LONG_RESTS_REMAIN,
	REST_BLOCKED_BY_COMBAT,     // Active combat blocks long rest
	REST_BLOCKED_BY_DURATION,   // Active duration-based condition prevents rest

	// --- Combat / Death saves ---
	DEATH_SAVE_NOT_DEAD,
	DEATH_SAVE_INVALID,
	DEATH_SAVE_NATURAL_20,
	DEATH_SAVE_NATURAL_1,

	// --- Inventory / Items ---
	ITEM_NOT_FOUND,
	ITEM_NOT_IN_INVENTORY,
	INVENTORY_FULL,
	INVENTORY_QUANTITY_INVALID,
	INVENTORY_ALREADY_EQUIPPED,
	INVENTORY_ALREADY_ATTUNED,
	INVENTORY_ATTUNEMENT_LIMIT,

	// --- Faction / Standings ---
	FACTION_NOT_FOUND,
	STANDING_INVALID,
	STANDING_INVALID_RANGE,

	// --- Shop / Economy ---
	SHOP_NOT_FOUND,
	SHOP_CLOSED,
	SHOP_OUT_OF_STOCK,
	SHOP_INSUFFICIENT_FUNDS,
	SHOP_NOT_AFFORDABLE,        // character can't afford
	SHOP_BUYBACK_TOO_EXPENSIVE,  // shop can't afford to buy back
	SHOP_HAGGLE_EXHAUSTED,       // out of haggle attempts today
	SHOP_HAGGLE_DC,
	SHOP_MAX_VALUE_EXCEEDED,
	SHOP_INVALID_QUANTITY,

	// --- Quests ---
	QUEST_NOT_FOUND,
	QUEST_OBJECTIVE_NOT_FOUND,
	QUEST_ALREADY_COMPLETE,
	QUEST_ALREADY_FAILED,
	QUEST_INVALID_STATUS,

	// --- World / Locations ---
	LOCATION_NOT_FOUND,
	LOCATION_IS_PARENT,         // location cannot be its own parent
	LOCATION_HAS_PARENT,        // already has a parent
	LOCATION_NOT_IN_CAMPAIGN,
	HOUSE_NOT_FOUND,
	HOUSE_HAS_RESIDENT,
	HOUSE_FULL,
	SHOP_NOT_IN_LOCATION,

	// --- Wanted / Crime ---
	WANTED_NOT_FOUND,
	CRIME_LOG_FAILED,

	// --- Time / Calendar ---
	TIME_INVALID,
	TIME_REWIND_DETECTED,       // calendar set-calendar went backwards

	// --- Companion ---
	COMPANION_NOT_FOUND,
	COMPANION_INVALID_LEVEL,

	// --- Permissions / Access ---
	ACCESS_DENIED,
	RESTRICTED,                 // access blocked by restricted location

	// --- Trades ---
	TRADE_RECIPIENT_NOT_FOUND,
	TRADE_SENDER_NOT_FOUND,
	TRADE_INSUFFICIENT_FUNDS,
	TRADE_NEGATIVE_QUANTITY,

	// --- Dice / Math ---
	INVALID_DICE_SPEC,
}

Error_Response :: struct {
	code:      Error_Code,
	message:   string,
	retryable: bool,
}

error_response :: proc(db: ^lib.Db, code: Error_Code, message: string, retryable: bool) -> int {
	code_str := error_code_str(code)
	if db.is_json {
		fmt.printf(
			`{{"success":false,"code":"%s","error":"%s","retryable":%t}}` + "\n",
			code_str,
			escape_json_string(message),
			retryable,
		)
	} else {
		fmt.eprintln(message)
	}
	return 1
}

// error_code_str returns the SCREAMING_SNAKE_CASE string form of a code.
// Kept as a switch so the enum and string stay in lockstep.
error_code_str :: proc(code: Error_Code) -> string {
	#partial switch code {
	case .USAGE:                       return "USAGE"
	case .VALIDATION:                  return "VALIDATION"
	case .NOT_FOUND:                   return "NOT_FOUND"
	case .CONFLICT:                    return "CONFLICT"
	case .DB_ERROR:                    return "DB_ERROR"
	case .INTERNAL:                    return "INTERNAL"
	case .COMBAT_NOT_FOUND:            return "COMBAT_NOT_FOUND"
	case .COMBAT_ALREADY_ACTIVE:       return "COMBAT_ALREADY_ACTIVE"
	case .COMBAT_NOT_ACTIVE:           return "COMBAT_NOT_ACTIVE"
	case .COMBAT_NOT_IN_ENCOUNTER:     return "COMBAT_NOT_IN_ENCOUNTER"
	case .COMBAT_TURN_ADVANCE_FAILED:  return "COMBAT_TURN_ADVANCE_FAILED"
	case .COMBAT_NO_ACTIONS_REMAIN:    return "COMBAT_NO_ACTIONS_REMAIN"
	case .COMBAT_NO_REACTIONS_REMAIN:  return "COMBAT_NO_REACTIONS_REMAIN"
	case .COMBAT_ATTACK_RESOLVE_FAILED: return "COMBAT_ATTACK_RESOLVE_FAILED"
	case .COMBAT_DAMAGE_APPLY_FAILED:  return "COMBAT_DAMAGE_APPLY_FAILED"
	case .COMBAT_INVALID_POSITION:     return "COMBAT_INVALID_POSITION"
	case .COMBAT_REQUIRES_INIT:        return "COMBAT_REQUIRES_INIT"
	case .SPELL_NOT_FOUND:             return "SPELL_NOT_FOUND"
	case .SPELL_NOT_KNOWN:             return "SPELL_NOT_KNOWN"
	case .SPELL_NOT_PREPARED:          return "SPELL_NOT_PREPARED"
	case .SPELL_SLOT_EXHAUSTED:        return "SPELL_SLOT_EXHAUSTED"
	case .SPELL_SLOT_LEVEL_INVALID:    return "SPELL_SLOT_LEVEL_INVALID"
	case .SPELL_NO_CONCENTRATION:      return "SPELL_NO_CONCENTRATION"
	case .SPELL_CANNOT_CONCENTRATE:    return "SPELL_CANNOT_CONCENTRATE"
	case .CHARACTER_NOT_FOUND:         return "CHARACTER_NOT_FOUND"
	case .CHARACTER_DEAD:              return "CHARACTER_DEAD"
	case .CHARACTER_NO_HP:             return "CHARACTER_NO_HP"
	case .CHARACTER_NO_TEMP_HP:        return "CHARACTER_NO_TEMP_HP"
	case .CHARACTER_INSURVIVABLE:      return "CHARACTER_INSURVIVABLE"
	case .NPC_NOT_FOUND:               return "NPC_NOT_FOUND"
	case .CREATURE_NOT_FOUND:          return "CREATURE_NOT_FOUND"
	case .CONDITION_NOT_FOUND:         return "CONDITION_NOT_FOUND"
	case .CONDITION_ALREADY_PRESENT:   return "CONDITION_ALREADY_PRESENT"
	case .RESOURCE_NOT_FOUND:          return "RESOURCE_NOT_FOUND"
	case .RESOURCE_EXHAUSTED:          return "RESOURCE_EXHAUSTED"
	case .NO_HIT_DICE:                 return "NO_HIT_DICE"
	case .NO_SHORT_RESTS_REMAIN:       return "NO_SHORT_RESTS_REMAIN"
	case .NO_LONG_RESTS_REMAIN:        return "NO_LONG_RESTS_REMAIN"
	case .REST_BLOCKED_BY_COMBAT:      return "REST_BLOCKED_BY_COMBAT"
	case .REST_BLOCKED_BY_DURATION:    return "REST_BLOCKED_BY_DURATION"
	case .DEATH_SAVE_NOT_DEAD:         return "DEATH_SAVE_NOT_DEAD"
	case .DEATH_SAVE_INVALID:          return "DEATH_SAVE_INVALID"
	case .DEATH_SAVE_NATURAL_20:       return "DEATH_SAVE_NATURAL_20"
	case .DEATH_SAVE_NATURAL_1:        return "DEATH_SAVE_NATURAL_1"
	case .ITEM_NOT_FOUND:              return "ITEM_NOT_FOUND"
	case .ITEM_NOT_IN_INVENTORY:       return "ITEM_NOT_IN_INVENTORY"
	case .INVENTORY_FULL:              return "INVENTORY_FULL"
	case .INVENTORY_QUANTITY_INVALID:  return "INVENTORY_QUANTITY_INVALID"
	case .INVENTORY_ALREADY_EQUIPPED:  return "INVENTORY_ALREADY_EQUIPPED"
	case .INVENTORY_ALREADY_ATTUNED:   return "INVENTORY_ALREADY_ATTUNED"
	case .INVENTORY_ATTUNEMENT_LIMIT:  return "INVENTORY_ATTUNEMENT_LIMIT"
	case .FACTION_NOT_FOUND:           return "FACTION_NOT_FOUND"
	case .STANDING_INVALID:            return "STANDING_INVALID"
	case .STANDING_INVALID_RANGE:      return "STANDING_INVALID_RANGE"
	case .SHOP_NOT_FOUND:              return "SHOP_NOT_FOUND"
	case .SHOP_CLOSED:                 return "SHOP_CLOSED"
	case .SHOP_OUT_OF_STOCK:           return "SHOP_OUT_OF_STOCK"
	case .SHOP_INSUFFICIENT_FUNDS:     return "SHOP_INSUFFICIENT_FUNDS"
	case .SHOP_NOT_AFFORDABLE:         return "SHOP_NOT_AFFORDABLE"
	case .SHOP_BUYBACK_TOO_EXPENSIVE:  return "SHOP_BUYBACK_TOO_EXPENSIVE"
	case .SHOP_HAGGLE_EXHAUSTED:       return "SHOP_HAGGLE_EXHAUSTED"
	case .SHOP_HAGGLE_DC:              return "SHOP_HAGGLE_DC"
	case .SHOP_MAX_VALUE_EXCEEDED:     return "SHOP_MAX_VALUE_EXCEEDED"
	case .SHOP_INVALID_QUANTITY:       return "SHOP_INVALID_QUANTITY"
	case .QUEST_NOT_FOUND:             return "QUEST_NOT_FOUND"
	case .QUEST_OBJECTIVE_NOT_FOUND:   return "QUEST_OBJECTIVE_NOT_FOUND"
	case .QUEST_ALREADY_COMPLETE:      return "QUEST_ALREADY_COMPLETE"
	case .QUEST_ALREADY_FAILED:        return "QUEST_ALREADY_FAILED"
	case .QUEST_INVALID_STATUS:        return "QUEST_INVALID_STATUS"
	case .LOCATION_NOT_FOUND:          return "LOCATION_NOT_FOUND"
	case .LOCATION_IS_PARENT:          return "LOCATION_IS_PARENT"
	case .LOCATION_HAS_PARENT:         return "LOCATION_HAS_PARENT"
	case .LOCATION_NOT_IN_CAMPAIGN:    return "LOCATION_NOT_IN_CAMPAIGN"
	case .HOUSE_NOT_FOUND:             return "HOUSE_NOT_FOUND"
	case .HOUSE_HAS_RESIDENT:          return "HOUSE_HAS_RESIDENT"
	case .HOUSE_FULL:                  return "HOUSE_FULL"
	case .SHOP_NOT_IN_LOCATION:        return "SHOP_NOT_IN_LOCATION"
	case .WANTED_NOT_FOUND:            return "WANTED_NOT_FOUND"
	case .CRIME_LOG_FAILED:            return "CRIME_LOG_FAILED"
	case .TIME_INVALID:                return "TIME_INVALID"
	case .TIME_REWIND_DETECTED:        return "TIME_REWIND_DETECTED"
	case .COMPANION_NOT_FOUND:         return "COMPANION_NOT_FOUND"
	case .COMPANION_INVALID_LEVEL:     return "COMPANION_INVALID_LEVEL"
	case .ACCESS_DENIED:               return "ACCESS_DENIED"
	case .RESTRICTED:                  return "RESTRICTED"
	case .TRADE_RECIPIENT_NOT_FOUND:   return "TRADE_RECIPIENT_NOT_FOUND"
	case .TRADE_SENDER_NOT_FOUND:      return "TRADE_SENDER_NOT_FOUND"
	case .TRADE_INSUFFICIENT_FUNDS:    return "TRADE_INSUFFICIENT_FUNDS"
	case .TRADE_NEGATIVE_QUANTITY:     return "TRADE_NEGATIVE_QUANTITY"
	case .INVALID_DICE_SPEC:           return "INVALID_DICE_SPEC"
	}
	return "INTERNAL"
}

// Standard usage error helper. Used by command procs that detect
// wrong arg count and want a stable USAGE code.
usage_error :: proc(db: ^lib.Db, usage: string) -> int {
	return error_response(db, .USAGE, usage, false)
}

// Standard not-found helper. Use for "entity ID doesn't exist" cases.
not_found :: proc(db: ^lib.Db, entity: string, id: int) -> int {
	return error_response(
		db,
		.NOT_FOUND,
		fmt.tprintf("%s %d not found", entity, id),
		false,
	)
}

// Standard DB error helper. Use when SQLite returns an error from
// exec/prepare/step. The error message includes the entity being
// operated on for agent diagnostics.
db_error :: proc(db: ^lib.Db, op: string, entity: string) -> int {
	return error_response(
		db,
		.DB_ERROR,
		fmt.tprintf("Failed to %s %s. The database may be locked or the entity may be in a conflicting state.", op, entity),
		true,
	)
}
