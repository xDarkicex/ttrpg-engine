package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import lib "lib"
import cmd "cmd"

SubcommandHelp :: struct {
	name: string,
	args: string,
	description: string,
}

CommandHelp :: struct {
	command: string,
	description: string,
	subcommands: []SubcommandHelp,
}

HELP_COMMANDS := []CommandHelp{
	{
		command = "character",
		description = "Manage player characters and their stats.",
		subcommands = []SubcommandHelp{
			{"create", "<name> <class> <level> <max_hp>", "Create a new character sheet."},
			{"list", "", "List all characters."},
			{"get", "<id>", "Show detailed character sheet (stats, saves, equipment, party, last action)."},
			{"delete", "<id>", "Delete a character."},
			{"damage", "<id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll] [source]", "Environmental/trap/non-combat damage. Applies type modifiers, temp HP, saves, AC checks. Source describes origin (e.g. lava pit)."},
			{"heal", "<id> <amount> [source]", "Restore hit points up to max HP. Optional source for narrative (e.g. healing potion)."},
			{"set-stats", "<id> <str> <dex> <con> <int> <wis> <cha>", "Configure base ability scores."},
			{"set-save-prof", "<id> <str> <dex> <con> <int> <wis> <cha>", "Set saving throw proficiencies (0 or 1)."},
			{"set-details", "<id> <ac> <race> <speed> [alignment] [size]", "Set AC, race, movement speed, alignment, and size."},
			{"set-combat-meta", "<id> <resistances> <vulnerabilities> <immunities>", "Configure damage modifications (comma-separated)."},
			{"set-status", "<id> <status_effects>", "Set active status conditions (comma-separated)."},
			{"set-action", "<id> <action>", "Record the last action performed by this character."},
			{"set-party", "<id> <party_name>", "Assign character to a party."},
			{"set-campaign", "<id> <campaign_id>", "Assign character to a campaign."},
			{"add-class", "<char_id> <class_name> <level>", "Add or update levels in a class (supports multiclassing)."},
			{"list-classes", "<char_id>", "List classes and levels for a character."},
			{"add-xp", "<id> <amount>", "Reward experience points (XP)."},
			{"add-money", "<id> <gold> <silver> <copper> [platinum] [electrum]", "Add coins to character inventory."},
			{"remove-money", "<id> <gold> <silver> <copper> [platinum] [electrum]", "Deduct coins from character inventory."},
			{"set-temp-hp", "<id> <amount>", "Set temporary hit points."},
			{"set-death-saves", "<id> <successes> <failures>", "Set death saves (0 to 3)."},
			{"set-exhaustion", "<id> <level>", "Set exhaustion level (0 to 6)."},
			{"set-hit-dice", "<id> <expended>", "Set expended hit dice count."},
			{"set-inspiration", "<id> <0/1>", "Set DM-awarded inspiration (0 or 1)."},
			{"set-rests", "<id> <short_rests> <long_rests>", "Set available short and long rests."},
			{"set-backstory", "<id> <backstory>", "Set character backstory."},
			{"set-location", "<id> <location_id>", "Link character to a campaign location."},
			{"set-chapter", "<id> <chapter_id>", "Set character active campaign chapter."},
			{"set-owner", "<id> <owner_name>", "Set player owner name of the character."},
			{"set-skill", "<char_id> <skill_name> <proficiency_level>", "Set skill level (0=none, 1=prof, 2=expertise)."},
			{"list-skills", "<char_id>", "List character skills and proficiencies."},
			{"set-resource", "<char_id> <resource_name> <max> <current> [reset_condition]", "Configure a class resource or spell slot pool."},
			{"use-resource", "<char_id> <resource_name> [amount]", "Use a specific resource amount (default 1)."},
			{"reset-resources", "<char_id> [reset_condition]", "Reset character resources (e.g. on long_rest)."},
			{"list-resources", "<char_id>", "List resources for a character."},
			{"set-gender", "<id> <gender>", "Set character gender."},
			{"set-age", "<id> <age>", "Set character age."},
		},
	},
	{
		command = "companion",
		description = "Manage character companions, familiars, and pets.",
		subcommands = []SubcommandHelp{
			{"create", "<char_id> <name> <type> <level> <max_hp> <ac> <attack_bonus> <damage_dice>", "Spawn a companion linked to a character."},
			{"set-stats", "<id> <str> <dex> <con> <int> <wis> <cha>", "Set companion ability scores."},
			{"list", "[char_id]", "List all companions (optionally filtered by owner character ID)."},
			{"get", "<id>", "Display companion sheet."},
			{"damage", "<id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]", "Apply damage with saving throws and resistances."},
			{"heal", "<id> <amount>", "Heal a companion."},
		},
	},
	{
		command = "creature",
		description = "Manage enemies, villains, and monsters for DM combat tracking.",
		subcommands = []SubcommandHelp{
			{"create", "<name> <max_hp> <ac> <attacks> <story_role> <campaign_id>", "Create a new creature preset."},
			{"list", "", "Display active creatures."},
			{"get", "<id>", "Display creature details."},
			{"damage", "<id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]", "Apply damage to a creature."},
			{"heal", "<id> <amount>", "Heal a creature."},
			{"set-status", "<id> <status_effects>", "Update active status conditions."},
			{"set-combat-meta", "<id> <resistances> <vulnerabilities> <immunities>", "Configure creature resistances/vulnerabilities/immunities."},
			{"set-action", "<id> <action>", "Set creature's last combat action."},
			{"set-location", "<creature_id> <location_id>", "Link creature to a campaign location."},
			{"set-stats", "<id> <str> <dex> <con> <int> <wis> <cha>", "Set creature ability scores."},
			{"add-money", "<id> <gold> <silver> <copper> [platinum] [electrum]", "Add loot money to a creature."},
			{"remove-money", "<id> <gold> <silver> <copper> [platinum] [electrum]", "Remove loot money from a creature."},
			{"add-ability", "<creature_id> <feature_id>", "Link a feature/ability to a creature."},
			{"remove-ability", "<creature_id> <feature_id>", "Remove a feature/ability from a creature."},
			{"list-abilities", "<creature_id>", "List abilities of a creature."},
		},
	},
	{
		command = "faction",
		description = "Manage campaign factions and character standings.",
		subcommands = []SubcommandHelp{
			{"create", "<name> <description>", "Define a new faction."},
			{"list", "", "List all active factions."},
			{"join", "<char|npc> <id> <faction_id>", "Make a character or NPC join a faction."},
			{"set-standing", "<character_id> <faction_id> <standing> [notes]", "Set standing reputation (integer) and notes with a faction."},
			{"get-standing", "<character_id> [faction_id]", "Retrieve faction standings for a character (all or filtered by faction ID)."},
				{"set-party-standing", "<campaign_id> <faction_id> <standing> [notes]", "Set party-wide institutional standing with a faction."},
				{"get-party-standing", "<campaign_id> [faction_id]", "Retrieve party faction standings for a campaign."},
				{"effective-standing", "<campaign_id> <faction_id>", "Computed effective standing (party + avg character). Non-canonical display."},
		},
	},
	{
		command = "item",
		description = "Upsert and list campaign items.",
		subcommands = []SubcommandHelp{
			{"upsert", "<name> <description> <type> [damage_dice] [damage_type] [ac_bonus] [properties] [weight] [value_gp]", "Create or update an item definition."},
			{"list", "", "List all items in the campaign database."},
		},
	},
	{
		command = "inventory",
		description = "Manage character, NPC, and creature inventories.",
		subcommands = []SubcommandHelp{
			{"add", "<char|npc|creature> <id> <item_id> <qty>", "Add items to inventory."},
			{"remove", "<char|npc|creature> <id> <item_id> <qty>", "Deduct items from inventory."},
			{"get", "<char|npc|creature> <id>", "Display entity inventory list."},
			{"equip", "<char|npc|creature> <id> <item_id> <0/1>", "Toggle item equipment status."},
			{"attune", "<char|npc|creature> <id> <item_id> <0/1>", "Toggle item attunement status."},
		},
	},
	{
		command = "npc",
		description = "Manage story NPCs, Daily/Story Roles, and Relationships.",
		subcommands = []SubcommandHelp{
			{"create", "<name> <desc> <max_hp> <camp_id>", "Create a new NPC."},
			{"list", "", "List all NPCs."},
			{"get", "<id>", "Display NPC details including active location and relationships."},
			{"delete", "<id>", "Delete an NPC."},
			{"damage", "<id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]", "Apply combat damage to an NPC."},
			{"heal", "<id> <amount>", "Heal an NPC."},
			{"set-details", "<id> <ac> <story_role> <daily_role> <backstory>", "Set detailed NPC role and backstory information."},
			{"set-stats", "<id> <str> <dex> <con> <int> <wis> <cha>", "Set NPC ability scores."},
			{"set-combat-meta", "<id> <resistances> <vulnerabilities> <immunities>", "Configure NPC combat vulnerabilities/resistances."},
			{"set-status", "<id> <status_effects>", "Set active status conditions."},
			{"add-money", "<id> <gold> <silver> <copper>", "Add coins to NPC inventory."},
			{"remove-money", "<id> <gold> <silver> <copper>", "Deduct coins from NPC inventory."},
			{"set-action", "<id> <action>", "Record last action by NPC."},
			{"set-relationship", "<npc_id_1> <npc_id_2> <friendship_level> [notes]", "Define relationship standing (-10 to +10) between two NPCs."},
			{"list-relationships", "<npc_id>", "List relationships of a specific NPC."},
			{"set-location", "<npc_id> <location_id>", "Link NPC to a campaign location."},
			{"add-ability", "<npc_id> <feature_id>", "Link a feature/ability to an NPC."},
			{"remove-ability", "<npc_id> <feature_id>", "Remove a feature/ability from an NPC."},
			{"list-abilities", "<npc_id>", "List abilities of an NPC."},
		},
	},
	{
		command = "spell",
		description = "Manage spell definitions and character spellbooks.",
		subcommands = []SubcommandHelp{
			{"upsert", "<name> <level> <school> <casting_time> <range> <components> <duration> <description>", "Define or update a spell."},
			{"list", "", "List all spells in the spell library."},
			{"learn", "<char_id> <spell_id> [prepared (0/1)] [class_name] [source]", "Make a character learn a spell."},
			{"forget", "<char_id> <spell_id>", "Remove a spell entirely from a character."},
			{"prepare", "<char_id> <spell_id> <0/1>", "Prepare or unprepare a spell for a character."},
			{"list-character", "<char_id>", "List spellbook and preparation state for a character."},
		},
	},
	{
		command = "feature",
		description = "Configure race/class features and character trait benefits.",
		subcommands = []SubcommandHelp{
			{"upsert", "<name> <source> <description>", "Create/modify a special feature."},
			{"list", "", "List all features in database."},
			{"add-to-char", "<char_id> <feature_id>", "Grant a feature to a character."},
			{"list-character", "<char_id>", "List features possessed by a character."},
		},
	},
	{
		command = "class-specialty",
		description = "Define class specialties and special level-gained abilities.",
		subcommands = []SubcommandHelp{
			{"upsert", "<class_name> <level> <ability_name> <description>", "Define level-specific class specialty."},
			{"list", "[class_name]", "List all specialties (optionally filtered by class)."},
		},
	},
	{
		command = "condition",
		description = "Manage active D&D 5e conditions (restrained, prone, etc.) on any entity.",
		subcommands = []SubcommandHelp{
			{"add", "<character|npc|creature> <id> <name> [source] [duration_rounds] [save_dc] [save_ability]", "Apply a condition to an entity. Source explains the origin (e.g. Web). Save fields are for effects that end on save."},
			{"list", "<character|npc|creature> <id>", "List active conditions on an entity."},
			{"remove", "<character|npc|creature> <id> <name>", "Remove a condition by name."},
		},
	},
		{
			command = "combat",
			description = "Manage D&D 5e combat encounters with turn tracking, attack resolution, damage application, and condition handling.",
			subcommands = []SubcommandHelp{
				{"start", "<campaign_id> <location_id>", "Create a new combat encounter."},
				{"join", "<encounter_id> <char|npc|creature> <id> <initiative> [mod] [position]", "Add a participant to the encounter."},
				{"join-all", "<encounter_id>", "Auto-add all characters/creatures with combat=1 at the encounter location."},
				{"init", "<encounter_id>", "Lock turn order sorted by initiative (descending)."},
				{"next", "<encounter_id>", "Advance to the next turn. Resets reactions on new rounds."},
				{"attack", "<encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <roll> [ability] [adv|disadv]", "Resolve an attack roll vs target AC."},
				{"damage", "<encounter_id> <target_type> <target_id> <amount> <type> [source]", "Apply damage with resistance/vulnerability/immunity."},
				{"save", "<encounter_id> <actor_type> <actor_id> <ability> <roll> [dc] [adv|disadv]", "Resolve a saving throw."},
				{"move", "<encounter_id> <actor_type> <actor_id> <position>", "Change position (melee, ranged, cover, hidden, fleeing)."},
				{"condition", "<encounter_id> <target_type> <target_id> <name> [dur] [dc] [save]", "Apply a condition during combat."},
				{"death-save", "<character_id> <roll>", "Roll a death saving throw."},
				{"react", "<encounter_id> <actor_type> <actor_id> <reaction> [target_type] [target_id]", "Use a reaction."},
				{"ready", "<encounter_id> <actor_type> <actor_id> \"<action>\" <trigger>", "Ready an action with a trigger condition."},
				{"status", "<encounter_id>", "Show full combat state."},
				{"end", "<encounter_id>", "End the encounter and archive it."},
			},
		},
		{
			command = "rest",
			description = "Take a short or long rest to recover HP, hit dice, spell slots, and resources.",
			subcommands = []SubcommandHelp{
				{"short", "<character_id> <hit_dice_count>", "Short rest: spend hit dice to heal, reset short-rest resources."},
				{"long", "<character_id>", "Long rest: full heal, recover half hit dice, reset all resources and spell slots."},
			},
		},
			{
				command = "quest",
			description = "Manage campaign quests with objectives and actor tracking.",
			subcommands = []SubcommandHelp{
				{"add", "<campaign_id> <name> [description] [quest_giver_npc_id] [reward] [chapter]", "Create a new quest."},
				{"add-objective", "<quest_id> <description> [sort_order]", "Add a step to a quest."},
				{"complete-objective", "<objective_id>", "Mark an objective as complete."},
				{"set-status", "<quest_id> <active|completed|failed|abandoned>", "Update quest status."},
				{"add-actor", "<quest_id> <char|npc> <actor_id> [role]", "Link a character or NPC to a quest."},
				{"list", "<campaign_id> [status]", "List quests for a campaign."},
				{"get", "<quest_id>", "Show full quest details with objectives and actors."},
			},
		},
	{
		command = "campaign",
		description = "Track sessions, chapters, current active locations, story progress, and DM campaign logs.",
		subcommands = []SubcommandHelp{
			{"create", "<name>", "Start a new campaign."},
			{"list", "", "List campaigns."},
			{"get", "<id>", "Display brief campaign stats."},
			{"delete", "<id>", "Delete a campaign."},
			{"set-chapter", "<id> <chapter>", "Configure campaign's current chapter."},
			{"next-session", "<id>", "Advance campaign session number by 1."},
			{"add-location", "<campaign_id> <name> <description> [chapter]", "Add location to campaign."},
			{"set-location", "<campaign_id> <location_id>", "Set campaign's current active location."},
			{"list-locations", "<campaign_id>", "List all locations in campaign."},
			{"add-action", "<campaign_id> <description> [location_id] [faction_id] [standing_impact] [story_progression] [status]", "Log a plot/story action impacting factions/story state."},
			{"link-actor", "<action_id> <char|npc> <actor_id>", "Link character/NPC to a logged campaign action."},
			{"list-actions", "<campaign_id> [location_id]", "List story actions in campaign."},
			{"get-story-state", "<campaign_id>", "Show full campaign context packet: locations tree, journal, quests, standings, story log."},
				{"add-journal-entry", "<campaign_id> <entry_type> <description> [location_id] [session_num]", "Add a timestamped journal entry for session recaps."},
				{"list-journal", "<campaign_id> [limit]", "List recent journal entries for a campaign."},
				{"set-dm-notes", "<campaign_id> <text>", "Set private DM notes for a campaign."},
				{"set-time", "<campaign_id> <in_game_day> <time_of_day> <season>", "Set in-game calendar state."},
		},
	},
	{
		command = "init",
		description = "Create and initialize database schema.",
		subcommands = nil,
	},
	{
		command = "help",
		description = "Print commands list and usage.",
		subcommands = nil,
	},
}

