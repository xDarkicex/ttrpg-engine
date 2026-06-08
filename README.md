# ttrpg-engine

> The terminal-native D&D world engine. Build your campaign as a living database — towns, shops, NPCs, quests, session journals, faction politics — then query it from the command line or feed it to an AI Dungeon Master.

[![Odin](https://img.shields.io/badge/Odin-dev--2026--05-blue?logo=odin&logoColor=white)](https://odin-lang.org)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue?logo=linux&logoColor=white)](https://github.com/xDarkicex/ttrpg-engine/actions)
[![Build](https://github.com/xDarkicex/ttrpg-engine/actions/workflows/release.yml/badge.svg)](https://github.com/xDarkicex/ttrpg-engine/actions/workflows/release.yml)

## The World Engine

ttrpg-engine models your tabletop world as a **relational database** — every tavern, blacksmith, quest giver, and goblin camp is a row you can query, update, and connect. It was built for DMs who run long-form campaigns with deep continuity, and for AI agents that need a canonical source of truth about the game state.

**The world model.** You create a campaign. Inside it, you build locations — towns, districts, dungeons. Locations nest into sub-locations (`Ashwick > Blacksmith District > The Anvil & Flame`). Each location holds houses (with residents and inventory), shops (with opening hours and proprietors), wandering encounters, and story-driving setpieces. NPCs, characters, and creatures all have a location — the CLI tells you exactly who is where right now.

**The memory system.** A stateless AI agent only knows what you tell it. ttrpg-engine solves this with three systems working together: a **campaign journal** (timestamped session recaps the AI writes and reads back), a **quest tracker** (step-by-step objectives with linked actors, so the AI remembers what the party is supposed to be doing), and an **in-game calendar** (day, time of day, season) so the AI can say "it's autumn evening on day 42." One command — `campaign get-story-state` — returns the complete context packet the AI needs to reconstruct the game from a cold start.

**The combat engine.** Turn-based D&D 5e combat lives inside the database. `combat start`, `combat join`, `combat init` set up the encounter. `combat attack` resolves attack rolls against AC, `combat damage` applies damage with automatic resistance/vulnerability/immunity. `combat save` handles saving throws with proficiency bonuses. `combat next` advances turns, resets reactions each round. Death saves, concentration, conditions, reactions, and ready actions are all tracked. The combat snapshot appears in `get-story-state` — the AI always knows who's up, what HP everyone has, and what conditions are active.

**The relationship graph.** NPCs have friendships, rivalries, and family ties with each other (tracked with a decay-aware score). Characters have personal faction standings, and campaigns track party-wide institutional faction reputation — a faction can hate one PC but still mark the party as hostile for the group's actions. Houses have residents. Quests have quest givers and participants. Every entity can be linked to every other entity — the database IS the campaign bible.

**Built for AI pipelines.** Every command emits `--json` output for piping into LLM agents, Discord bots, or automation scripts. The schema is designed so an AI can call `get-story-state`, receive the full world snapshot (locations tree with all entities present, active quests, recent journal entries, faction standings, story log), and immediately begin DMing with full context. No warm-up, no context-stuffing — one query, everything it needs.

**Fast by design.** O(1) database lookups. Arena-based memory with zero heap allocations after startup. Automatic SQLite schema migrations — drop the binary into a campaign folder and run. No config files, no daemons, no network calls. Just a 2.6 MB binary and a `.db` file you can commit to git alongside your session notes.

## Install

### macOS — Homebrew (recommended)

```sh
brew tap xDarkicex/ttrpg-engine
brew install ttrpg-engine
```

### Linux — Tarball

```sh
curl -sL https://github.com/xDarkicex/ttrpg-engine/releases/latest/download/ttrpg-engine-unknown-linux.tar.gz | tar -xz
chmod +x ttrpg-engine
./ttrpg-engine init
```

### macOS — Tarball

```sh
curl -sL https://github.com/xDarkicex/ttrpg-engine/releases/latest/download/ttrpg-engine-apple-darwin.tar.gz | tar -xz
chmod +x ttrpg-engine
./ttrpg-engine init
```

### Build from source

```sh
odin build . -file -collection:ext=./vendor -out:ttrpg-engine
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
* **Build Binary**: `make build` (Produces the `ttrpg-engine` binary)
* **Run Tests**: `make test` (Runs package-wide unit tests)
* **Initialize Database**: `./ttrpg-engine init` (Creates the schema inside `ttrpg-engine.db`)
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
./ttrpg-engine character list --json
```

---

## CLI Command Reference

### 1. Characters & Multiclassing
Create, delete, list, and view detailed player character sheets.

- **Create Character**:
  ```bash
  ./ttrpg-engine character create <name> <class> <level> <max_hp>
  ```
- **List Characters**:
  ```bash
  ./ttrpg-engine character list [--json]
  ```
- **Get Detailed Character Sheet**:
  ```bash
  ./ttrpg-engine character get <id> [--json]
  ```
  *Displays multiclass summaries, base ability scores, saves, vitals, money, skills, and resources.*
- **Delete Character**:
  ```bash
  ./ttrpg-engine character delete <id>
  ```
- **Add or Level Up Class (Multiclassing)**:
  ```bash
  ./ttrpg-engine character add-class <char_id> <class_name> <level>
  ```
- **List Character Classes**:
  ```bash
  ./ttrpg-engine character list-classes <char_id>
  ```
- **Award XP**:
  ```bash
  ./ttrpg-engine character add-xp <id> <amount>
  ```
- **Manage Money (Supports Gold, Silver, Copper, Platinum, Electrum)**:
  ```bash
  ./ttrpg-engine character add-money <id> <gp> <sp> <cp> [pp] [ep]
  ./ttrpg-engine character remove-money <id> <gp> <sp> <cp> [pp] [ep]
  ```

---

### 2. Vitals & Resting Setters
Manage combat conditions, resting metrics, and temporary states.

- **Apply Combat Damage (Depletes Temporary HP first)**:
  ```bash
  ./ttrpg-engine character damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ```
  *Handles evasion feats, races, resistances, vulnerabilities, immunities, and saving throw modifier calculations automatically.*
- **Apply Healing**:
  ```bash
  ./ttrpg-engine character heal <id> <amount>
  ```
- **Set Temporary Hit Points**:
  ```bash
  ./ttrpg-engine character set-temp-hp <id> <amount>
  ```
- **Set Death Saving Throws**:
  ```bash
  ./ttrpg-engine character set-death-saves <id> <successes_count> <failures_count>
  ```
- **Set Exhaustion Levels (0 to 6)**:
  ```bash
  ./ttrpg-engine character set-exhaustion <id> <level>
  ```
- **Set Spent Hit Dice**:
  ```bash
  ./ttrpg-engine character set-hit-dice <id> <expended_count>
  ```
- **Set Inspiration**:
  ```bash
  ./ttrpg-engine character set-inspiration <id> <0/1>
  ```
- **Set Backstory**:
  ```bash
  ./ttrpg-engine character set-backstory <id> <backstory>
  ```
- **Set Location**:
  ```bash
  ./ttrpg-engine character set-location <id> <location_id>
  ```
- **Set Chapter**:
  ```bash
  ./ttrpg-engine character set-chapter <id> <chapter_id>
  ```
- **Set Owner**:
  ```bash
  ./ttrpg-engine character set-owner <id> <owner_name>
  ```
- **Configure Ability Scores & Base Details**:
  ```bash
  ./ttrpg-engine character set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ./ttrpg-engine character set-save-prof <id> <str_0/1> <dex_0/1> <con_0/1> <int_0/1> <wis_0/1> <cha_0/1>
  ./ttrpg-engine character set-details <id> <ac> <race> <speed> [alignment] [size]
  ```

---

### 3. Combat Stats & Spellcasting
Set D&D 5e combat math: proficiency bonus, initiative, spell save DC, spell attack bonus, passive perception, languages, max hit dice, concentration, and the combat-engaged flag (consumed by an external combat engine).

- **Set Proficiency Bonus**:
  ```bash
  ./ttrpg-engine character set-proficiency <id> <bonus>
  ```
- **Set Spellcasting (DC + Spell Attack)**:
  ```bash
  ./ttrpg-engine character set-spellcasting <id> <dc> <attack_bonus>
  ```
- **Set Initiative Modifier**:
  ```bash
  ./ttrpg-engine character set-initiative <id> <modifier>
  ```
- **Set Passive Perception**:
  ```bash
  ./ttrpg-engine character set-passive-perception <id> <value>
  ```
- **Set Languages (Comma-Separated)**:
  ```bash
  ./ttrpg-engine character set-languages <id> <csv>
  ```
- **Set Max Hit Dice**:
  ```bash
  ./ttrpg-engine character set-max-hit-dice <id> <amount>
  ```
- **Set Concentration Spell (Blank to Clear)**:
  ```bash
  ./ttrpg-engine character set-concentrating <id> <spell_name_or_blank>
  ```
- **Toggle Combat State (0 = out, 1 = in combat)**:
  ```bash
  ./ttrpg-engine character set-combat <id> <0|1>
  ```
- **Add Weapon / Armor / Tool Proficiency**:
  ```bash
  ./ttrpg-engine character add-prof <id> <weapon|armor|tool> <name>
  ./ttrpg-engine character remove-prof <id> <weapon|armor|tool> <name>
  ```
- **Set Darkvision (Range in Feet, 0 = None)**:
  ```bash
  ./ttrpg-engine character set-darkvision <id> <range>
  ```

---

### 4. Conditions & Personality
Track D&D 5e conditions with source/duration/save metadata, and PHB personality hooks. Conditions are a top-level command (apply to character, NPC, or creature polymorphically).

- **Apply a Condition**:
  ```bash
  ./ttrpg-engine condition add <character|npc|creature> <id> <name> [source] [duration_rounds] [save_dc] [save_ability]
  ```
  *Example: `ttrpg-engine condition add character 1 restrained Web 10 13 STR` — restrained by Web, ends on STR save DC 13 or after 10 rounds.*
- **List Active Conditions on an Entity**:
  ```bash
  ./ttrpg-engine condition list <character|npc|creature> <id>
  ```
- **Remove a Condition**:
  ```bash
  ./ttrpg-engine condition remove <character|npc|creature> <id> <name>
  ```
- **Set Personality Hooks (PHB)**:
  ```bash
  ./ttrpg-engine character set-bond <id> <text>
  ./ttrpg-engine character set-flaw <id> <text>
  ./ttrpg-engine character set-ideal <id> <text>
  ./ttrpg-engine character set-personality-traits <id> <text>
  ./ttrpg-engine character set-appearance <id> <text>
  ```

---

### 5. Skills & Proficiencies
Manage skill proficiencies. Modifiers are calculated dynamically based on 5e rules.

- **Set Skill Proficiency Level**:
  ```bash
  ./ttrpg-engine character set-skill <char_id> <skill_name> <level>
  ```
  *Levels: `0` = none, `1` = proficient, `2` = expertise.*
- **List Character Skill Proficiencies**:
  ```bash
  ./ttrpg-engine character list-skills <char_id>
  ```

---

### 6. Class Resources & Spell Slots
Track custom class resource pools (Rage, Ki, Sorcery Points) and spell slots.

- **Configure Resource Pool**:
  ```bash
  ./ttrpg-engine character set-resource <char_id> <resource_name> <max> <current> [reset_condition]
  ```
  *Reset conditions: `short_rest` or `long_rest` (default `long_rest`).*
- **Spend Resource**:
  ```bash
  ./ttrpg-engine character use-resource <char_id> <resource_name> [amount]
  ```
- **List Active Resources**:
  ```bash
  ./ttrpg-engine character list-resources <char_id>
  ```
- **Short Rest (Spend hit dice to heal)**:
  ```bash
  ./ttrpg-engine rest short <character_id> <hit_dice_count>
  ```
  *Heals hit_dice_count × (avg_hit_die + CON_mod). Resets short-rest resources, decrements available short rests, clears rest-duration conditions. Hit die size determined by character class (d6→4, d8→5, d10→6, d12→7 average).*
- **Long Rest (Full recovery)**:
  ```bash
  ./ttrpg-engine rest long <character_id>
  ```
  *Full HP heal, clears temp HP, recovers half expended hit dice, reduces exhaustion by 1, resets all spell slots and resources, resets available rests to 2/1, clears short/long/until_rest conditions.*

- **Manual Resource Reset (for fine-grained control)**:
  ```bash
  ./ttrpg-engine character reset-resources <char_id> [reset_condition]
  ```
  *A `long_rest` automatically triggers reset for both `long_rest` and `short_rest` resource types.*
- **Set Spell Slot by Level (Track Max and Used)**:
  ```bash
  ./ttrpg-engine character set-spell-slot <id> <slot_level> <max> <used>
  ```

---

### 7. Companions & Pets
Track character companions, mounts, pets, and familiars.

- **Create Companion**:
  ```bash
  ./ttrpg-engine companion create <char_id> <name> <type> <level> <max_hp> <ac> <attack_bonus> <damage_dice>
  ```
- **Set Companion Stats**:
  ```bash
  ./ttrpg-engine companion set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **List Companions**:
  ```bash
  ./ttrpg-engine companion list [char_id]
  ```
- **View Companion Details**:
  ```bash
  ./ttrpg-engine companion get <id>
  ```
- **Damage/Heal Companion**:
  ```bash
  ./ttrpg-engine companion damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./ttrpg-engine companion heal <id> <amount>
  ```

---

### 8. NPCs & Relationships
Manage campaign NPCs, daily roles, location, and interpersonal relationships.

- **Create NPC**:
  ```bash
  ./ttrpg-engine npc create <name> <description> <max_hp> <campaign_id>
  ```
- **Set NPC details**:
  ```bash
  ./ttrpg-engine npc set-details <id> <ac> <story_role> <daily_role> <backstory>
  ```
- **Configure NPC Ability Scores**:
  ```bash
  ./ttrpg-engine npc set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **Manage NPC Abilities/Traits**:
  ```bash
  ./ttrpg-engine npc add-ability <npc_id> <feature_id>
  ./ttrpg-engine npc remove-ability <npc_id> <feature_id>
  ./ttrpg-engine npc list-abilities <npc_id>
  ```
- **Manage Relationship (Friendship + Type)**:
  ```bash
  ./ttrpg-engine npc set-relationship <npc_id_1> <npc_id_2> <friendship_level> [type] [notes]
  ```
  *Type: spouse, family, friend, rival, enemy, acquaintance, ally. Friendship level: -10 to +10.*
  *Friendship level scale: `-10` (Archnemesis) to `+10` (Close Ally).*
- **List NPC Relationships**:
  ```bash
  ./ttrpg-engine npc list-relationships <npc_id>
  ```
- **Assign NPC Active Location**:
  ```bash
  ./ttrpg-engine npc set-location <npc_id> <location_id>
  ```
- **Set Challenge Rating**:
  ```bash
  ./ttrpg-engine npc set-cr <id> <cr>
  ```
- **Set NPC Attack (Bonus, Damage Dice, Damage Type)**:
  ```bash
  ./ttrpg-engine npc set-attack <id> <bonus> <damage_dice> <damage_type>
  ```
- **Set NPC Initiative**:
  ```bash
  ./ttrpg-engine npc set-initiative <id> <modifier>
  ```
- **Set NPC Passive Perception**:
  ```bash
  ./ttrpg-engine npc set-passive-perception <id> <value>
  ```
- **Set NPC Languages (Comma-Separated)**:
  ```bash
  ./ttrpg-engine npc set-languages <id> <csv>
  ```
- **Set NPC Concentration (Blank to Clear)**:
  ```bash
  ./ttrpg-engine npc set-concentrating <id> <spell_name_or_blank>
  ```
- **Toggle NPC Combat State (0/1)**:
  ```bash
  ./ttrpg-engine npc set-combat <id> <0|1>
  ```
- **Set NPC Skill (Proficiency Level)**:
  ```bash
  ./ttrpg-engine npc set-skill <npc_id> <skill_name> <proficiency_level>
  ./ttrpg-engine npc remove-skill <npc_id> <skill_name>
  ```
  *proficiency_level: 0=none, 1=proficient, 2=expertise. Total modifier is computed from ability scores + prof_bonus * level.*
- **Set NPC Darkvision (Range in Feet)**:
  ```bash
  ./ttrpg-engine npc set-darkvision <id> <range>
  ```
- **Set NPC Personality Hooks (Bond/Flaw/Ideal/Traits/Appearance)**:
  ```bash
  ./ttrpg-engine npc set-bond <id> <text>
  ./ttrpg-engine npc set-flaw <id> <text>
  ./ttrpg-engine npc set-ideal <id> <text>
  ./ttrpg-engine npc set-personality-traits <id> <text>
  ./ttrpg-engine npc set-appearance <id> <text>
  ```
- **Manage NPC Tool Proficiencies** (e.g. `smith's tools`, `herbalism kit`):
  ```bash
  ./ttrpg-engine npc add-tool-prof <npc_id> <tool_name>
  ./ttrpg-engine npc remove-tool-prof <npc_id> <tool_name>
  ```

---

### 9. Creatures & Monsters
Manage active monsters, beasts, and campaign enemies. Supports ability scores, loot currencies, loot inventory tables, and custom traits.

- **Create Creature Preset**:
  ```bash
  ./ttrpg-engine creature create <name> <max_hp> <ac> <attacks> <story_role> <campaign_id>
  ```
- **List Active Creatures**:
  ```bash
  ./ttrpg-engine creature list
  ```
- **Get Creature Details**:
  ```bash
  ./ttrpg-engine creature get <id> [--json]
  ```
  *Displays HP, AC, linked campaign/location, full ability scores, loot currency, abilities, and inventory items.*
- **Apply Combat Damage/Healing**:
  ```bash
  ./ttrpg-engine creature damage <id> <amount> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./ttrpg-engine creature heal <id> <amount>
  ```
- **Configure Creature Ability Scores**:
  ```bash
  ./ttrpg-engine creature set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ```
- **Manage Loot Currency**:
  ```bash
  ./ttrpg-engine creature add-money <id> <gp> <sp> <cp> [pp] [ep]
  ./ttrpg-engine creature remove-money <id> <gp> <sp> <cp> [pp] [ep]
  ```
- **Manage Creature Abilities/Traits**:
  ```bash
  ./ttrpg-engine creature add-ability <creature_id> <feature_id>
  ./ttrpg-engine creature remove-ability <creature_id> <feature_id>
  ./ttrpg-engine creature list-abilities <creature_id>
  ```
- **Update Active Status/Combat Conditions**:
  ```bash
  ./ttrpg-engine creature set-status <id> <status_effects>
  ./ttrpg-engine creature set-combat-meta <id> <resistances> <vulnerabilities> <immunities>
  ./ttrpg-engine creature set-action <id> <action>
  ```
- **Set Creature Attack (Bonus, Damage Dice, Damage Type)**:
  ```bash
  ./ttrpg-engine creature set-attack <id> <bonus> <damage_dice> <damage_type>
  ```
- **Set Creature Challenge Rating**:
  ```bash
  ./ttrpg-engine creature set-cr <id> <cr>
  ```
- **Set Creature Initiative**:
  ```bash
  ./ttrpg-engine creature set-initiative <id> <modifier>
  ```
- **Set Creature Passive Perception**:
  ```bash
  ./ttrpg-engine creature set-passive-perception <id> <value>
  ```
- **Set Creature Reactions (Free-Form Text)**:
  ```bash
  ./ttrpg-engine creature set-reactions <id> <text>
  ```
- **Set Creature Legendary Actions (Free-Form Text)**:
  ```bash
  ./ttrpg-engine creature set-legendary <id> <text>
  ```
- **Toggle Creature Combat State (0/1)**:
  ```bash
  ./ttrpg-engine creature set-combat <id> <0|1>
  ```
- **Set Creature Darkvision (Range in Feet)**:
  ```bash
  ./ttrpg-engine creature set-darkvision <id> <range>
  ```
- **Link Creature to Campaign Location**:
  ```bash
  ./ttrpg-engine creature set-location <creature_id> <location_id>
  ```

---

### 10. Campaigns, Story Tracking & Session Continuity
Manage the campaign world, track sessions, log story events, write session recaps, and generate the AI context packet.

- **Create Campaign**:
  ```bash
  ./ttrpg-engine campaign create <name>
  ```
- **Set Campaign Chapter**:
  ```bash
  ./ttrpg-engine campaign set-chapter <id> <chapter>
  ```
- **Advance Session Number**:
  ```bash
  ./ttrpg-engine campaign next-session <campaign_id>
  ```
- **Set In-Game Calendar**:
  ```bash
  ./ttrpg-engine campaign set-time <campaign_id> <in_game_day> <time_of_day> <season>
  ```
  *Example: `ttrpg-engine campaign set-time 1 42 evening autumn` — it is day 42, evening, in autumn.*
- **Set Private DM Notes**:
  ```bash
  ./ttrpg-engine campaign set-dm-notes <campaign_id> <text>
  ```
  *Hidden notes visible in the story state report; never shown to players.*
- **Add Location to Campaign**:
  ```bash
  ./ttrpg-engine campaign add-location <campaign_id> <name> <description> [chapter]
  ```
- **Set Campaign's Active Location**:
  ```bash
  ./ttrpg-engine campaign set-location <campaign_id> <location_id>
  ```
- **Log Plot/Story Action**:
  ```bash
  ./ttrpg-engine campaign add-action <campaign_id> <description> [location_id] [faction_id] [standing_impact] [story_progression] [status]
  ```
- **Link Actor (Player/NPC) to Story Action**:
  ```bash
  ./ttrpg-engine campaign link-actor <action_id> <char|npc> <actor_id>
  ```
- **Add Journal Entry (Session Recap)**:
  ```bash
  ./ttrpg-engine campaign add-journal-entry <campaign_id> <entry_type> <description> [location_id] [session_num]
  ```
  *Entry types: `narrative`, `combat`, `decision`, `npc_interaction`, `quest_update`, `dm_note`. The AI writes these to remember what happened; get-story-state loads the last 10 for session continuity.*
- **List Journal Entries**:
  ```bash
  ./ttrpg-engine campaign list-journal <campaign_id> [limit]
  ```
- **Get Complete Story State (AI Context Packet)**:
  ```bash
  ./ttrpg-engine campaign get-story-state <campaign_id> [--json]
  ```
  *Returns the full context packet: campaign metadata with in-game time, DM notes, last 10 journal entries, active quests with objectives and actors, location tree with all entities present (sub-locations, houses, shops, encounters, setpieces, NPCs, characters, creatures), factions, NPC relationships, character faction standings, party faction standings, active combat encounter with turn order/HP/conditions, and chronological story log. This is the single command an AI agent calls to reconstruct the entire game state.*

---

### 11. Quest Tracking
Track campaign quests with step-by-step objectives and linked actors. Quests appear in the `get-story-state` context packet so the AI knows what the party is supposed to be doing.

- **Create Quest**:
  ```bash
  ./ttrpg-engine quest add <campaign_id> <name> [description] [quest_giver_npc_id] [reward] [chapter]
  ```
- **Add Objective (Step)**:
  ```bash
  ./ttrpg-engine quest add-objective <quest_id> <description> [sort_order]
  ```
- **Complete an Objective**:
  ```bash
  ./ttrpg-engine quest complete-objective <objective_id>
  ```
- **Update Quest Status**:
  ```bash
  ./ttrpg-engine quest set-status <quest_id> <active|completed|failed|abandoned>
  ```
- **Link Actor to Quest**:
  ```bash
  ./ttrpg-engine quest add-actor <quest_id> <char|npc> <actor_id> [role]
  ```
  *Roles: `leader`, `participant`, `target`, `observer`.*
- **List Quests for a Campaign**:
  ```bash
  ./ttrpg-engine quest list <campaign_id> [status]
  ```
- **Get Full Quest Details**:
  ```bash
  ./ttrpg-engine quest get <quest_id> [--json]
  ```
  *Returns quest metadata, all objectives with completion status, and all linked actors with names.*

---

### 12. World & Locations
Manage the campaign world: locations, sub-locations via `parent_id`, houses, shops, encounters, and setpieces. All commands are O(1) per query.

- **Set a Sub-location Parent (Recursive)**:
  ```bash
  ./ttrpg-engine location set-parent <id> <parent_id|0>
  ./ttrpg-engine location breadcrumb <id>
  ```
  *Breadcrumb walks the parent chain and prints `Ashwick > Blacksmith District > The Anvil & Flame`.*
- **Set Location Access Restriction**:
  ```bash
  ./ttrpg-engine location set-restricted <id> <0|1> <until>
  ```
- **Houses (Residential Properties)**:
  ```bash
  ./ttrpg-engine house add <location_id> <name> [description] [npc_id] [scale]
  ./ttrpg-engine house list <location_id>
  ./ttrpg-engine house set-inventory <id> <text>
  ./ttrpg-engine house set-restricted <id> <0|1> <until>
  ```
  *Inventory text is passed to the AI for on-the-fly item generation.*
- **House Residents (Multi-Resident, v17)**:
  ```bash
  ./ttrpg-engine house add-resident <house_id> <npc_id>
  ./ttrpg-engine house remove-resident <house_id> <npc_id>
  ./ttrpg-engine house list-residents <house_id>
  ```
- **Shops (Commercial Properties)**:
  ```bash
  ./ttrpg-engine shop add <location_id> <name> [description] [npc_id] [scale] [open_hours]
  ./ttrpg-engine shop list <location_id>
  ./ttrpg-engine shop set-inventory <id> <text>
  ```
- **Encounters**:
  ```bash
  ./ttrpg-engine encounter add <location_id> <type> [description] [npc_id]
  ./ttrpg-engine encounter list <location_id>
  ```
- **Setpieces (Story-Driving Locations)**:
  ```bash
  ./ttrpg-engine setpiece add <location_id> <name> [description] [chapter_event]
  ./ttrpg-engine setpiece list <location_id>
  ```
  *When `chapter_event` is non-empty, it becomes an AI system instruction when the party enters.*
- **Check Property Access (Decay-Aware)**:
  ```bash
  ./ttrpg-engine can-enter <house|shop|location> <id> [visitor_npc_id] [visitor_char_id] [in_game_day]
  ```
  *O(1) access check with exponential relationship decay. Returns `allowed`, `wary`, or `denied`.*

---

### 13. Factions & Standings
Configure factions and standings metrics.

- **Create Faction**:
  ```bash
  ./ttrpg-engine faction create <name> <description>
  ```
- **Join Faction**:
  ```bash
  ./ttrpg-engine faction join <char|npc> <id> <faction_id>
  ```
- **Set Character Standing**:
  ```bash
  ./ttrpg-engine faction set-standing <character_id> <faction_id> <standing> [notes]
  ```
- **Get Character Standings**:
  ```bash
  ./ttrpg-engine faction get-standing <character_id> [faction_id]
  ```
- **Set Party Standing** (institutional party-wide reputation):
  ```bash
  ./ttrpg-engine faction set-party-standing <campaign_id> <faction_id> <standing> [notes]
  ```
- **Get Party Standings**:
  ```bash
  ./ttrpg-engine faction get-party-standing <campaign_id> [faction_id]
  ```
- **Effective Standing** (computed, non-canonical display):
  ```bash
  ./ttrpg-engine faction effective-standing <campaign_id> <faction_id>
  ```

---

### 14. Spells & Features
Manage spell libraries, features, and character spellbooks.

- **Spells Library**:
  ```bash
  ./ttrpg-engine spell upsert <name> <level> <school> <casting_time> <range> <components> <duration> <description>
  ./ttrpg-engine spell list
  ```
- **Character Spellbook**:
  ```bash
  ./ttrpg-engine spell learn <char_id> <spell_id> [prepared_0/1] [class_name] [source]
  ./ttrpg-engine spell forget <char_id> <spell_id>
  ./ttrpg-engine spell prepare <char_id> <spell_id> <0/1>
  ./ttrpg-engine spell list-character <char_id>
  ```
- **Features Library (Traits & Feats)**:
  ```bash
  ./ttrpg-engine feature upsert <name> <source> <description>
  ./ttrpg-engine feature list
  ```
- **Grant Feature to Character**:
  ```bash
  ./ttrpg-engine feature add-to-char <char_id> <feature_id>
  ```
- **List Character Features**:
  ```bash
  ./ttrpg-engine feature list-character <char_id>
  ```

---

### 15. Items & Inventory Management
Enforce items configurations and map item ownership, equipment, and attunement status.

- **Create/Modify Item Blueprint**:
  ```bash
  ./ttrpg-engine item upsert <name> <description> <type> [damage_dice] [damage_type] [ac_bonus] [properties] [weight] [value_gp]
  ```
- **Add Item to Inventory**:
  ```bash
  ./ttrpg-engine inventory add <char|npc|creature> <id> <item_id> <qty>
  ```
- **Remove/Deduct Item**:
  ```bash
  ./ttrpg-engine inventory remove <char|npc|creature> <id> <item_id> <qty>
  ```
- **Toggle Equipped Status**:
  ```bash
  ./ttrpg-engine inventory equip <char|npc|creature> <id> <item_id> <0/1>
  ```
- **Toggle Attunement Status**:
  ```bash
  ./ttrpg-engine inventory attune <char|npc|creature> <id> <item_id> <0/1>
  ```

---

---

### 16. Combat Engine

Full D&D 5e turn-based combat tracking with attack resolution, damage application, saving throws, initiative, conditions, death saves, and reactions.

- **Start Combat**:
  ```bash
  ./ttrpg-engine combat start <campaign_id> <location_id>
  ```
- **Add Participants**:
  ```bash
  ./ttrpg-engine combat join <encounter_id> <char|npc|creature> <id> <initiative_roll> [initiative_mod] [position]
  ./ttrpg-engine combat join-all <encounter_id>
  ```
- **Lock Turn Order**:
  ```bash
  ./ttrpg-engine combat init <encounter_id>
  ```
- **Advance Turn**:
  ```bash
  ./ttrpg-engine combat next <encounter_id>
  ```
- **Resolve Attack (roll vs AC)**:
  ```bash
  ./ttrpg-engine combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <attack_roll> [ability] [adv|disadv]
  ```
  *Auto-computes attack modifier (proficiency + ability mod for characters, attack_bonus for NPCs/creatures). Includes cover bonus from target position.*
- **Apply Damage**:
  ```bash
  ./ttrpg-engine combat damage <encounter_id> <target_type> <target_id> <amount> <type> [source]
  ```
  *Auto-applies resistance (half), vulnerability (double), immunity (zero). Depletes temp HP first. Tracks concentration break DC, handles death at 0 HP.*
- **Saving Throw**:
  ```bash
  ./ttrpg-engine combat save <encounter_id> <actor_type> <actor_id> <ability> <save_roll> [dc] [adv|disadv]
  ```
  *Applies ability mod + save proficiency (characters only) + cover bonus.*
- **Move/Position**:
  ```bash
  ./ttrpg-engine combat move <encounter_id> <actor_type> <actor_id> <position>
  ```
  *Positions: melee, ranged, cover, hidden, fleeing. Warns about opportunity attacks when leaving melee.*
- **Death Saving Throw**:
  ```bash
  ./ttrpg-engine combat death-save <character_id> <roll>
  ```
  *Nat 20: regains 1 HP. Nat 1: 2 failures. 3 successes: stabilized. 3 failures: dead.*
- **Use Reaction**:
  ```bash
  ./ttrpg-engine combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]
  ```
- **Ready Action**:
  ```bash
  ./ttrpg-engine combat ready <encounter_id> <actor_type> <actor_id> "<action>" <trigger>
  ```
- **Apply Condition**:
  ```bash
  ./ttrpg-engine combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]
  ```
- **View Combat Status**:
  ```bash
  ./ttrpg-engine combat status <encounter_id> [--json]
  ```
  *Shows full turn order with HP/AC/position/flags for every participant.*
- **End Combat**:
  ```bash
  ./ttrpg-engine combat end <encounter_id>
  ```
  *Archives encounter, clears combat flags on all character participants.*

---

## Automatic Database Schema Migrations
The tool handles schema updates automatically using SQLite's internal versioning integer `PRAGMA user_version`. 

When the CLI starts up, it reads the current schema version of `ttrpg-engine.db`. If the database is new or has an older version, the tool executes all missing forward-only SQL migration blocks sequentially and stamps the new version number onto the file. This requires zero setup or manual commands from the Dungeon Master, keeping campaign data intact.

---

## Example Walkthrough Scenario

Below is an example session tracking story progression, character resting resources, and combat damage depletion.

```bash
# 1. Initialize DB and Campaign
./ttrpg-engine init
./ttrpg-engine campaign create "Phandelver"
./ttrpg-engine campaign set-chapter 1 "Chapter 1: Goblin Arrows"

# 2. Configure Locations
./ttrpg-engine campaign add-location 1 "Phandalin" "A small frontier town." "Chapter 1"
./ttrpg-engine campaign add-location 1 "Cragmaw Hideout" "Goblin cave system." "Chapter 1"
./ttrpg-engine campaign set-location 1 1 # Start in Phandalin

# 3. Create Player Character
./ttrpg-engine character create "Grog" Barbarian 5 60
./ttrpg-engine character set-campaign 1 1
./ttrpg-engine character set-details 1 15 human 40 chaotic_good medium

# 4. Set Skill Proficiencies
./ttrpg-engine character set-skill 1 athletics 1
./ttrpg-engine character set-skill 1 stealth 2

# 5. Set up Resting Resources
./ttrpg-engine character set-resource 1 Rage 3 3 long_rest
./ttrpg-engine character set-resource 1 "Second Wind" 1 1 short_rest

# 6. Combat Scenario: Add Temp HP and Take Damage
./ttrpg-engine character set-temp-hp 1 15
./ttrpg-engine character damage 1 10 # Grog takes 10 damage
# Output: Character HP now: 60/60 (Temp HP: 5) (Took 10 damage)

./ttrpg-engine character damage 1 10 # Grog takes another 10 damage
# Output: Character HP now: 55/60 (Temp HP: 0) (Took 10 damage)

# 6b. Short Rest (spend hit dice to heal after taking damage)
./ttrpg-engine rest short 1 2
# Output: Short rest: character 1 healed 14 HP, spent 2 hit dice.

# 6c. Combat Encounter with the new engine
./ttrpg-engine creature create "Goblin Scout" 7 7 14 10 12 12 8 10 1 1 1 1
./ttrpg-engine combat start 1 1
./ttrpg-engine combat join 1 character 1 18
./ttrpg-engine combat join 1 creature 1 8
./ttrpg-engine combat init 1
./ttrpg-engine combat attack 1 character 1 creature 1 15 str
./ttrpg-engine combat damage 1 creature 1 7 slashing "Grog's greataxe"
./ttrpg-engine combat end 1

# 7. Log Story Actions and Link Actors
./ttrpg-engine faction create "Harpers" "Defenders of peace."
./ttrpg-engine faction join char 1 1
./ttrpg-engine campaign add-action 1 "Defeated goblin scouts near Phandalin" 1 1 5 3 "completed"
./ttrpg-engine campaign link-actor 1 char 1

# 8. View Complete Campaign Status
./ttrpg-engine campaign get-story-state 1
```
