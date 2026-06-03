# dnd-agent

> D&D campaign management CLI — track characters, NPCs, items, spells, factions, and campaign storylines from your terminal.

[![Odin](https://img.shields.io/badge/Odin-dev--2026--05-blue?logo=odin&logoColor=white)](https://odin-lang.org)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue?logo=linux&logoColor=white)](https://github.com/xDarkicex/dnd-agent/actions)
[![Build](https://github.com/xDarkicex/dnd-agent/actions/workflows/release.yml/badge.svg)](https://github.com/xDarkicex/dnd-agent/actions/workflows/release.yml)

## Why dnd-agent?

- **Script-friendly** — `--json` output for piping into AI agent pipelines, bots, or automation.
- **Rich 5e tracking** — multiclass characters, spell slots, companions, factions, story log.
- **Zero-config** — automatic SQLite schema migrations on first run.
- **Fast** — arena-based memory, O(1) DB lookups, zero heap allocations after startup.
- **Deep inventory** — items, equipment, attuned status across characters, NPCs, and creatures.

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
1. [Installation & Build](#installation--build)
2. [Database Schema](#database-schema)
3. [Global Output Flags](#global-output-flags)
4. [CLI Command Reference](#cli-command-reference)
   - [Characters & Multiclassing](#1-characters--multiclassing)
   - [Vitals & Resting Setters](#2-vitals--resting-setters)
   - [Skills & Proficiencies](#3-skills--proficiencies)
   - [Class Resources & Spell Slots](#4-class-resources--spell-slots)
   - [Companions & Pets](#5-companions--pets)
   - [NPCs & Relationships](#6-npcs--relationships)
   - [Creatures & Monsters](#7-creatures--monsters)
   - [Campaigns, Locations, & Story Tracking](#8-campaigns-locations--story-tracking)
   - [Factions & Standings](#9-factions--standings)
   - [Spells & Features](#10-spells--features)
   - [Items & Inventory Management](#11-items--inventory-management)
5. [Automatic Database Schema Migrations](#automatic-database-schema-migrations)
6. [Example Walkthrough Scenario](#example-walkthrough-scenario)

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
- **Configure Ability Scores & Base Details**:
  ```bash
  ./dnd-agent character set-stats <id> <str> <dex> <con> <int> <wis> <cha>
  ./dnd-agent character set-save-prof <id> <str_0/1> <dex_0/1> <con_0/1> <int_0/1> <wis_0/1> <cha_0/1>
  ./dnd-agent character set-details <id> <ac> <race> <speed> [alignment] [size]
  ```

---

### 3. Skills & Proficiencies
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

### 4. Class Resources & Spell Slots
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
- **Perform Rest (Resets resources based on condition)**:
  ```bash
  ./dnd-agent character reset-resources <char_id> [reset_condition]
  ```
  *A `long_rest` automatically triggers reset for both `long_rest` and `short_rest` resource types.*

---

### 5. Companions & Pets
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

### 6. NPCs & Relationships
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
- **Manage Relationship (Friendship metrics)**:
  ```bash
  ./dnd-agent npc set-relationship <npc_id_1> <npc_id_2> <friendship_level> [notes]
  ```
  *Friendship level scale: `-10` (Archnemesis) to `+10` (Close Ally).*
- **List NPC Relationships**:
  ```bash
  ./dnd-agent npc list-relationships <npc_id>
  ```
- **Assign NPC Active Location**:
  ```bash
  ./dnd-agent npc set-location <npc_id> <location_id>
  ```

---

### 7. Creatures & Monsters
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
- **Link Creature to Campaign Location**:
  ```bash
  ./dnd-agent creature set-location <creature_id> <location_id>
  ```

---

### 8. Campaigns, Locations, & Story Tracking
Track the session number, current location, logged events, and generate a comprehensive campaign status report.

- **Create Campaign**:
  ```bash
  ./dnd-agent campaign create <name>
  ```
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
- **Advance Session**:
  ```bash
  ./dnd-agent campaign next-session <campaign_id>
  ```
- **Get Complete Story State & Report**:
  ```bash
  ./dnd-agent campaign get-story-state <campaign_id> [--json]
  ```
  *Prints a report including session details, current location, location list, characters' standings with factions, and a chronological campaign story log.*

---

### 9. Factions & Standings
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
- **Get Standings**:
  ```bash
  ./dnd-agent faction get-standing <character_id> [faction_id]
  ```

---

### 10. Spells & Features
Manage spell libraries, features, and character spellbooks.

- **Spells Library**:
  ```bash
  ./dnd-agent spell upsert <name> <level> <school> <casting_time> <range> <components> <duration> <description>
  ./dnd-agent spell list
  ```
- **Character Spellbook**:
  ```bash
  ./dnd-agent spell learn <char_id> <spell_id> [prepared_0/1]
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

### 11. Items & Inventory Management
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

# 7. Log Story Actions and Link Actors
./dnd-agent faction create "Harpers" "Defenders of peace."
./dnd-agent faction join char 1 1
./dnd-agent campaign add-action 1 "Defeated goblin scouts near Phandalin" 1 1 5 3 "completed"
./dnd-agent campaign link-actor 1 char 1

# 8. View Complete Campaign Status
./dnd-agent campaign get-story-state 1
```