main :: proc() {
	is_json := false
	filtered_args := make([dynamic]string, context.temp_allocator)
	for arg in os.args {
		if arg == "--json" || arg == "-j" {
			is_json = true
		} else {
			append(&filtered_args, arg)
		}
	}

	if len(filtered_args) < 2 {
		print_usage(is_json)
		os.exit(1)
	}

	db, db_err := lib.db_open("dnd-agent.db")
	if db_err != lib.Error.None {
		fmt.eprintln("Failed to open DB:", db_err)
		os.exit(1)
	}
	db.is_json = is_json

	if lib.db_init_schema(&db) != lib.Error.None {
		fmt.eprintln("Failed to init schema")
		lib.db_close(&db)
		os.exit(1)
	}

	ec := route_command(&db, filtered_args[1], filtered_args[2:])
	lib.db_close(&db)
	os.exit(ec)
}

route_command :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "character", "item", "inventory", "npc", "spell", "feature", "companion", "creature", "faction", "class-specialty":
		return route_game_command(db, cmd_name, args)
	case "condition":
		return route_condition(db, args)
		case "combat":
			return route_combat(db, args)
		case "rest":
			return route_rest(db, args)
	case "location", "house", "shop", "encounter", "setpiece":
		return route_world(db, cmd_name, args)
	case "can-enter":
		return route_can_enter(db, args)
	case "quest":
		return route_quest(db, args)
	case "campaign", "init", "help":
		return route_meta_command(db, cmd_name, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown command"}`)
		} else {
			fmt.eprintln("Unknown command:", cmd_name)
			print_usage()
		}
		return 1
	}
}

