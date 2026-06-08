# dnd-agent

> The terminal-native D&D world engine. Build your campaign as a living database — towns, shops, NPCs, quests, session journals, faction politics — then query it from the command line or feed it to an AI Dungeon Master.

[![Odin](https://img.shields.io/badge/Odin-dev--2026--05-blue?logo=odin&logoColor=white)](https://odin-lang.org)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue?logo=linux&logoColor=white)](https://github.com/xDarkicex/dnd-agent/actions)
[![Build](https://github.com/xDarkicex/dnd-agent/actions/workflows/release.yml/badge.svg)](https://github.com/xDarkicex/dnd-agent/actions/workflows/release.yml)

## The World Engine

dnd-agent models your tabletop world as a **relational database** — every tavern, blacksmith, quest giver, and goblin camp is a row you can query, update, and connect. It was built for DMs who run long-form campaigns with deep continuity, and for AI agents that need a canonical source of truth about the game state.

**The world model.** You create a campaign. Inside it, you build locations — towns, districts, dungeons. Locations nest into sub-locations (`Ashwick > Blacksmith District > The Anvil & Flame`). Each location holds houses (with residents and inventory), shops (with opening hours and proprietors), wandering encounters, and story-driving setpieces. NPCs, characters, and creatures all have a location — the CLI tells you exactly who is where right now.

**The memory system.** A stateless AI agent only knows what you tell it. dnd-agent solves this with three systems working together: a **campaign journal** (timestamped session recaps the AI writes and reads back), a **quest tracker** (step-by-step objectives with linked actors, so the AI remembers what the party is supposed to be doing), and an **in-game calendar** (day, time of day, season) so the AI can say "it's autumn evening on day 42." One command — `campaign get-story-state` — returns the complete context packet the AI needs to reconstruct the game from a cold start.

**The combat engine.** Turn-based D&D 5e combat lives inside the database. `combat start`, `combat join`, `combat init` set up the encounter. `combat attack` resolves attack rolls against AC, `combat damage` applies damage with automatic resistance/vulnerability/immunity. `combat save` handles saving throws with proficiency bonuses. `combat next` advances turns, resets reactions each round. Death saves, concentration, conditions, reactions, and ready actions are all tracked. The combat snapshot appears in `get-story-state` — the AI always knows who's up, what HP everyone has, and what conditions are active.

**The relationship graph.** NPCs have friendships, rivalries, and family ties with each other (tracked with a decay-aware score). Characters have personal faction standings, and campaigns track party-wide institutional faction reputation — a faction can hate one PC but still mark the party as hostile for the group's actions. Houses have residents. Quests have quest givers and participants. Every entity can be linked to every other entity — the database IS the campaign bible.

**Built for AI pipelines.** Every command emits `--json` output for piping into LLM agents, Discord bots, or automation scripts. The schema is designed so an AI can call `get-story-state`, receive the full world snapshot (locations tree with all entities present, active quests, recent journal entries, faction standings, story log), and immediately begin DMing with full context. No warm-up, no context-stuffing — one query, everything it needs.

**Fast by design.** O(1) database lookups. Arena-based memory with zero heap allocations after startup. Automatic SQLite schema migrations — drop the binary into a campaign folder and run. No config files, no daemons, no network calls. Just a 2.6 MB binary and a `.db` file you can commit to git alongside your session notes.

## Install

### macOS — Homebrew (recommended)

```sh
brew tap xDarkicex/dnd-agent
brew install dnd-agent
```

### Linux — Tarball

```sh
curl -sL https://github.com/xDarkicex/dnd-agent/releases/latest/download/dnd-agent-unknown-linux.tar.gz | tar -xz
chmod +x dnd-agent
./dnd-agent init
```

### macOS — Tarball

```sh
curl -sL https://github.com/xDarkicex/dnd-agent/releases/latest/download/dnd-agent-apple-darwin.tar.gz | tar -xz
chmod +x dnd-agent
./dnd-agent init
```

### Build from source

```sh
odin build . -file -collection:ext=./vendor -out:dnd-agent
```

---

## Table of Contents
1. [The World Engine](#the-world-engine)
2. [Installation & Build](#installation--build)
3. [Database Schema](#database-schema)
4. [Global Output Flags](#global-output-flags)
5. [CLI Command Reference](#cli-command-reference)
   - [Characters & Multiclassing](#1-characters--multiclassing)
   - [Vitals & Resting Setters](#2-vitals--resting-setters)
   - [Combat Stats & Spellcasting](#3-combat-stats--spellcasting)
   - [Conditions & Personality](#4-conditions--personality)
   - [Skills & Proficiencies](#5-skills--proficiencies)
   - [Class Resources & Spell Slots](#6-class-resources--spell-slots)
   - [Companions & Pets](#7-companions--pets)
   - [NPCs & Relationships](#8-npcs--relationships)
   - [Creatures & Monsters](#9-creatures--monsters)
   - [Campaigns, Story Tracking & Session Continuity](#10-campaigns-story-tracking--session-continuity)
   - [Quest Tracking](#11-quest-tracking)
   - [World & Locations](#12-world--locations)
   - [Factions & Standings](#13-factions--standings)
   - [Spells & Features](#14-spells--features)
   - [Items & Inventory Management](#15-items--inventory-management)
6. [Automatic Database Schema Migrations](#automatic-database-schema-migrations)
7. [Example Walkthrough Scenario](#example-walkthrough-scenario)

---

## Installation & Build

### Prerequisites
- [Odin compiler](https://odin-lang.org/) (installed and in your `PATH`)
- `sqlite3` development headers (normally pre-installed on macOS/macOS Command Line Tools)

### Build Commands
Run these commands from the project root:
* **Build Binary**: `make build` (Produces the `dnd-agent` binary)
* **Run Tests**: `make test` (Runs package-wide unit tests)
* **Initialize Database**: `./dnd-agent init` (Creates the schema inside `dnd-agent.db`)
* **Clean Artifacts**: `make clean` (Deletes the compiled binary and database file)

---

## Database Schema
The database uses a highly relational SQLite schema. For a detailed mapping of all tables, fields, constraints, and relationships, see the **[docs/schema.md](docs/schema.md)** document.

---

## Global Output Flags
The CLI supports two output modes:
- **Standard Text**: Human-readable tables and command summaries designed for DMs.
- **Structured JSON**: By appending `--json` or `-j` to any command, the CLI prints structured JSON to `stdout` for programmatic parsing or integration with AI agents.

*Example*:
```bash
./dnd-agent character list --json
```

---

## CLI Command Reference

### 1. Characters & Multiclassing
Create, delete, list, and view detailed player character sheets.

- **Create Character**:
  ```bash
  ./dnd-agent character create <name> <class> <level> <max_hp>
  ```
- **List Characters**:
  ```bash
  ./dnd-agent character list [--json]
  ```
- **Get Detailed Character Sheet**:
  ```bash
  ./dnd-agent character get <id> [--json]
  ```
  *Displays multiclass summaries, base ability scores, saves, vitals, money, skills, and resources.*
- **Delete Character**:
  ```bash
  ./dnd-agent character delete <id>
  ```
- **Add or Level Up Class (Multiclassing)**:
  ```bash
  ./dnd-agent character add-class <char_id> <class_name> <level>
  ```
- **List Character Classes**:
  ```bash
  ./dnd-agent character list-classes <char_id>
  ```
- **Award XP**:
  ```bash
  ./dnd-agent character add-xp <id> <amount>
  ```
- **Manage Money (Supports Gold, Silver, Copper, Platinum, Electrum)**:
  ```bash
  ./dnd-agent character add-money <id> <gp> <sp> <cp> [pp] [ep]
  ./dnd-agent character remove-money <id> <gp> <sp> <cp> [pp] [ep]
  ```

---

### 2. Vitals & Resting Setters
Manage combat conditions, resting metrics, and temporary states.

- **Apply Combat Damage (Depletes Temporary HP first)**:
  ```bash
  ./dnd-agent character damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ```
  *Handles evasion feats, races, resistances, vulnerabilities, immunities, and saving throw modifier calculations automatically.*
- **Apply Healing**:
  ```bash
  ./dnd-agent character heal <id> <amount>
  ```
- **Set Temporary Hit Points**:
  ```bash
  ./dnd-agent character set-temp-hp <id> <amount>
  ```
- **Set Death Saving Throws**:
  ```bash
  ./dnd-agent character set-death-saves <id> <successes_count> <failures_count>
  ```
- **Set Exhaustion Levels (0 to 6)**:
  ```bash
  ./dnd-agent character set-exhaustion <id> <level>
  ```
- **Set Spent Hit Dice**:
  ```bash
  ./dnd-agent character set-hit-dice <id> <expended_count>
  ```
- **Set Inspiration**:
  ```bash
  ./dnd-agent character set-inspiration <id> <0/1>
  ```
- **Set Backstory**:
  ```bash
  ./dnd-agent character set-backstory <id> <backstory>
  ```
- **Set Location**:
  ```bash
  ./dnd-agent character set-location <id> <location_id>
  ```
- **Set Chapter**:
  ```bash
  ./dnd-agent character set-chapter <id> <chapter_id>
  ```
- **Set Owner**:
  ```bash
  ./dnd-agent character set-owner <id> <owner_name>
  ```
- **Configure Ability Scores & Base Details**:
  ```bash
  ./dnd-agent character set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ./dnd-agent character set-save-prof <id> <str_0/1> <dex_0/1> <con_0/1> <int_0/1> <wis_0/1> <cha_0/1>
  ./dnd-agent character set-details <id> <ac> <race> <speed> [alignment] [size]
  ```

---

### 3. Combat Stats & Spellcasting
Set D&D 5e combat math: proficiency bonus, initiative, spell save DC, spell attack bonus, passive perception, languages, max hit dice, concentration, and the combat-engaged flag (consumed by an external combat engine).

- **Set Proficiency Bonus**:
  ```bash
  ./dnd-agent character set-proficiency <id> <bonus>
  ```
- **Set Spellcasting (DC + Spell Attack)**:
  ```bash
  ./dnd-agent character set-spellcasting <id> <dc> <attack_bonus>
  ```
- **Set Initiative Modifier**:
  ```bash
  ./dnd-agent character set-initiative <id> <modifier>
  ```
- **Set Passive Perception**:
  ```bash
  ./dnd-agent character set-passive-perception <id> <value>
  ```
- **Set Languages (Comma-Separated)**:
  ```bash
  ./dnd-agent character set-languages <id> <csv>
  ```
- **Set Max Hit Dice**:
  ```bash
  ./dnd-agent character set-max-hit-dice <id> <amount>
  ```
- **Set Concentration Spell (Blank to Clear)**:
  ```bash
  ./dnd-agent character set-concentrating <id> <spell_name_or_blank>
  ```
- **Toggle Combat State (0 = out, 1 = in combat)**:
  ```bash
  ./dnd-agent character set-combat <id> <0|1>
  ```
- **Add Weapon / Armor / Tool Proficiency**:
  ```bash
  ./dnd-agent character add-prof <id> <weapon|armor|tool> <name>
  ./dnd-agent character remove-prof <id> <weapon|armor|tool> <name>
  ```
- **Set Darkvision (Range in Feet, 0 = None)**:
  ```bash
  ./dnd-agent character set-darkvision <id> <range>
  ```

---

### 4. Conditions & Personality
Track D&D 5e conditions with source/duration/save metadata, and PHB personality hooks. Conditions are a top-level command (apply to character, NPC, or creature polymorphically).

- **Apply a Condition**:
  ```bash
  ./dnd-agent condition add <character|npc|creature> <id> <name> [source] [duration_rounds] [save_dc] [save_ability]
  ```
  *Example: `dnd-agent condition add character 1 restrained Web 10 13 STR` — restrained by Web, ends on STR save DC 13 or after 10 rounds.*
- **List Active Conditions on an Entity**:
  ```bash
  ./dnd-agent condition list <character|npc|creature> <id>
  ```
- **Remove a Condition**:
  ```bash
  ./dnd-agent condition remove <character|npc|creature> <id> <name>
  ```
- **Set Personality Hooks (PHB)**:
  ```bash
  ./dnd-agent character set-bond <id> <text>
  ./dnd-agent character set-flaw <id> <text>
  ./dnd-agent character set-ideal <id> <text>
  ./dnd-agent character set-personality-traits <id> <text>
  ./dnd-agent character set-appearance <id> <text>
  ```

---

### 5. Skills & Proficiencies
Manage skill proficiencies. Modifiers are calculated dynamically based on 5e rules.

- **Set Skill Proficiency Level**:
  ```bash
  ./dnd-agent character set-skill <char_id> <skill_name> <level>
  ```
  *Levels: `0` = none, `1` = proficient, `2` = expertise.*
- **List Character Skill Proficiencies**:
  ```bash
  ./dnd-agent character list-skills <char_id>
  ```

---

### 6. Class Resources & Spell Slots
Track custom class resource pools (Rage, Ki, Sorcery Points) and spell slots.

- **Configure Resource Pool**:
  ```bash
  ./dnd-agent character set-resource <char_id> <resource_name> <max> <current> [reset_condition]
  ```
  *Reset conditions: `short_rest` or `long_rest` (default `long_rest`).*
- **Spend Resource**:
  ```bash
  ./dnd-agent character use-resource <char_id> <resource_name> [amount]
  ```
- **List Active Resources**:
  ```bash
  ./dnd-agent character list-resources <char_id>
  ```
- **Short Rest (Spend hit dice to heal)**:
  ```bash
  ./dnd-agent rest short <character_id> <hit_dice_count>
  ```
  *Heals hit_dice_count × (avg_hit_die + CON_mod). Resets short-rest resources, decrements available short rests, clears rest-duration conditions. Hit die size determined by character class (d6→4, d8→5, d10→6, d12→7 average).*
- **Long Rest (Full recovery)**:
  ```bash
  ./dnd-agent rest long <character_id>
  ```
  *Full HP heal, clears temp HP, recovers half expended hit dice, reduces exhaustion by 1, resets all spell slots and resources, resets available rests to 2/1, clears short/long/until_rest conditions.*

- **Manual Resource Reset (for fine-grained control)**:
  ```bash
  ./dnd-agent character reset-resources <char_id> [reset_condition]
  ```
  *A `long_rest` automatically triggers reset for both `long_rest` and `short_rest` resource types.*
- **Set Spell Slot by Level (Track Max and Used)**:
  ```bash
  ./dnd-agent character set-spell-slot <id> <slot_level> <max> <used>
  ```

---

### 7. Companions & Pets
Track character companions, mounts, pets, and familiars.

- **Create Companion**:
  ```bash
  ./dnd-agent companion create <char_id> <name> <type> <level> <max_hp> <ac> <attack_bonus> <damage_dice>
  ```
- **Set Companion Stats**:
  ```bash
  ./dnd-agent companion set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **List Companions**:
  ```bash
  ./dnd-agent companion list [char_id]
  ```
- **View Companion Details**:
  ```bash
  ./dnd-agent companion get <id>
  ```
- **Damage/Heal Companion**:
  ```bash
  ./dnd-agent companion damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./dnd-agent companion heal <id> <amount>
  ```

---

### 8. NPCs & Relationships
Manage campaign NPCs, daily roles, location, and interpersonal relationships.

- **Create NPC**:
  ```bash
  ./dnd-agent npc create <name> <description> <max_hp> <campaign_id>
  ```
- **Set NPC details**:
  ```bash
  ./dnd-agent npc set-details <id> <ac> <story_role> <daily_role> <backstory>
  ```
- **Configure NPC Ability Scores**:
  ```bash
  ./dnd-agent npc set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **Manage NPC Abilities/Traits**:
  ```bash
  ./dnd-agent npc add-ability <npc_id> <feature_id>
  ./dnd-agent npc remove-ability <npc_id> <feature_id>
  ./dnd-agent npc list-abilities <npc_id>
  ```
- **Manage Relationship (Friendship + Type)**:
  ```bash
  ./dnd-agent npc set-relationship <npc_id_1> <npc_id_2> <friendship_level> [type] [notes]
  ```
  *Type: spouse, family, friend, rival, enemy, acquaintance, ally. Friendship level: -10 to +10.*
  *Friendship level scale: `-10` (Archnemesis) to `+10` (Close Ally).*
- **List NPC Relationships**:
  ```bash
  ./dnd-agent npc list-relationships <npc_id>
  ```
- **Assign NPC Active Location**:
  ```bash
  ./dnd-agent npc set-location <npc_id> <location_id>
  ```
- **Set Challenge Rating**:
  ```bash
  ./dnd-agent npc set-cr <id> <cr>
  ```
- **Set NPC Attack (Bonus, Damage Dice, Damage Type)**:
  ```bash
  ./dnd-agent npc set-attack <id> <bonus> <damage_dice> <damage_type>
  ```
- **Set NPC Initiative**:
  ```bash
  ./dnd-agent npc set-initiative <id> <modifier>
  ```
- **Set NPC Passive Perception**:
  ```bash
  ./dnd-agent npc set-passive-perception <id> <value>
  ```
- **Set NPC Languages (Comma-Separated)**:
  ```bash
  ./dnd-agent npc set-languages <id> <csv>
  ```
- **Set NPC Concentration (Blank to Clear)**:
  ```bash
  ./dnd-agent npc set-concentrating <id> <spell_name_or_blank>
  ```
- **Toggle NPC Combat State (0/1)**:
  ```bash
  ./dnd-agent npc set-combat <id> <0|1>
  ```
- **Set NPC Skill (Proficiency Level)**:
  ```bash
  ./dnd-agent npc set-skill <npc_id> <skill_name> <proficiency_level>
  ./dnd-agent npc remove-skill <npc_id> <skill_name>
  ```
  *proficiency_level: 0=none, 1=proficient, 2=expertise. Total modifier is computed from ability scores + prof_bonus * level.*
- **Set NPC Darkvision (Range in Feet)**:
  ```bash
  ./dnd-agent npc set-darkvision <id> <range>
  ```
- **Set NPC Personality Hooks (Bond/Flaw/Ideal/Traits/Appearance)**:
  ```bash
  ./dnd-agent npc set-bond <id> <text>
  ./dnd-agent npc set-flaw <id> <text>
  ./dnd-agent npc set-ideal <id> <text>
  ./dnd-agent npc set-personality-traits <id> <text>
  ./dnd-agent npc set-appearance <id> <text>
  ```
- **Manage NPC Tool Proficiencies** (e.g. `smith's tools`, `herbalism kit`):
  ```bash
  ./dnd-agent npc add-tool-prof <npc_id> <tool_name>
  ./dnd-agent npc remove-tool-prof <npc_id> <tool_name>
  ```

---

### 9. Creatures & Monsters
Manage active monsters, beasts, and campaign enemies. Supports ability scores, loot currencies, loot inventory tables, and custom traits.

- **Create Creature Preset**:
  ```bash
  ./dnd-agent creature create <name> <max_hp> <ac> <attacks> <story_role> <campaign_id>
  ```
- **List Active Creatures**:
  ```bash
  ./dnd-agent creature list
  ```
- **Get Creature Details**:
  ```bash
  ./dnd-agent creature get <id> [--json]
  ```
  *Displays HP, AC, linked campaign/location, full ability scores, loot currency, abilities, and inventory items.*
- **Apply Combat Damage/Healing**:
  ```bash
  ./dnd-agent creature damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./dnd-agent creature heal <id> <amount>
  ```
- **Configure Creature Ability Scores**:
  ```bash
  ./dnd-agent creature set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **Manage Loot Currency**:
  ```bash
  ./dnd-agent creature add-money <id> <gp> <sp> <cp> [pp] [ep]
  ./dnd-agent creature remove-money <id> <gp> <sp> <cp> [pp] [ep]
  ```
- **Manage Creature Abilities/Traits**:
  ```bash
  ./dnd-agent creature add-ability <creature_id> <feature_id>
  ./dnd-agent creature remove-ability <creature_id> <feature_id>
  ./dnd-agent creature list-abilities <creature_id>
  ```
- **Update Active Status/Combat Conditions**:
  ```bash
  ./dnd-agent creature set-status <id> <status_effects>
  ./dnd-agent creature set-combat-meta <id> <resistances> <vulnerabilities> <immunities>
  ./dnd-agent creature set-action <id> <action>
  ```
- **Set Creature Attack (Bonus, Damage Dice, Damage Type)**:
  ```bash
  ./dnd-agent creature set-attack <id> <bonus> <damage_dice> <damage_type>
  ```
- **Set Creature Challenge Rating**:
  ```bash
  ./dnd-agent creature set-cr <id> <cr>
  ```
- **Set Creature Initiative**:
  ```bash
  ./dnd-agent creature set-initiative <id> <modifier>
  ```
- **Set Creature Passive Perception**:
  ```bash
  ./dnd-agent creature set-passive-perception <id> <value>
  ```
- **Set Creature Reactions (Free-Form Text)**:
  ```bash
  ./dnd-agent creature set-reactions <id> <text>
  ```
- **Set Creature Legendary Actions (Free-Form Text)**:
  ```bash
  ./dnd-agent creature set-legendary <id> <text>
  ```
- **Toggle Creature Combat State (0/1)**:
  ```bash
  ./dnd-agent creature set-combat <id> <0|1>
  ```
- **Set Creature Darkvision (Range in Feet)**:
  ```bash
  ./dnd-agent creature set-darkvision <id> <range>
  ```
- **Link Creature to Campaign Location**:
  ```bash
  ./dnd-agent creature set-location <creature_id> <location_id>
  ```

---

### 10. Campaigns, Story Tracking & Session Continuity
Manage the campaign world, track sessions, log story events, write session recaps, and generate the AI context packet.

- **Create Campaign**:
  ```bash
  ./dnd-agent campaign create <name>
  ```
- **Set Campaign Chapter**:
  ```bash
  ./dnd-agent campaign set-chapter <id> <chapter>
  ```
- **Advance Session Number**:
  ```bash
  ./dnd-agent campaign next-session <campaign_id>
  ```
- **Set In-Game Calendar**:
  ```bash
  ./dnd-agent campaign set-time <campaign_id> <in_game_day> <time_of_day> <season>
  ```
  *Example: `dnd-agent campaign set-time 1 42 evening autumn` — it is day 42, evening, in autumn.*
- **Set Private DM Notes**:
  ```bash
  ./dnd-agent campaign set-dm-notes <campaign_id> <text>
  ```
  *Hidden notes visible in the story state report; never shown to players.*
- **Add Location to Campaign**:
  ```bash
  ./dnd-agent campaign add-location <campaign_id> <name> <description> [chapter]
  ```
- **Set Campaign's Active Location**:
  ```bash
  ./dnd-agent campaign set-location <campaign_id> <location_id>
  ```
- **Log Plot/Story Action**:
  ```bash
  ./dnd-agent campaign add-action <campaign_id> <description> [location_id] [faction_id] [standing_impact] [story_progression] [status]
  ```
- **Link Actor (Player/NPC) to Story Action**:
  ```bash
  ./dnd-agent campaign link-actor <action_id> <char|npc> <actor_id>
  ```
- **Add Journal Entry (Session Recap)**:
  ```bash
  ./dnd-agent campaign add-journal-entry <campaign_id> <entry_type> <description> [location_id] [session_num]
  ```
  *Entry types: `narrative`, `combat`, `decision`, `npc_interaction`, `quest_update`, `dm_note`. The AI writes these to remember what happened; get-story-state loads the last 10 for session continuity.*
- **List Journal Entries**:
  ```bash
  ./dnd-agent campaign list-journal <campaign_id> [limit]
  ```
- **Get Complete Story State (AI Context Packet)**:
  ```bash
  ./dnd-agent campaign get-story-state <campaign_id> [--json]
  ```
  *Returns the full context packet: campaign metadata with in-game time, DM notes, last 10 journal entries, active quests with objectives and actors, location tree with all entities present (sub-locations, houses, shops, encounters, setpieces, NPCs, characters, creatures), factions, NPC relationships, character faction standings, party faction standings, active combat encounter with turn order/HP/conditions, and chronological story log. This is the single command an AI agent calls to reconstruct the entire game state.*

---

### 11. Quest Tracking
Track campaign quests with step-by-step objectives and linked actors. Quests appear in the `get-story-state` context packet so the AI knows what the party is supposed to be doing.

- **Create Quest**:
  ```bash
  ./dnd-agent quest add <campaign_id> <name> [description] [quest_giver_npc_id] [reward] [chapter]
  ```
- **Add Objective (Step)**:
  ```bash
  ./dnd-agent quest add-objective <quest_id> <description> [sort_order]
  ```
- **Complete an Objective**:
  ```bash
  ./dnd-agent quest complete-objective <objective_id>
  ```
- **Update Quest Status**:
  ```bash
  ./dnd-agent quest set-status <quest_id> <active|completed|failed|abandoned>
  ```
- **Link Actor to Quest**:
  ```bash
  ./dnd-agent quest add-actor <quest_id> <char|npc> <actor_id> [role]
  ```
  *Roles: `leader`, `participant`, `target`, `observer`.*
- **List Quests for a Campaign**:
  ```bash
  ./dnd-agent quest list <campaign_id> [status]
  ```
- **Get Full Quest Details**:
  ```bash
  ./dnd-agent quest get <quest_id> [--json]
  ```
  *Returns quest metadata, all objectives with completion status, and all linked actors with names.*

---

### 12. World & Locations
Manage the campaign world: locations, sub-locations via `parent_id`, houses, shops, encounters, and setpieces. All commands are O(1) per query.

- **Set a Sub-location Parent (Recursive)**:
  ```bash
  ./dnd-agent location set-parent <id> <parent_id|0>
  ./dnd-agent location breadcrumb <id>
  ```
  *Breadcrumb walks the parent chain and prints `Ashwick > Blacksmith District > The Anvil & Flame`.*
- **Set Location Access Restriction**:
  ```bash
  ./dnd-agent location set-restricted <id> <0|1> <until>
  ```
- **Houses (Residential Properties)**:
  ```bash
  ./dnd-agent house add <location_id> <name> [description] [npc_id] [scale]
  ./dnd-agent house list <location_id>
  ./dnd-agent house set-inventory <id> <text>
  ./dnd-agent house set-restricted <id> <0|1> <until>
  ```
  *Inventory text is passed to the AI for on-the-fly item generation.*
- **House Residents (Multi-Resident, v17)**:
  ```bash
  ./dnd-agent house add-resident <house_id> <npc_id>
  ./dnd-agent house remove-resident <house_id> <npc_id>
  ./dnd-agent house list-residents <house_id>
  ```
- **Shops (Commercial Properties)**:
  ```bash
  ./dnd-agent shop add <location_id> <name> [description] [npc_id] [scale] [open_hours]
  ./dnd-agent shop list <location_id>
  ./dnd-agent shop set-inventory <id> <text>
  ```
- **Encounters**:
  ```bash
  ./dnd-agent encounter add <location_id> <type> [description] [npc_id]
  ./dnd-agent encounter list <location_id>
  ```
- **Setpieces (Story-Driving Locations)**:
  ```bash
  ./dnd-agent setpiece add <location_id> <name> [description] [chapter_event]
  ./dnd-agent setpiece list <location_id>
  ```
  *When `chapter_event` is non-empty, it becomes an AI system instruction when the party enters.*
- **Check Property Access (Decay-Aware)**:
  ```bash
  ./dnd-agent can-enter <house|shop|location> <id> [visitor_npc_id] [visitor_char_id] [in_game_day]
  ```
  *O(1) access check with exponential relationship decay. Returns `allowed`, `wary`, or `denied`.*

---

### 13. Factions & Standings
Configure factions and standings metrics.

- **Create Faction**:
  ```bash
  ./dnd-agent faction create <name> <description>
  ```
- **Join Faction**:
  ```bash
  ./dnd-agent faction join <char|npc> <id> <faction_id>
  ```
- **Set Character Standing**:
  ```bash
  ./dnd-agent faction set-standing <character_id> <faction_id> <standing> [notes]
  ```
- **Get Character Standings**:
  ```bash
  ./dnd-agent faction get-standing <character_id> [faction_id]
  ```
- **Set Party Standing** (institutional party-wide reputation):
  ```bash
  ./dnd-agent faction set-party-standing <campaign_id> <faction_id> <standing> [notes]
  ```
- **Get Party Standings**:
  ```bash
  ./dnd-agent faction get-party-standing <campaign_id> [faction_id]
  ```
- **Effective Standing** (computed, non-canonical display):
  ```bash
  ./dnd-agent faction effective-standing <campaign_id> <faction_id>
  ```

---

### 14. Spells & Features
Manage spell libraries, features, and character spellbooks.

- **Spells Library**:
  ```bash
  ./dnd-agent spell upsert <name> <level> <school> <casting_time> <range> <components> <duration> <description>
  ./dnd-agent spell list
  ```
- **Character Spellbook**:
  ```bash
  ./dnd-agent spell learn <char_id> <spell_id> [prepared_0/1] [class_name] [source]
  ./dnd-agent spell forget <char_id> <spell_id>
  ./dnd-agent spell prepare <char_id> <spell_id> <0/1>
  ./dnd-agent spell list-character <char_id>
  ```
- **Features Library (Traits & Feats)**:
  ```bash
  ./dnd-agent feature upsert <name> <source> <description>
  ./dnd-agent feature list
  ```
- **Grant Feature to Character**:
  ```bash
  ./dnd-agent feature add-to-char <char_id> <feature_id>
  ```
- **List Character Features**:
  ```bash
  ./dnd-agent feature list-character <char_id>
  ```

---

### 15. Items & Inventory Management
Enforce items configurations and map item ownership, equipment, and attunement status.

- **Create/Modify Item Blueprint**:
  ```bash
  ./dnd-agent item upsert <name> <description> <type> [damage_dice] [damage_type] [ac_bonus] [properties] [weight] [value_gp]
  ```
- **Add Item to Inventory**:
  ```bash
  ./dnd-agent inventory add <char|npc|creature> <id> <item_id> <qty>
  ```
- **Remove/Deduct Item**:
  ```bash
  ./dnd-agent inventory remove <char|npc|creature> <id> <item_id> <qty>
  ```
- **Toggle Equipped Status**:
  ```bash
  ./dnd-agent inventory equip <char|npc|creature> <id> <item_id> <0/1>
  ```
- **Toggle Attunement Status**:
  ```bash
  ./dnd-agent inventory attune <char|npc|creature> <id> <item_id> <0/1>
  ```

---

---

### 16. Combat Engine

Full D&D 5e turn-based combat tracking with attack resolution, damage application, saving throws, initiative, conditions, death saves, and reactions.

- **Start Combat**:
  ```bash
  ./dnd-agent combat start <campaign_id> <location_id>
  ```
- **Add Participants**:
  ```bash
  ./dnd-agent combat join <encounter_id> <char|npc|creature> <id> <initiative_roll> [initiative_mod] [position]
  ./dnd-agent combat join-all <encounter_id>
  ```
- **Lock Turn Order**:
  ```bash
  ./dnd-agent combat init <encounter_id>
  ```
- **Advance Turn**:
  ```bash
  ./dnd-agent combat next <encounter_id>
  ```
- **Resolve Attack (roll vs AC)**:
  ```bash
  ./dnd-agent combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <attack_roll> [ability] [adv|disadv]
  ```
  *Auto-computes attack modifier (proficiency + ability mod for characters, attack_bonus for NPCs/creatures). Includes cover bonus from target position.*
- **Apply Damage**:
  ```bash
  ./dnd-agent combat damage <encounter_id> <target_type> <target_id> <amount> <type> [source]
  ```
  *Auto-applies resistance (half), vulnerability (double), immunity (zero). Depletes temp HP first. Tracks concentration break DC, handles death at 0 HP.*
- **Saving Throw**:
  ```bash
  ./dnd-agent combat save <encounter_id> <actor_type> <actor_id> <ability> <save_roll> [dc] [adv|disadv]
  ```
  *Applies ability mod + save proficiency (characters only) + cover bonus.*
- **Move/Position**:
  ```bash
  ./dnd-agent combat move <encounter_id> <actor_type> <actor_id> <position>
  ```
  *Positions: melee, ranged, cover, hidden, fleeing. Warns about opportunity attacks when leaving melee.*
- **Death Saving Throw**:
  ```bash
  ./dnd-agent combat death-save <character_id> <roll>
  ```
  *Nat 20: regains 1 HP. Nat 1: 2 failures. 3 successes: stabilized. 3 failures: dead.*
- **Use Reaction**:
  ```bash
  ./dnd-agent combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]
  ```
- **Ready Action**:
  ```bash
  ./dnd-agent combat ready <encounter_id> <actor_type> <actor_id> "<action>" <trigger>
  ```
- **Apply Condition**:
  ```bash
  ./dnd-agent combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]
  ```
- **View Combat Status**:
  ```bash
  ./dnd-agent combat status <encounter_id> [--json]
  ```
  *Shows full turn order with HP/AC/position/flags for every participant.*
- **End Combat**:
  ```bash
  ./dnd-agent combat end <encounter_id>
  ```
  *Archives encounter, clears combat flags on all character participants.*

---

## Automatic Database Schema Migrations
The tool handles schema updates automatically using SQLite's internal versioning integer `PRAGMA user_version`. 

When the CLI starts up, it reads the current schema version of `dnd-agent.db`. If the database is new or has an older version, the tool executes all missing forward-only SQL migration blocks sequentially and stamps the new version number onto the file. This requires zero setup or manual commands from the Dungeon Master, keeping campaign data intact.

---

## Example Walkthrough Scenario

Below is an example session tracking story progression, character resting resources, and combat damage depletion.

```bash
# 1. Initialize DB and Campaign
./dnd-agent init
./dnd-agent campaign create "Phandelver"
./dnd-agent campaign set-chapter 1 "Chapter 1: Goblin Arrows"

# 2. Configure Locations
./dnd-agent campaign add-location 1 "Phandalin" "A small frontier town." "Chapter 1"
./dnd-agent campaign add-location 1 "Cragmaw Hideout" "Goblin cave system." "Chapter 1"
./dnd-agent campaign set-location 1 1 # Start in Phandalin

# 3. Create Player Character
./dnd-agent character create "Grog" Barbarian 5 60
./dnd-agent character set-campaign 1 1
./dnd-agent character set-details 1 15 human 40 chaotic_good medium

# 4. Set Skill Proficiencies
./dnd-agent character set-skill 1 athletics 1
./dnd-agent character set-skill 1 stealth 2

# 5. Set up Resting Resources
./dnd-agent character set-resource 1 Rage 3 3 long_rest
./dnd-agent character set-resource 1 "Second Wind" 1 1 short_rest

# 6. Combat Scenario: Add Temp HP and Take Damage
./dnd-agent character set-temp-hp 1 15
./dnd-agent character damage 1 10 # Grog takes 10 damage
# Output: Character HP now: 60/60 (Temp HP: 5) (Took 10 damage)

./dnd-agent character damage 1 10 # Grog takes another 10 damage
# Output: Character HP now: 55/60 (Temp HP: 0) (Took 10 damage)

# 6b. Short Rest (spend hit dice to heal after taking damage)
./dnd-agent rest short 1 2
# Output: Short rest: character 1 healed 14 HP, spent 2 hit dice.

# 6c. Combat Encounter with the new engine
./dnd-agent creature create "Goblin Scout" 7 7 14 10 12 12 8 10 1 1 1 1
./dnd-agent combat start 1 1
./dnd-agent combat join 1 character 1 18
./dnd-agent combat join 1 creature 1 8
./dnd-agent combat init 1
./dnd-agent combat attack 1 character 1 creature 1 15 str
./dnd-agent combat damage 1 creature 1 7 slashing "Grog's greataxe"
./dnd-agent combat end 1

# 7. Log Story Actions and Link Actors
./dnd-agent faction create "Harpers" "Defenders of peace."
./dnd-agent faction join char 1 1
./dnd-agent campaign add-action 1 "Defeated goblin scouts near Phandalin" 1 1 5 3 "completed"
./dnd-agent campaign link-actor 1 char 1

# 8. View Complete Campaign Status
./dnd-agent campaign get-story-state 1
```