route_game_command :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "character", "npc", "companion", "creature":
		return route_actor_command(db, cmd_name, args)
	case "item", "inventory", "spell", "feature", "faction", "class-specialty":
		return route_asset_command(db, cmd_name, args)
	}
	return 1
}

route_actor_command :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "character": return route_character(db, args)
	case "npc":       return route_npc(db, args)
	case "companion": return route_companion(db, args)
	case "creature":  return route_creature(db, args)
	}
	return 1
}

route_asset_command :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "item":      return route_item(db, args)
	case "inventory": return route_inventory(db, args)
	case "spell":     return route_spell(db, args)
	case "feature":   return route_feature(db, args)
	case "faction":   return route_faction(db, args)
	case "class-specialty": return route_specialty(db, args)
	}
	return 1
}

route_specialty :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent class-specialty <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent class-specialty <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "upsert": return cmd.specialty_upsert(db, args)
	case "list":   return cmd.specialty_list(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown class-specialty subcommand"}`)
		} else {
			fmt.eprintln("Unknown class-specialty subcommand:", sub)
		}
		return 1
	}
}

route_quest :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent quest <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent quest <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "add":                return cmd.quest_add(db, args)
	case "add-objective":     return cmd.quest_add_objective(db, args)
	case "complete-objective": return cmd.quest_complete_objective(db, args)
	case "set-status":        return cmd.quest_set_status(db, args)
	case "add-actor":         return cmd.quest_add_actor(db, args)
	case "list":              return cmd.quest_list(db, args)
	case "get":               return cmd.quest_get(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown quest subcommand"}`)
		} else {
			fmt.eprintln("Unknown quest subcommand:", sub)
		}
		return 1
	}
}

route_meta_command :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "campaign": return route_campaign(db, args)
	case "init":
		if db.is_json {
			fmt.println(`{"success":true,"message":"dnd-agent initialized"}`)
		} else {
			fmt.println("dnd-agent initialized.")
		}
		return 0
	case "help":
		print_usage(db.is_json)
		return 0
	}
	return 1
}

route_character :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent character <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent character <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create", "list", "get", "delete", "damage", "heal":
		return route_character_core(db, sub, args)
	case "set-stats", "set-save-prof", "set-details", "set-combat-meta", "set-status", "set-action", "add-class", "list-classes", "add-xp", "add-money", "remove-money", "set-party", "set-campaign", "set-temp-hp", "set-death-saves", "set-exhaustion", "set-hit-dice", "set-inspiration", "set-rests", "set-backstory", "set-location", "set-chapter", "set-owner", "set-skill", "list-skills", "set-resource", "use-resource", "reset-resources", "list-resources", "set-proficiency", "set-spellcasting", "set-initiative", "set-passive-perception", "set-languages", "set-max-hit-dice", "set-combat", "set-concentrating", "add-prof", "remove-prof", "set-spell-slot", "set-darkvision", "set-bond", "set-flaw", "set-ideal", "set-personality-traits", "set-appearance", "set-gender", "set-age":
		return route_character_setters(db, sub, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown character subcommand"}`)
		} else {
			fmt.eprintln("Unknown character subcommand:", sub)
		}
		return 1
	}
}

route_character_core :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "create": return cmd.character_create(db, args)
	case "list":   return cmd.character_list(db)
	case "get":    return cmd.character_get(db, args)
	case "delete": return cmd.character_delete(db, args)
	case "damage": return cmd.character_damage(db, args)
	case "heal":   return cmd.character_heal(db, args)
	}
	return 1
}

route_character_setters :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "set-stats":       return cmd.character_set_stats(db, args)
	case "set-save-prof":   return cmd.character_set_save_prof(db, args)
	case "set-details":     return cmd.character_set_details(db, args)
	case "set-combat-meta": return cmd.character_set_combat_meta(db, args)
	case "set-status":      return cmd.character_set_status(db, args)
	case "set-action":      return cmd.character_set_action(db, args)
	case "add-class":       return cmd.character_add_class(db, args)
	case "list-classes":    return cmd.character_list_classes(db, args)
	case "add-xp":          return cmd.character_add_xp(db, args)
	case "add-money":       return cmd.character_add_money(db, args)
	case "remove-money":    return cmd.character_remove_money(db, args)
	case "set-party":       return cmd.character_set_party(db, args)
	case "set-campaign":    return cmd.character_set_campaign(db, args)
	case "set-temp-hp":     return cmd.character_set_temp_hp(db, args)
	case "set-death-saves": return cmd.character_set_death_saves(db, args)
	case "set-exhaustion":  return cmd.character_set_exhaustion(db, args)
	case "set-hit-dice":    return cmd.character_set_hit_dice(db, args)
	case "set-inspiration": return cmd.character_set_inspiration(db, args)
	case "set-rests":       return cmd.character_set_rests(db, args)
	case "set-backstory":   return cmd.character_set_backstory(db, args)
	case "set-location":    return cmd.character_set_location(db, args)
	case "set-chapter":     return cmd.character_set_chapter(db, args)
	case "set-owner":       return cmd.character_set_owner(db, args)
	case "set-skill":       return cmd.character_set_skill(db, args)
	case "list-skills":     return cmd.character_list_skills(db, args)
	case "set-resource":    return cmd.character_set_resource(db, args)
	case "use-resource":    return cmd.character_use_resource(db, args)
	case "reset-resources": return cmd.character_reset_resources(db, args)
	case "list-resources":  return cmd.character_list_resources(db, args)
	case "set-proficiency":         return cmd.character_set_proficiency(db, args)
	case "set-spellcasting":        return cmd.character_set_spellcasting(db, args)
	case "set-initiative":          return cmd.character_set_initiative(db, args)
	case "set-passive-perception":  return cmd.character_set_passive_perception(db, args)
	case "set-languages":           return cmd.character_set_languages(db, args)
	case "set-max-hit-dice":        return cmd.character_set_max_hit_dice(db, args)
	case "set-combat":              return cmd.character_set_combat(db, args)
	case "set-concentrating":       return cmd.character_set_concentrating(db, args)
	case "add-prof":                return cmd.character_add_prof(db, args)
	case "remove-prof":             return cmd.character_remove_prof(db, args)
	case "set-spell-slot":          return cmd.character_set_spell_slot(db, args)
	case "set-darkvision":          return cmd.character_set_darkvision(db, args)
	case "set-bond":                return cmd.character_set_bond(db, args)
	case "set-flaw":                return cmd.character_set_flaw(db, args)
	case "set-ideal":               return cmd.character_set_ideal(db, args)
	case "set-personality-traits":  return cmd.character_set_personality_traits(db, args)
	case "set-appearance":          return cmd.character_set_appearance(db, args)
	case "set-gender":              return cmd.character_set_gender(db, args)
	case "set-age":                 return cmd.character_set_age(db, args)
	}
	return 1
}

route_item :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent item <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent item <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "upsert":
		return cmd.item_upsert(db, args)
	case "list":
		return cmd.item_list(db)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown item subcommand"}`)
		} else {
			fmt.eprintln("Unknown item subcommand:", sub)
		}
		return 1
	}
}

route_inventory :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent inventory <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent inventory <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "add":    return cmd.inventory_add(db, args)
	case "get":    return cmd.inventory_get(db, args)
	case "remove": return cmd.inventory_remove(db, args)
	case "equip":  return cmd.inventory_equip(db, args)
	case "attune": return cmd.inventory_attune(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown inventory subcommand"}`)
		} else {
			fmt.eprintln("Unknown inventory subcommand:", sub)
		}
		return 1
	}
}

route_spell :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent spell <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent spell <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "upsert":         return cmd.spell_upsert(db, args)
	case "list":           return cmd.spell_list(db)
	case "learn":          return cmd.spell_learn(db, args)
	case "forget":         return cmd.spell_forget(db, args)
	case "prepare":        return cmd.spell_prepare(db, args)
	case "list-character": return cmd.spell_list_character(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown spell subcommand"}`)
		} else {
			fmt.eprintln("Unknown spell subcommand:", sub)
		}
		return 1
	}
}

route_feature :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent feature <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent feature <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "upsert":         return cmd.feature_upsert(db, args)
	case "list":           return cmd.feature_list(db)
	case "add-to-char":    return cmd.feature_add_to_char(db, args)
	case "list-character": return cmd.feature_list_character(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown feature subcommand"}`)
		} else {
			fmt.eprintln("Unknown feature subcommand:", sub)
		}
		return 1
	}
}

route_companion :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent companion <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent companion <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create":    return cmd.companion_create(db, args)
	case "list":      return cmd.companion_list(db, args)
	case "get":       return cmd.companion_get(db, args)
	case "set-stats": return cmd.companion_set_stats(db, args)
	case "damage":    return cmd.companion_damage(db, args)
	case "heal":      return cmd.companion_heal(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown companion subcommand"}`)
		} else {
			fmt.eprintln("Unknown companion subcommand:", sub)
		}
		return 1
	}
}

route_creature :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent creature <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent creature <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create", "list", "get":
		return route_creature_core(db, sub, args)
	case "set-status", "set-combat-meta", "set-action", "set-location", "damage", "heal", "set-stats", "add-money", "remove-money", "add-ability", "remove-ability", "list-abilities", "set-attack", "set-cr", "set-initiative", "set-passive-perception", "set-reactions", "set-legendary", "set-combat", "set-darkvision", "set-type", "set-alignment", "set-environment", "set-speed-fly", "set-hover", "set-speed", "set-blindsight", "set-telepathy", "set-damage-immunities", "set-condition-immunities", "set-recharge", "set-bonus-actions", "set-lair-actions", "set-regional", "set-traits", "set-actions", "set-saving-throws", "set-skills-text", "set-languages-full":
		return route_creature_ops(db, sub, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown creature subcommand"}`)
		} else {
			fmt.eprintln("Unknown creature subcommand:", sub)
		}
		return 1
	}
}

route_creature_core :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "create": return cmd.creature_create(db, args)
	case "list":   return cmd.creature_list(db)
	case "get":    return cmd.creature_get(db, args)
	}
	return 1
}

route_creature_ops :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "set-status":      return cmd.creature_set_status(db, args)
	case "set-combat-meta": return cmd.creature_set_combat_meta(db, args)
	case "set-action":      return cmd.creature_set_action(db, args)
	case "set-location":    return cmd.creature_set_location(db, args)
	case "damage":          return cmd.creature_damage(db, args)
	case "heal":            return cmd.creature_heal(db, args)
	case "set-stats":       return cmd.creature_set_stats(db, args)
	case "add-money":       return cmd.creature_add_money(db, args)
	case "remove-money":    return cmd.creature_remove_money(db, args)
	case "add-ability":     return cmd.creature_add_ability(db, args)
	case "remove-ability":  return cmd.creature_remove_ability(db, args)
	case "list-abilities":  return cmd.creature_list_abilities(db, args)
	case "set-attack":              return cmd.creature_set_attack(db, args)
	case "set-cr":                  return cmd.creature_set_cr(db, args)
	case "set-initiative":          return cmd.creature_set_initiative(db, args)
	case "set-passive-perception":  return cmd.creature_set_passive_perception(db, args)
	case "set-reactions":           return cmd.creature_set_reactions(db, args)
	case "set-legendary":           return cmd.creature_set_legendary(db, args)
	case "set-type":                return cmd.creature_set_type(db, args)
	case "set-alignment":           return cmd.creature_set_alignment(db, args)
	case "set-environment":         return cmd.creature_set_environment(db, args)
	case "set-speed-fly":           return cmd.creature_set_speed_fly(db, args)
	case "set-hover":               return cmd.creature_set_hover(db, args)
	case "set-speed":               return cmd.creature_set_speed(db, args)
	case "set-blindsight":           return cmd.creature_set_blindsight(db, args)
	case "set-telepathy":           return cmd.creature_set_telepathy(db, args)
	case "set-damage-immunities":   return cmd.creature_set_damage_immunities(db, args)
	case "set-condition-immunities": return cmd.creature_set_condition_immunities(db, args)
	case "set-recharge":            return cmd.creature_set_recharge(db, args)
	case "set-bonus-actions":       return cmd.creature_set_bonus_actions(db, args)
	case "set-lair-actions":        return cmd.creature_set_lair_actions(db, args)
	case "set-regional":            return cmd.creature_set_regional(db, args)
	case "set-traits":              return cmd.creature_set_traits(db, args)
	case "set-actions":             return cmd.creature_set_actions(db, args)
	case "set-saving-throws":       return cmd.creature_set_saving_throws(db, args)
	case "set-skills-text":         return cmd.creature_set_skills_text(db, args)
	case "set-languages-full":      return cmd.creature_set_languages_full(db, args)
	case "set-combat":              return cmd.creature_set_combat(db, args)
	case "set-darkvision":          return cmd.creature_set_darkvision(db, args)
	}
	return 1
}

route_faction :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent faction <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent faction <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create": return cmd.faction_create(db, args)
	case "list":   return cmd.faction_list(db)
	case "join":   return cmd.faction_join(db, args)
	case "set-standing": return cmd.faction_set_standing(db, args)
	case "get-standing":        return cmd.faction_get_standing(db, args)
		case "set-party-standing":  return cmd.faction_set_party_standing(db, args)
		case "get-party-standing":  return cmd.faction_get_party_standing(db, args)
		case "effective-standing":  return cmd.faction_effective_standing(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown faction subcommand"}`)
		} else {
			fmt.eprintln("Unknown faction subcommand:", sub)
		}
		return 1
	}
}


route_condition :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent condition <add|remove|list> <character|npc|creature> <id> <name> [source] [duration_rounds] [save_dc] [save_ability]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent condition <add|remove|list> <character|npc|creature> <id> <name> [source] [duration_rounds] [save_dc] [save_ability]")
		}
		return 1
	}
	switch args[0] {
	case "add":    return cmd.condition_add(db, args[1:])
	case "remove": return cmd.condition_remove(db, args[1:])
	case "list":   return cmd.condition_list(db, args[1:])
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown condition subcommand"}`)
		} else {
			fmt.eprintln("Unknown condition subcommand:", args[0])
		}
		return 1
	}
}

route_combat :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent combat <subcommand> ..."}`) }
		else { fmt.eprintln("Usage: dnd-agent combat <subcommand> ...") }
		return 1
	}
	switch args[0] {
	case "start":       return cmd.combat_start(db, args)
	case "join":        return cmd.combat_join(db, args)
	case "join-all":    return cmd.combat_join_all(db, args)
	case "init":        return cmd.combat_init(db, args)
	case "next":        return cmd.combat_next(db, args)
	case "attack":      return cmd.combat_attack(db, args)
	case "damage":      return cmd.combat_damage(db, args)
	case "save":        return cmd.combat_save(db, args)
	case "move":        return cmd.combat_move(db, args)
	case "condition":   return cmd.combat_condition(db, args)
	case "death-save":  return cmd.combat_death_save(db, args)
	case "react":       return cmd.combat_react(db, args)
	case "ready":       return cmd.combat_ready(db, args)
	case "status":      return cmd.combat_status(db, args)
	case "end":         return cmd.combat_end(db, args)
	case:
		if db.is_json { fmt.println(`{"success":false,"error":"Unknown combat subcommand"}`) }
		else { fmt.eprintln("Unknown combat subcommand:", args[0]) }
		return 1
	}
}

route_rest :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent rest <short|long> <character_id> [hit_dice_count]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent rest <short|long> <character_id> [hit_dice_count]")
		}
		return 1
	}
	switch args[0] {
	case "short": return cmd.rest_short(db, args)
	case "long":  return cmd.rest_long(db, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown rest subcommand. Use 'short' or 'long'."}`)
		} else {
			fmt.eprintln("Unknown rest subcommand. Use 'short' or 'long'.")
		}
		return 1
	}
}

route_npc :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent npc <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent npc <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create", "list", "get", "delete", "damage", "heal":
		return route_npc_core(db, sub, args)
	case "set-details", "set-stats", "set-combat-meta", "set-status", "add-money", "remove-money", "set-action", "set-relationship", "list-relationships", "set-location", "add-ability", "remove-ability", "list-abilities", "set-cr", "set-attack", "set-initiative", "set-combat", "set-languages", "set-passive-perception", "set-concentrating", "set-skill", "remove-skill", "set-darkvision", "set-bond", "set-flaw", "set-ideal", "set-personality-traits", "set-appearance", "add-tool-prof", "remove-tool-prof":
		return route_npc_setters(db, sub, args)
	case "help":
		if db.is_json {
			fmt.println(`{"success":true,"subcommands":["create","list","get","delete","damage","heal","set-details","set-stats","set-combat-meta","set-status","add-money","remove-money","set-action","set-relationship","list-relationships","set-location","add-ability","remove-ability","list-abilities","set-cr","set-attack","set-initiative","set-combat","set-languages","set-passive-perception","set-concentrating","set-skill","remove-skill","set-darkvision","set-bond","set-flaw","set-ideal","set-personality-traits","set-appearance","add-tool-prof","remove-tool-prof"]}`)
		} else {
			fmt.println("npc subcommands: create, list, get, delete, damage, heal, set-details, set-stats, set-combat-meta, set-status, add-money, remove-money, set-action, set-relationship, list-relationships, set-location, add-ability, remove-ability, list-abilities, set-cr, set-attack, set-initiative, set-combat, set-languages, set-passive-perception, set-concentrating, set-skill, remove-skill, set-darkvision, set-bond, set-flaw, set-ideal, set-personality-traits, set-appearance, add-tool-prof, remove-tool-prof")
		}
		return 0
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown npc subcommand"}`)
		} else {
			fmt.eprintln("Unknown npc subcommand:", sub)
		}
		return 1
	}
}

route_npc_core :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "create": return cmd.npc_create(db, args)
	case "list":   return cmd.npc_list(db)
	case "get":    return cmd.npc_get(db, args)
	case "delete": return cmd.npc_delete(db, args)
	case "damage": return cmd.npc_damage(db, args)
	case "heal":   return cmd.npc_heal(db, args)
	}
	return 1
}

route_npc_setters :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "set-details":      return cmd.npc_set_details(db, args)
	case "set-stats":        return cmd.npc_set_stats(db, args)
	case "set-combat-meta":  return cmd.npc_set_combat_meta(db, args)
	case "set-status":       return cmd.npc_set_status(db, args)
	case "add-money":        return cmd.npc_add_money(db, args)
	case "remove-money":     return cmd.npc_remove_money(db, args)
	case "set-action":       return cmd.npc_set_action(db, args)
	case "set-relationship":  return cmd.npc_set_relationship(db, args)
	case "list-relationships": return cmd.npc_list_relationships(db, args)
	case "set-location":     return cmd.npc_set_location(db, args)
	case "add-ability":      return cmd.npc_add_ability(db, args)
	case "remove-ability":   return cmd.npc_remove_ability(db, args)
	case "list-abilities":   return cmd.npc_list_abilities(db, args)
	case "set-cr":                   return cmd.npc_set_cr(db, args)
	case "set-attack":               return cmd.npc_set_attack(db, args)
	case "set-initiative":           return cmd.npc_set_initiative(db, args)
	case "set-combat":               return cmd.npc_set_combat(db, args)
	case "set-languages":            return cmd.npc_set_languages(db, args)
	case "set-passive-perception":   return cmd.npc_set_passive_perception(db, args)
	case "set-concentrating":        return cmd.npc_set_concentrating(db, args)
	case "set-skill":                return cmd.npc_set_skill(db, args)
	case "remove-skill":             return cmd.npc_remove_skill(db, args)
	case "set-darkvision":           return cmd.npc_set_darkvision(db, args)
	case "set-bond":                 return cmd.npc_set_bond(db, args)
	case "set-flaw":                 return cmd.npc_set_flaw(db, args)
	case "set-ideal":                return cmd.npc_set_ideal(db, args)
	case "set-personality-traits":   return cmd.npc_set_personality_traits(db, args)
	case "set-appearance":           return cmd.npc_set_appearance(db, args)
	case "add-tool-prof":            return cmd.npc_add_tool_prof(db, args)
	case "remove-tool-prof":         return cmd.npc_remove_tool_prof(db, args)
	}
	return 1
}

route_campaign :: proc(db: ^lib.Db, args: []string) -> int {
	if len(args) < 1 {
		if db.is_json {
			fmt.println(`{"success":false,"error":"Usage: dnd-agent campaign <subcommand> [args]"}`)
		} else {
			fmt.eprintln("Usage: dnd-agent campaign <subcommand> [args]")
		}
		return 1
	}
	sub := args[0]
	switch sub {
	case "create", "list", "get", "delete", "set-chapter", "next-session":
		return route_campaign_core(db, sub, args)
	case "add-location", "set-location", "list-locations", "add-action", "link-actor", "list-actions", "get-story-state", "add-journal-entry", "list-journal", "set-dm-notes", "set-time":
		return route_campaign_story(db, sub, args)
	case:
		if db.is_json {
			fmt.println(`{"success":false,"error":"Unknown campaign subcommand"}`)
		} else {
			fmt.eprintln("Unknown campaign subcommand:", sub)
		}
		return 1
	}
}

route_campaign_core :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "create":       return cmd.campaign_create(db, args)
	case "list":         return cmd.campaign_list(db)
	case "get":          return cmd.campaign_get(db, args)
	case "delete":       return cmd.campaign_delete(db, args)
	case "set-chapter":  return cmd.campaign_set_chapter(db, args)
	case "next-session": return cmd.campaign_next_session(db, args)
	}
	return 1
}

route_campaign_story :: proc(db: ^lib.Db, sub: string, args: []string) -> int {
	switch sub {
	case "add-location":       return cmd.campaign_add_location(db, args)
	case "set-location":       return cmd.campaign_set_location(db, args)
	case "list-locations":     return cmd.campaign_list_locations(db, args)
	case "add-action":         return cmd.campaign_add_action(db, args)
	case "link-actor":         return cmd.campaign_link_actor(db, args)
	case "list-actions":       return cmd.campaign_list_actions(db, args)
	case "get-story-state":    return cmd.campaign_get_story_state(db, args)
	case "add-journal-entry":  return cmd.campaign_add_journal_entry(db, args)
	case "list-journal":       return cmd.campaign_list_journal(db, args)
	case "set-dm-notes":       return cmd.campaign_set_dm_notes(db, args)
	case "set-time":           return cmd.campaign_set_time(db, args)
	}
	return 1
}

print_usage_json :: proc() {
	fmt.println("[")
	for cmd, idx in HELP_COMMANDS {
		if idx > 0 do fmt.println(",")
		fmt.printf("  {{\"command\":\"%s\",\"description\":\"%s\"", cmd.command, cmd.description)
		if cmd.subcommands != nil {
			fmt.println(",")
			fmt.println("   \"subcommands\":[")
			for sub, sub_idx in cmd.subcommands {
				if sub_idx > 0 do fmt.println(",")
				fmt.printf("     {{\"name\":\"%s\",\"args\":\"%s\",\"description\":\"%s\"}}", sub.name, sub.args, sub.description)
			}
			fmt.println()
			fmt.printf("   ]")
		}
		fmt.printf("}}")
	}
	fmt.println()
	fmt.println("]")
}

print_usage_text :: proc() {
	fmt.println("dnd-agent - D&D campaign management CLI")
	fmt.println()
	fmt.println("Usage: dnd-agent <command> [args] [--json]")
	fmt.println()
	fmt.println("Commands:")
	for cmd in HELP_COMMANDS {
		fmt.printf("  %-16s %s\n", cmd.command, cmd.description)
		if cmd.subcommands != nil {
			for sub in cmd.subcommands {
				fmt.printf("    %-14s %-40s %s\n", sub.name, sub.args, sub.description)
			}
			fmt.println()
		}
	}
}

print_usage :: proc(is_json: bool = false) {
	if is_json {
		print_usage_json()
	} else {
		print_usage_text()
	}
}
route_world :: proc(db: ^lib.Db, cmd_name: string, args: []string) -> int {
	switch cmd_name {
	case "location":
		switch args[0] {
		case "set-parent":       return cmd.location_set_parent(db, args)
		case "set-restricted":   return cmd.location_set_restricted(db, args)
		case "breadcrumb":
			id := strconv.atoi(args[1])
			fmt.println(cmd.location_breadcrumb(db, id))
			return 0
		case:
			if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent location <set-parent|set-restricted|breadcrumb> ..."}`) }
			else { fmt.eprintln("Usage: dnd-agent location <set-parent|set-restricted|breadcrumb> ...") }
			return 1
		}
	case "house":
		switch args[0] {
		case "add":              return cmd.house_add(db, args)
		case "list":             return cmd.house_list(db, args)
		case "set-inventory":    return cmd.house_set_inventory(db, args)
		case "set-restricted":   return cmd.house_set_restricted(db, args)
		case "add-resident":     return cmd.house_add_resident(db, args)
		case "remove-resident":  return cmd.house_remove_resident(db, args)
		case "list-residents":   return cmd.house_list_residents(db, args)
		case:
			if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent house <add|list|set-inventory|set-restricted> ..."}`) }
			else { fmt.eprintln("Usage: dnd-agent house <add|list|set-inventory|set-restricted> ...") }
			return 1
		}
	case "shop":
		switch args[0] {
		case "add":              return cmd.shop_add(db, args)
		case "list":             return cmd.shop_list(db, args)
		case "set-inventory":    return cmd.shop_set_inventory(db, args)
		case:
			if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent shop <add|list|set-inventory> ..."}`) }
			else { fmt.eprintln("Usage: dnd-agent shop <add|list|set-inventory> ...") }
			return 1
		}
	case "encounter":
		switch args[0] {
		case "add":              return cmd.encounter_add(db, args)
		case "list":             return cmd.encounter_list(db, args)
		case:
			if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent encounter <add|list> ..."}`) }
			else { fmt.eprintln("Usage: dnd-agent encounter <add|list> ...") }
			return 1
		}
	case "setpiece":
		switch args[0] {
		case "add":              return cmd.setpiece_add(db, args)
		case "list":             return cmd.setpiece_list(db, args)
		case:
			if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent setpiece <add|list> ..."}`) }
			else { fmt.eprintln("Usage: dnd-agent setpiece <add|list> ...") }
			return 1
		}
	}
	return 1
}

route_can_enter :: proc(db: ^lib.Db, args: []string) -> int {
	// Usage: dnd-agent can-enter <property_kind> <property_id> [visitor_npc_id] [visitor_char_id] [in_game_day]
	if len(args) < 3 {
		if db.is_json { fmt.println(`{"success":false,"error":"Usage: dnd-agent can-enter <house|shop|location> <id> [visitor_npc_id] [visitor_char_id] [in_game_day]"}`) }
		else { fmt.eprintln("Usage: dnd-agent can-enter <house|shop|location> <id> [visitor_npc_id] [visitor_char_id] [in_game_day]") }
		return 1
	}
	property_kind := args[0]
	property_id := strconv.atoi(args[1])
	visitor_npc_id := len(args) > 2 ? strconv.atoi(args[2]) : 0
	visitor_char_id := len(args) > 3 ? strconv.atoi(args[3]) : 0
	in_game_day := len(args) > 4 ? strconv.atoi(args[4]) : 0

	result := cmd.can_enter(db, visitor_npc_id, visitor_char_id, property_kind, property_id, in_game_day)
	if db.is_json { fmt.printf(`{"success":true,"result":"%s"}` + "\n", result) }
	else { fmt.printf("Access: %s\n", result) }
	return 0
}
