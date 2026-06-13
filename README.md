# ttrpg-engine

> The terminal-native 5e-compatible TTRPG world engine. Build your campaign as a living database — towns, shops, NPCs, quests, session journals, faction politics — then query it from the command line or feed it to an AI Dungeon Master.

[![Odin](https://img.shields.io/badge/Odin-dev--2026--05-blue?logo=odin&logoColor=white)](https://odin-lang.org)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Linux](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue?logo=linux&logoColor=white)](https://github.com/xDarkicex/ttrpg-engine/actions)
[![Build](https://github.com/xDarkicex/ttrpg-engine/actions/workflows/release.yml/badge.svg)](https://github.com/xDarkicex/ttrpg-engine/actions/workflows/release.yml)


## Agent Rules (read before doing anything else)

The SQLite database is an internal implementation detail, **not the API**. The `ttrpg-engine` binary is the sole interface to canonical state.

**Agents MUST:**

- Use `ttrpg-engine` subcommands for all reads and writes
- Call `campaign get-story-state --json` to load world state
- Treat the `.db` file as opaque — back it up, copy it, but never open it for writes
- Let the binary run schema migrations automatically on startup

**Agents MUST NOT:**

- Run `sqlite3` against the campaign database for any reason
- Execute `CREATE`, `ALTER`, `DROP`, `INSERT`, `UPDATE`, or `DELETE` against the `.db`
- Infer schema from `docs/schema.md` and write rows directly
- Patch, repair, or migrate the database manually

**Why.** The binary manages schema versioning with `PRAGMA user_version`
and forward-only migrations. Any external DDL or DML breaks version
tracking, corrupts the migration chain, and produces errors the agent
cannot diagnose. The `.db` file is safe to read with any SQLite browser
for inspection — just never write to it.

For the complete JSON schema, error shapes, exit codes, read/write
command tables, and concurrency behavior, see the full
**[AI Agent Contract](#ai-agent-contract)** below.


## The World Engine

ttrpg-engine models your tabletop world as a **relational database** —
every tavern, blacksmith, quest giver, and goblin camp is a row you can
query, update, and connect. It was built for DMs who run long-form
campaigns with deep continuity, and for AI agents that need a canonical
source of truth about the game state.

**The world model.** You create a campaign. Inside it, you build
locations — towns, districts, dungeons. Locations nest into
sub-locations (`Ashwick > Blacksmith District > The Anvil & Flame`).
Each location holds houses (with residents and inventory), shops (with
opening hours and proprietors), wandering encounters, and story-driving
setpieces. NPCs, characters, and creatures all have a location — the CLI
tells you exactly who is where right now.

**The memory system.** A stateless AI agent only knows what you tell it.
ttrpg-engine solves this with three systems working together: a
**campaign journal** (timestamped session recaps the AI writes and reads
back), a **quest tracker** (step-by-step objectives with linked actors,
so the AI remembers what the party is supposed to be doing), and an
**in-game calendar** (day, time of day, season) so the AI can say "it's
autumn evening on day 42." One command — `campaign get-story-state` —
returns the complete context packet the AI needs to reconstruct the game
from a cold start.

**The combat engine.** Turn-based 5e-compatible combat lives inside the
database. `combat start`, `combat join`, `combat init` set up the
encounter. `combat attack` resolves attack rolls against AC, `combat
damage` applies damage with automatic resistance/vulnerability/immunity.
`combat save` handles saving throws with proficiency bonuses. `combat
next` advances turns, resets reactions each round. Death saves,
concentration, conditions, reactions, and ready actions are all tracked.
The combat snapshot appears in `get-story-state` — the AI always knows
who's up, what HP everyone has, and what conditions are active.

**The relationship graph.** NPCs have friendships, rivalries, and family
ties with each other (tracked with a decay-aware score). Characters have
personal faction standings, and campaigns track party-wide institutional
faction reputation — a faction can hate one PC but still mark the party
as hostile for the group's actions. Houses have residents. Characters
group into parties with shared treasury and location. Quests have quest
givers and participants. Every entity can be linked to every other
entity — the database IS the campaign bible.

**Built for AI pipelines.** Every command emits `--json` output for
piping into LLM agents, Discord bots, or automation scripts. The schema
is designed so an AI can call `get-story-state`, receive the full world
snapshot (locations tree with all entities present, active quests,
recent journal entries, faction standings, story log), and immediately
begin DMing with full context. No warm-up, no context-stuffing — one
query, everything it needs.

**Fast by design.** Single-row lookups are O(1) via indexed primary
keys. List commands scale with result size, not table size. Location
tree walks are O(depth) with depth bounded by campaign geography
(practically ≤10). Arena-based memory with zero heap allocations after
startup. Automatic SQLite schema migrations — drop the binary into a
campaign folder and run. No config files, no daemons, no network calls.
Just a 2.6 MB binary and a `.db` file you can commit to git alongside
your session notes.


## AI Agent Contract

This section is the canonical reference for AI agents, automation scripts, and LLM pipelines that call `ttrpg-engine` as a subprocess. Everything an agent needs to consume the engine reliably without reading the Odin source.

### Golden rule: `get-story-state` is your entry point

To reconstruct the full game world from a cold start, call:

```bash
ttrpg-engine campaign get-story-state <campaign_id> --json
```

This returns the complete context packet — one JSON object containing everything. **Never** scrape the world by calling multiple `list`/`get` commands; the result is a single snapshot that is internally consistent.

### `get-story-state` JSON schema

```jsonc
{
  "success": true,                     // always true on success (see error shapes below)

  // ── Campaign metadata ──
  "campaign": {
    "id": 1,                           // stable, never reused after DELETE
    "name": "Phandelver",
    "chapter": "",                     // current narrative chapter
    "session_num": 0,                  // increments via campaign next-session
    "dm_notes": "",                    // private DM scratchpad
    "in_game_day": 0,                  // total elapsed days (total_hours / 24)
    "in_game_time": "morning",         // morning | afternoon | evening | night
    "current_season": "spring"         // spring | summer | autumn | winter
  },

  // ── Session journal (last 10 entries, newest first) ──
  "journal": [{
    "id": 1,
    "session_num": 1,
    "entry_type": "narrative",         // narrative | combat | decision | npc_interaction | quest_update | dm_note
    "description": "...",
    "location_id": 1,                  // null if no location
    "created_at": "2026-06-13 17:40:03"
  }],

  // ── Active quests with objectives and linked actors ──
  "quests": [{
    "id": 1,
    "name": "Find Gundren Rockseeker",
    "description": "The dwarf patron is missing",
    "quest_giver_npc_id": 1,           // null if none
    "quest_giver_name": "Sildar Hallwinter",
    "status": "active",                // active | completed | failed | abandoned
    "reward_description": "500 gp",
    "chapter": "Chapter 1",
    "created_at": "2026-06-13 17:40:03",
    "objectives": [{
      "id": 1,
      "description": "Investigate the goblin ambush site",
      "status": "incomplete",          // incomplete | complete
      "sort_order": 1
    }],
    "actors": [{
      "actor_type": "character",       // character | npc
      "actor_id": 1,
      "actor_name": "Grimgar",
      "role": "leader"                 // leader | participant | target | observer
    }]
  }],

  // ── Location tree (recursive — sub_locations nest arbitrarily deep) ──
  "locations_tree": [{
    "id": 1,                           // global PK, never reused
    "name": "Phandalin",
    "description": "A frontier town",
    "chapter": "Chapter 1",
    "is_current": true,                // campaign's active location
    "parent_id": null,                 // null = root; integer = child of that location
    "restricted": 0,                   // 0 = open, 1 = restricted
    "restricted_until": "",
    "sub_locations": [{                // recursive — same shape, can nest deeper
      "id": 2,
      "name": "Cragmaw Hideout"
      // ... same fields, may have sub_locations of its own
    }],
    "houses": [],                      // {id, name, description, npc_id, scale, restricted, inventory}
    "shops": [],                       // {id, name, description, npc_id, scale, open_hours, restricted, inventory}
    "encounters": [],                  // {id, type, description, npc_id}
    "setpieces": [],                   // {id, name, description, chapter_event}
    "npcs_present": [{                 // NPCs whose location_id matches this location
      "id": 1,
      "name": "Sildar Hallwinter",
      "description": "Retired knight",
      "current_hp": 40,
      "max_hp": 40,
      "story_role": "",
      "daily_role": ""
    }],
    "characters_present": [{           // characters whose location_id matches
      "id": 1,
      "name": "Grimgar",
      "current_hp": 50,
      "max_hp": 50,
      "owner": "dm",
      "party": ""
    }],
    "creatures_present": []            // {id, name, current_hp, max_hp}
  }],

  // ── Parties with members and treasury ──
  "parties": [{
    "id": 1,
    "name": "The Black Company",
    "notes": "",
    "location_id": 1,
    "gold": 0, "silver": 0, "copper": 0,
    "members": [{
      "id": 1, "name": "Grimgar", "hp": 50, "max_hp": 50, "ac": 10
    }]
  }],

  // ── All factions in the campaign ──
  "factions": [{
    "id": 1,
    "name": "Harpers",
    "description": "Defenders of peace"
  }],

  // ── NPC ↔ NPC relationships ──
  "npc_relationships": [{
    "npc_id_1": 1,
    "npc_name_1": "Sildar Hallwinter",
    "npc_id_2": 2,
    "npc_name_2": "Goblin Scout",
    "friendship_level": 8,             // -10 (archnemesis) to +10 (close ally)
    "type": "ally",                    // spouse | family | friend | rival | enemy | acquaintance | ally
    "notes": "Old war buddies",
    "last_interaction_at": ""
  }],

  // ── Character faction standings ──
  "character_faction_standings": [{
    "character_id": 1,
    "character_name": "Grimgar",
    "faction_id": 1,
    "faction_name": "Harpers",
    "standing": 75,                    // decays toward 0 over ~14 days without interaction
    "notes": "Hero of the realm"
  }],

  // ── Party-wide faction standings (institutional reputation) ──
  "party_faction_standings": [{
    "campaign_id": 1,
    "faction_id": 2,
    "faction_name": "Redbrands",
    "standing": -30,
    "notes": "Enemies of the Redbrands"
  }],

  // ── Active combat encounter (null if no combat in progress) ──
  "combat": null | {
    "id": 1,
    "round": 2,
    "turn_index": 0,
    "status": "active",
    "location_id": 1,
    "participants": [{
      "actor_type": "character",
      "actor_id": 1,
      "actor_name": "Grimgar",
      "initiative_roll": 18,
      "initiative_mod": 3,
      "sort_order": 0,
      "is_active": true,
      "position": "melee",
      "current_hp": 45,
      "max_hp": 50,
      "ac": 15,
      "status_effects": "rage",
      "reaction_used": 0, "action_used": 1, "bonus_action_used": 0,
      "attacks_used": 1, "movement_used": 0,
      "readied_action": ""
    }]
  },

  // ── Story action log (chronological) ──
  "story_actions": [{
    "id": 1,
    "description": "Cleared goblin ambush on Triboar Trail",
    "location_id": 1,
    "location_name": "Phandalin",
    "standing_faction_id": 1,
    "standing_faction_name": "Harpers",
    "standing_impact": 10,
    "story_progression": 5,
    "status": "completed",
    "created_at": "2026-06-13 17:40:03",
    "actors": [{
      "type": "character",             // character | npc
      "id": 1
    }]
  }]
}
```

### Stable ID contract

- **Every entity has an integer primary key** (`id`). IDs are SQLite `INTEGER PRIMARY KEY` — never reused after `DELETE`.
- **Actor references are `(actor_type, actor_id)` tuples.** `actor_type` is one of `"character"`, `"npc"`, or `"creature"`. These strings are stable and will not change.
- **Location IDs are global**, not per-campaign. A location's `parent_id` points to another location by its global ID.
- **Faction IDs are global.** Characters, NPCs, wanted heat, and standings all reference factions by these IDs.
- **Campaign IDs scope** characters, NPCs, locations, quests, and journal entries. An entity's `campaign_id` links it to the campaign it belongs to.
- **Name fields are display-only.** Never key logic off `name` — always use `id`. Names can change, be duplicated, or be empty.

### Read vs. write commands

Agents must know which commands mutate canonical state. **Assume mutation unless listed below.**

**Read-only** (safe to call at any time, no side effects):

| Command | Notes |
|---|---|
| `character list`, `character get <id>` | |
| `npc list`, `npc get <id>` | |
| `creature list`, `creature get <id>` | |
| `companion list`, `companion get <id>` | |
| `item list` | |
| `inventory get <type> <id>` | |
| `spell list`, `spell list-character <id>` | |
| `feature list`, `feature list-character <id>` | |
| `faction list`, `faction get-standing`, `faction get-party-standing`, `faction effective-standing` | `get-standing` computes decay at query time but does not persist it |
| `campaign list`, `campaign get`, `campaign get-story-state`, `campaign get-time`, `campaign list-locations`, `campaign list-actions`, `campaign list-journal` | |
| `class-specialty list` | |
| `condition list` | |
| `quest list`, `quest get` | |
| `party list` | |
| `combat status` | |
| `wanted get`, `wanted list` | Decay computed at query time, not persisted |
| `shop browse`, `shop get` | |
| `house list`, `house list-residents` | |
| `encounter list`, `setpiece list` | |
| `can-enter` | |
| `location breadcrumb` | |

**Mutating** (changes database state — be intentional about when you call these):

| Command | What it changes |
|---|---|
| `character create/delete/damage/heal/set-*` | Character rows, inventory, conditions |
| `npc create/delete/damage/heal/set-*` | NPC rows, relationships, standings |
| `creature create/damage/heal/set-*` | Creature rows |
| `combat start/join/init/next/attack/strike/cast/damage/save/move/condition/death-save/react/ready/use-feature/end` | Combat state, HP, spell slots, conditions, resources |
| `rest short/long` | HP, hit dice, spell slots, resources, conditions, in-game time |
| `wanted crime/set/clear` | wanted_heat rows, crime_log rows |
| `campaign create/delete/set-*/add-*/next-session/advance-time/set-calendar` | Campaign state, locations, journal, quests, story actions, time |
| `faction create/set-standing/set-party-standing/join` | Faction rows, standing rows |
| `item upsert` | Item definitions |
| `inventory add/remove/equip/attune` | Inventory rows |
| `spell upsert/learn/forget/prepare` | Spell rows, character_spells |
| `quest add/add-objective/complete-objective/set-status/add-actor` | Quest state |
| `party create/add/remove/rest/move/treasury` | Party rows, character location/party fields |
| `shop stock/buy/sell/add-money/remove-money/haggle` | Shop inventory, character inventory/coins, haggle state |
| `condition add/remove` | conditions rows |
| `trade` | Character inventory and coins (two characters) |

### Exit codes and error shapes

Every command returns **0 on success, 1 on failure**. All output goes to stdout in JSON mode; errors go to stderr in text mode.

**Success shape** (varies by command, but always contains `"success":true`):
```json
{"success":true, "message": "...", ...command-specific fields...}
```

**Error shape** (uniform across all commands):
```json
{"success":false, "error": "<human-readable message>"}
```

Error messages are **human-readable, not machine-stable**. Key logic off `"success"` and exit code, never off error string content.

| Exit | JSON shape | When |
|---|---|---|
| 1 | `{"success":false,"error":"Usage: ..."}` | Missing or invalid arguments |
| 1 | `{"success":false,"error":"... not found"}` | Entity ID doesn't exist |
| 1 | `{"success":false,"error":"Failed to ..."}` | Database constraint, lock, or I/O error |

### Concurrency and locking

SQLite provides **serialized write access**. The binary opens a single connection to `ttrpg-engine.db` per invocation and closes it before exiting. Two concurrent processes:

- **Reads never block each other.** Multiple `get-story-state` or `list` calls can run in parallel.
- **Writes serialize via SQLite's internal lock.** If process A is mid-write, process B's write blocks until A commits. If the wait exceeds SQLite's busy timeout, B gets `{"success":false,"error":"Failed to ..."}` and exits 1.
- **There is no WAL mode.** The database uses SQLite's default rollback journal. Long-running reads can starve writers under extreme load.

**Recommendation for agents:** serialize all writes through a single
process or queue. Reads can fan out freely. If you need to batch
mutations, chain them in a single `ttrpg-engine` invocation by using
multiple subcommands (not yet supported — each invocation is one
command).

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

### Database portability

The campaign database is a single SQLite file (`ttrpg-engine.db`). This means:

- **Backup is `cp`.** Copy the file. That's it.
- **Clone a campaign** by copying the `.db` and renaming the campaign row.
- **Version control** the `.db` alongside your session notes. SQLite files diff reasonably with `sqldiff` or `git diff` after `sqlite3 .db .dump > schema.sql`.
- **Cross-platform.** The `.db` file is binary-identical across macOS and Linux. Copy it between machines freely.
- **Inspect with any SQLite tool.** `sqlite3`, DB Browser, Datasette — the schema is documented in [docs/schema.md](docs/schema.md). Reads are always safe; never issue DDL (see schema warning above).

### Code quality constraints

Every proc in the codebase has a hard cyclomatic complexity limit of 10
(McCabe's original threshold). Decision points counted: `if`, `else if`,
`for`, `case` (in `switch`), `&&`, `||`, `?:`. Procs that would exceed
the limit must be split — helper procs that exist only to keep a caller
under the limit are preferred over clever monolithic functions. This
keeps every unit of logic reviewable in a single screen of code.

---

## Table of Contents
1. [Agent Rules](#agent-rules-read-before-doing-anything-else)
2. [The World Engine](#the-world-engine)
3. [AI Agent Contract](#ai-agent-contract)
4. [Installation & Build](#installation--build)
5. [Database Schema](#database-schema)
6. [Global Output Flags](#global-output-flags)
7. [Dice Notation](#dice-notation)
8. [CLI Command Reference](#cli-command-reference)
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
   - [Shop & Economy](#16-shop--economy)
   - [Player Trading](#17-player-trading)
   - [Party Management](#18-party-management)
   - [Combat Engine](#19-combat-engine)
   - [Time, Calendar & Decay](#20-time-calendar--decay)
   - [Wanted & Crime System](#21-wanted--crime-system)
9. [Automatic Database Schema Migrations](#automatic-database-schema-migrations)
10. [Example Walkthrough Scenario](#example-walkthrough-scenario)

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

> **IMPORTANT — AI agents and automation tools:** All schema management
> is handled internally by the `ttrpg-engine` binary via automatic
> forward-only migrations keyed on `PRAGMA user_version`. **Do not
> manually modify the schema with `sqlite3` or any other external tool.**
> Adding, altering, or dropping tables/columns outside the binary's
> migration system will break the engine's version tracking and cause
> migration failures on next startup. The `.db` file is safe to read
> (SELECT) and safe to open in any SQLite browser for inspection — just
> never execute DDL (CREATE/ALTER/DROP) against it directly.

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

## Dice Notation

All damage, healing, attack rolls, saving throws, initiative, and hit dice values accept **dice specs** instead of plain integers. The engine rolls cryptographically secure random numbers internally.

**Format:** `[count]d<sides>[+modifier]` with optional suffixes:

| Example | Meaning |
|---|---|
| `d20` | Roll 1d20 |
| `2d6+3` | Roll 2d6, add 3 |
| `8d6` | Roll 8d6 (Fireball) |
| `4d8+5` | Roll 4d8, add 5 |
| `d20+5` | Roll 1d20, add 5 |
| `1d20+3` | Roll initiative (d20 + DEX mod) |
| `4d6k3` | Roll 4d6, keep highest 3 |
| `4d6d1` | Roll 4d6, drop lowest 1 |
| `3d6!` | Roll 3d6, exploding (reroll on max) |
| `2d20r1` | Roll 2d20, reroll 1s |
| `5d10t8` | Roll 5d10, count successes ≥ 8 |
| `4dF` | Roll 4 Fudge dice |

Every command that previously accepted a raw integer now accepts a dice spec. The engine parses the spec, rolls with cryptographically secure RNG, and uses the total.

### Where dice are rolled

**User provides the dice spec** (you control the expression):

| Command | What rolls |
|---|---|
| `character damage` | `dice_spec` — damage dealt |
| `character heal` | `dice_spec` — HP restored |
| `character set-temp-hp` | `dice_spec` — temporary HP granted |
| `npc damage`, `npc heal` | `dice_spec` — damage or healing |
| `creature damage`, `creature heal` | `dice_spec` — damage or healing |
| `companion damage`, `companion heal` | `dice_spec` — damage or healing |
| `combat attack` | `dice_spec` — d20 attack roll |
| `combat strike` | Weapon damage dice auto-looked up from inventory; d20 attack roll |
| `combat cast` | `dice_spec` — spell damage/healing; d20 attack roll or target save |
| `combat damage` | `dice_spec` — damage dealt |
| `combat save` | `dice_spec` — d20 saving throw |
| `combat join` | `dice_spec` — initiative roll |
| `combat death-save` | `dice_spec` — death saving throw |
| `combat check` | d20 auto-rolled internally |
| `rest short` | Hit dice auto-rolled internally (largest class hit die × count + CON per die) |
| `rest long` | No rolls — full heal |

**Engine rolls automatically** (no dice spec argument):

| Command | What happens |
|---|---|
| `combat check` | Rolls d20 + ability mod + proficiency internally |
| `combat strike` | After the d20 attack roll, damage dice auto-looked up from equipped weapon |
| `combat cast` | Auto-rolls concentration save (d20 + CON + prof vs DC) when caster takes damage |
| `combat damage` | Auto-rolls concentration save for concentrating targets |
| `combat use-feature Second Wind` | Auto-rolls 1d10 + character level healing |
| `rest short` | Auto-rolls hit dice (largest class die × count) + CON per die |
| `shop haggle` | Auto-rolls d20 + CHA (Persuasion) vs scaling DC |

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
  ./ttrpg-engine character damage <id> <dice_spec> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ```
  *`dice_spec` is a dice expression like `2d6+3` or `8d6`. The
  `attack_or_save` argument accepts dice specs (e.g. `d20+5`) for
  attack rolls, or save ability names (str/dex/con/int/wis/cha) for
  saving throws. Handles evasion feats, races, resistances,
  vulnerabilities, immunities, and saving throw modifier calculations
  automatically.*
- **Apply Healing**:
  ```bash
  ./ttrpg-engine character heal <id> <dice_spec> [source]
  ```
  *`dice_spec` is a dice expression like `3d8+5`. Heals up to max HP.*
- **Set Temporary Hit Points**:
  ```bash
  ./ttrpg-engine character set-temp-hp <id> <dice_spec>
  ```
  *`dice_spec` is a dice expression like `2d6+3`.*
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
Set 5e-compatible combat math: proficiency bonus, initiative, spell save DC, spell attack bonus, passive perception, languages, max hit dice, concentration, and the combat-engaged flag (consumed by an external combat engine).

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
Track 5e conditions with source/duration/save metadata, and PHB personality hooks. Conditions are a top-level command (apply to character, NPC, or creature polymorphically).

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
  *Rolls `hit_dice_count` hit dice (largest available from character class) with CON modifier per die. Resets short-rest resources, decrements available short rests, clears rest-duration conditions.*
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
  ./ttrpg-engine companion damage <id> <dice_spec> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./ttrpg-engine companion heal <id> <dice_spec>
  ```
  *`dice_spec` is a dice expression like `2d6+3`. Supports resistances, vulnerabilities, and immunities.*

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
- **Damage/Heal NPC**:
  ```bash
  ./ttrpg-engine npc damage <id> <dice_spec> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./ttrpg-engine npc heal <id> <dice_spec>
  ```
  *`dice_spec` is a dice expression like `2d6+3`. Supports resistances, vulnerabilities, and immunities.*
- **Manage NPC Tool Proficiencies** (e.g. `smith's tools`, `herbalism kit`):
  ```bash
  ./ttrpg-engine npc add-tool-prof <npc_id> <tool_name>
  ./ttrpg-engine npc remove-tool-prof <npc_id> <tool_name>
  ```
- **Character↔NPC Standing**:
  ```bash
  ./ttrpg-engine npc set-char-standing <npc_id> <character_id> <standing> [notes]
  ./ttrpg-engine npc get-char-standing <character_id> [npc_id]
  ```
  *Track individual reputation between a player character and an NPC.
  Standing ranges from -100 (hated) to +100 (trusted). Affects haggle
  DCs, shop prices, and access checks. Decays over time (14-day
  half-life) — reset by any interaction or by calling
  `set-char-standing`. If `npc_id` is omitted from `get-char-standing`,
  returns all standings for that character.*


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
  ./ttrpg-engine creature damage <id> <dice_spec> [damage_type] [attack_or_save] [save_dc] [d20_roll]
  ./ttrpg-engine creature heal <id> <dice_spec>
  ```
  *`dice_spec` is a dice expression like `2d6+3`. Supports resistances, vulnerabilities, and immunities.*
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
  *Example: `ttrpg-engine campaign set-time 1 42 evening autumn` — it is day 42, evening, in autumn. This is the legacy command; prefer `set-calendar` for full date control.*
- **Advance Time**:
  ```bash
  ./ttrpg-engine campaign advance-time <campaign_id> <hours>
  ```
  *Tick the in-game clock forward by N hours. Auto-expires hour-based conditions. Recomputes all derived calendar fields.*
- **Set Calendar (DM Override)**:
  ```bash
  ./ttrpg-engine campaign set-calendar <campaign_id> <year> <month> <day> <hour>
  ```
  *Absolute date/time override — supports rewind (shows warning) and fast-forward.*
- **Get Current Time**:
  ```bash
  ./ttrpg-engine campaign get-time <campaign_id> [--json]
  ```
  *Display full calendar state: year, month, day, hour, time of day, season, total day count.*
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
  *Returns the full context packet: campaign metadata with in-game time,
  DM notes, last 10 journal entries, active quests with objectives and
  actors, location tree with all entities present (sub-locations, houses,
  shops, encounters, setpieces, NPCs, characters, creatures), factions,
  NPC relationships, character faction standings, party faction
  standings, parties with members and treasury, active combat encounter
  with turn order/HP/conditions, and chronological story log. This is
  the single command an AI agent calls to reconstruct the entire game
  state.*

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
  *Displays both raw standing and decay-adjusted value. Standing decays toward zero over time (14-day half-life) — every `set-standing` call resets the decay timer.*
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


### 16. Shop & Economy

Browse shop inventory, stock items with custom prices, buy and sell with full currency exchange. Shops have their own treasuries — they gain coins when characters buy and lose coins when they buy items back. Linked to an owner NPC via `npc_id`.

**Shop scale** (`low`, `mid`, `high`, `luxury`) controls three mechanics automatically:

| Scale | Auto-treasury | Buyback rate | Max item value |
|---|---|---|---|
| `low` | 50 gp | 30% | 50 gp |
| `mid` | 500 gp | 50% | 500 gp |
| `high` | 2,000 gp | 60% | 5,000 gp |
| `luxury` | 10,000 gp | 70% | no limit |

*The DM can override the auto-treasury with `shop add-money` / `shop remove-money` at any time.*

- **Browse Shop Inventory**:
  ```bash
  ./ttrpg-engine shop browse <shop_id> [--json]
  ```
  *Lists all items in stock with quantities and per-unit prices. Price shows the shop’s custom price if set, otherwise the item’s base `value_gp`.*

- **Stock Items (DM)**:
  ```bash
  ./ttrpg-engine shop stock <shop_id> <item_id> <quantity> [price_gp]
  ```
  *Add or replace item stock in a shop. If `price_gp` is omitted or 0, the item’s base `value_gp` is used.*

- **Purchase from Shop**:
  ```bash
  ./ttrpg-engine shop buy <shop_id> <char_id> <item_id> <quantity> [--json]
  ```
  *Character buys items. Auto-deducts coins from character (pp→gp→ep→sp→cp, largest first), credits shop treasury. Enforces the shop's max item value by scale. Validates sufficient stock and funds. Returns exit code 1 on failure.*

- **Sell to Shop**:
  ```bash
  ./ttrpg-engine shop sell <shop_id> <char_id> <item_id> <quantity> [--json]
  ```
  *Character sells items at the shop's scale-based buyback rate (30%–70% of base `value_gp`). Shop pays from its treasury — if the shop can’t afford the buyback, the sale is rejected with exit code 1. Removed from character inventory, restocked in shop.*

- **Manage Shop Treasury (DM)**:
  ```bash
  ./ttrpg-engine shop add-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]
  ./ttrpg-engine shop remove-money <shop_id> <gold> <silver> <copper> [platinum] [electrum]
  ```
  *Seed or drain a shop’s operating funds. Multi-denomination — the engine converts and distributes across coin types automatically.*

- **View Shop Details**:
  ```bash
  ./ttrpg-engine shop get <shop_id> [--json]
  ```
  *Displays shop name, location, scale, open hours, proprietor NPC, and current treasury breakdown.*

- **Haggle for a Discount**:
  ```bash
  ./ttrpg-engine shop haggle <shop_id> <char_id> <item_id> <quantity> <discount_pct> [--json]
  ```
  *Attempt a Persuasion (CHA) check to negotiate a discount with the
  shop owner. **3 attempts per shop per in-game day.** DC escalates
  with each failure, and a critical fail (miss by 10+) damages
  reputation with the NPC. On success, the item is purchased
  automatically at the discounted price — coins are deducted from the
  character and credited to the shop treasury.*

  | Mechanic | Detail |
  |---|---|
  | DC formula | `10 + discount%/5 + fail_streak×2 − standing/20` |
  | Success | Pays `price × (100 − discount%) / 100` |
  | Failure | `fail_streak++`, 1 attempt burned, DC rises |
  | Critical fail (by ≥ 10) | Standing with NPC reduced by 1d4 |
  | 3 failures | NPC refuses further haggling for the day |
  | Standing bonus | Every +20 standing reduces DC by 1 |

  *Example: `ttrpg-engine shop haggle 1 3 2 1 20` — character #3 tries for 20% off item #2 at shop #1.*

### 17. Player Trading

Atomic item-and-coin transfers between two player characters. Both participants must exist and the sender must own the item.

- **Trade Between Characters**:
  ```bash
  ./ttrpg-engine trade <from_char_id> <to_char_id> <item_id> <quantity> [gp] [sp] [cp] [pp] [ep]
  ```
  *Transfers the item from sender to recipient. Optional coin amounts (any combination of gp/sp/cp/pp/ep) are deducted from sender and credited to recipient in the same atomic operation.*

  *Example: `ttrpg-engine trade 1 2 3 1 10 0 0` — Aria sends item #3 plus 10gp to Bran.*

---
---

### 18. Party Management

Group characters into adventuring parties for collective movement, resting, and treasury management. Parties appear in `get-story-state`.

- **Create Party**:
  ```bash
  ./ttrpg-engine party create <campaign_id> <name> [notes]
  ```
- **Add Character to Party**:
  ```bash
  ./ttrpg-engine party add <party_id> <character_id>
  ```
  *Also updates the character's party text field for backward compatibility.*
- **Remove Character from Party**:
  ```bash
  ./ttrpg-engine party remove <character_id>
  ```
- **List Parties and Members**:
  ```bash
  ./ttrpg-engine party list <campaign_id> [--json]
  ```
- **Rest Entire Party**:
  ```bash
  ./ttrpg-engine party rest <party_id> <short|long> [hit_dice_count]
  ```
- **Move Entire Party**:
  ```bash
  ./ttrpg-engine party move <party_id> <location_id>
  ```
  *Moves all members and the party record to the new location at once.*
- **Manage Party Treasury**:
  ```bash
  ./ttrpg-engine party treasury <party_id> <add|remove|set> <gold> <silver> <copper>
  ```

---

### 19. Combat Engine

Full 5e-compatible turn-based combat with action economy enforcement, spell slot tracking, weapon auto-lookup, skill checks, concentration auto-rolls, and feature resource consumption. All dice values are dice specs — the engine rolls cryptographically secure random numbers internally.

#### Encounter Lifecycle

- **Start Combat**:
  ```bash
  ./ttrpg-engine combat start <campaign_id> <location_id>
  ```
- **Add Participants**:
  ```bash
  ./ttrpg-engine combat join <encounter_id> <char|npc|creature> <id> <dice_spec> [initiative_mod] [position]
  ./ttrpg-engine combat join-all <encounter_id>
  ```
  *`dice_spec` is an initiative expression like `1d20+3` or `d20`.*
- **Lock Turn Order**:
  ```bash
  ./ttrpg-engine combat init <encounter_id>
  ```
  *Sorts participants by initiative roll (descending), then initiative mod (descending). Sets round 1, turn 0.*
- **Advance Turn**:
  ```bash
  ./ttrpg-engine combat next <encounter_id>
  ```
  *Advances to next turn. Resets action_used, bonus_action_used, attacks_used, and movement_used for the incoming actor. Resets reactions for all participants on round wrap. Auto-reports who's up next.*
- **View Combat Status**:
  ```bash
  ./ttrpg-engine combat status <encounter_id> [--json]
  ```
  *Full turn order with HP/AC/position, action economy flags ([action] [BA] [react] [readied]), and current-actor marker.*
- **End Combat**:
  ```bash
  ./ttrpg-engine combat end <encounter_id>
  ```
  *Archives encounter, clears combat flags on all character participants.*

#### Actions (enforce action economy)

The engine enforces 5e action economy: one action (with Extra Attack / Multiattack), one bonus action, one reaction per round. The `attacks_used` counter is compared against `multiattack_count` (creatures/NPCs, default 1; characters default 1 — increase via `combat use-feature` for Extra Attack).

- **Attack (roll vs AC)**:
  ```bash
  ./ttrpg-engine combat attack <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> <dice_spec> [ability] [adv|disadv]
  ```
  *`dice_spec` is a d20 expression like `d20` or `d20+5`. Auto-computes attack modifier (proficiency + ability mod + attack_bonus for NPCs/creatures). Adds cover bonus from target position. Marks action_used, increments attacks_used. Rejects if no actions remain.*

- **Strike (attack + damage, weapon auto-lookup)**:
  ```bash
  ./ttrpg-engine combat strike <encounter_id> <attacker_type> <attacker_id> <target_type> <target_id> [ability] [bonus|ba]
  ```
  *One-command weapon attack. Auto-looks up the actor's equipped weapon
  from inventory: reads damage dice, damage type, magic bonus. Determines
  ability (STR for melee, DEX for ranged/finesse). Rolls d20 + mod +
  proficiency + magic vs AC. On hit: rolls weapon damage + ability mod +
  magic bonus, applies resistance/vulnerability/immunity, drains temp HP,
  auto-rolls concentration save, marks death at 0 HP. Falls back to
  unarmed strike (1 + STR bludgeoning) if no weapon equipped. Use
  `bonus` or `ba` as 7th argument for bonus-action attacks (e.g.
  off-hand).*

- **Cast a Spell**:
  ```bash
  ./ttrpg-engine combat cast <encounter_id> <caster_type> <caster_id> <spell_name> <slot_level> <target_type> <target_id> [save_ability] [dice_spec] [dc_override]
  ```
  *For characters: verifies spell is known and prepared, checks spell
  slots, consumes a slot. For all casters: uses character's
  spell_attack_bonus / spell_save_dc, or computes DC (8 + prof + best
  mental mod) for NPCs/creatures. If `save_ability` given
  (str/dex/con/int/wis/cha): target rolls save vs caster's DC.
  Otherwise: rolls spell attack vs target AC. Auto-tracks concentration
  if the spell's duration contains "Concentration".*

- **Apply Damage (manual)**:
  ```bash
  ./ttrpg-engine combat damage <encounter_id> <target_type> <target_id> <dice_spec> <type> [source]
  ```
  *`dice_spec` is a damage expression like `2d6+3` or `8d6`. Auto-applies resistance (half), vulnerability (double), immunity (zero). Depletes temp HP first. Auto-rolls concentration save if target is concentrating. Handles death at 0 HP (unconscious for characters, killed for NPCs/creatures).*

- **Use a Feature / Class Ability**:
  ```bash
  ./ttrpg-engine combat use-feature <encounter_id> <actor_type> <actor_id> <feature_name>
  ```
  *Activates a class feature or monster ability. Auto-matches feature to
  resource pool by naming convention (Rage → "Rage", Ki/Flurry of Blows
  → "Ki Points", Action Surge → "Action Surge", Second Wind →
  "Second Wind", Channel Divinity → "Channel Divinity", Bardic
  Inspiration, Sorcery Points, Wild Shape, etc.). Decrements resource
  by 1. Applies mechanical effects for known features:*
  - **Rage**: adds "rage" to status_effects (B/P/S resistance, +2 STR damage)
  - **Action Surge**: resets action_used and attacks_used (grants an extra action)
  - **Second Wind**: auto-heals 1d10 + character level
  - **Ki / Flurry / Patient Defense / Step of the Wind**: reports ki spent
  - **Divine Smite**: notes that a spell slot must be consumed via `combat cast`

- **Skill Check**:
  ```bash
  ./ttrpg-engine combat check <encounter_id> <actor_type> <actor_id> <skill_name> [dc] [contest_type] [contest_id]
  ```
  *Rolls d20 + ability mod + proficiency bonus × proficiency_level. Auto-maps skill to ability (Athletics→STR, Stealth→DEX, Perception→WIS, etc.). Supports both DC checks and contested rolls (grapple/shove — pass target actor as contest target).*

- **Saving Throw**:
  ```bash
  ./ttrpg-engine combat save <encounter_id> <actor_type> <actor_id> <ability> <dice_spec> [dc] [adv|disadv]
  ```
  *Rolls d20 + ability mod + save proficiency (characters only). Compares against DC.*

- **Move/Position**:
  ```bash
  ./ttrpg-engine combat move <encounter_id> <actor_type> <actor_id> <position>
  ```
  *Positions: melee, ranged, cover, hidden, fleeing. Warns about opportunity attacks when leaving melee.*

- **Death Saving Throw**:
  ```bash
  ./ttrpg-engine combat death-save <character_id> <dice_spec>
  ```
  *`dice_spec` is typically `d20`. Nat 20: regains 1 HP. Nat 1: 2 failures. 3 successes: stabilized. 3 failures: dead. Refuses if character HP > 0.*

#### Reactions & Other

- **Use Reaction** (1/round enforced):
  ```bash
  ./ttrpg-engine combat react <encounter_id> <actor_type> <actor_id> <reaction_type> [target_type] [target_id]
  ```
- **Ready Action** (marks action_used, stores trigger):
  ```bash
  ./ttrpg-engine combat ready <encounter_id> <actor_type> <actor_id> "<action>" <trigger>
  ```
- **Apply Condition**:
  ```bash
  ./ttrpg-engine combat condition <encounter_id> <target_type> <target_id> <name> [duration_rounds] [save_dc] [save_ability]
  ```

#### Action Economy Summary

| Economy | Tracked? | Enforced? | Reset |
|---|---|---|---|
| Action | `action_used` flag | Yes — attack/strike/cast reject if used (unless multiattack) | `combat next` |
| Extra Attack / Multiattack | `attacks_used` counter vs `multiattack_count` | Yes — rejects when attacks_used ≥ multiattack_count | `combat next` |
| Bonus Action | `bonus_action_used` flag | Yes — "bonus"/"ba" arg on strike, enforced | `combat next` |
| Reaction | `reaction_used` flag | Yes — react rejects if already used | Round wrap in `combat next` |
| Movement | `movement_used` (integer, feet) | Tracked, not enforced | `combat next` |
| Concentration | Auto-rolled on any damage > 0 | d20 + CON mod + prof vs DC = max(10, dmg/2) | Cleared on fail |

---

### 20. Time, Calendar & Decay

A unified time progression system with a 360-day Forgotten Realms calendar. All reputation and standing values decay over time toward zero (14-day half-life), encouraging characters to maintain relationships.

**Calendar model:** `total_elapsed_hours` is the single source of truth — 7 fields derive from it:

| Field | Derivation |
|---|---|
| `in_game_hour` | `total_hours % 24` |
| `in_game_day_of_month` | `(total_hours / 24) % 30 + 1` |
| `in_game_month` | `(total_hours / 720) % 12 + 1` |
| `in_game_year` | `1492 + total_hours / 8640` |
| `in_game_day` | `total_hours / 24` |
| `in_game_time` | hour 6-11=morning, 12-17=afternoon, 18-21=evening, else=night |
| `current_season` | month 1-3=winter, 4-6=spring, 7-9=summer, 10-12=autumn |

- **Advance Time**:
  ```bash
  ./ttrpg-engine campaign advance-time <campaign_id> <hours>
  ```
  *Ticks the in-game clock forward by N hours. Auto-expires time-based conditions (duration_type='hours'). After advancing, all derived calendar fields are recomputed.*

- **Set Calendar (DM Override)**:
  ```bash
  ./ttrpg-engine campaign set-calendar <campaign_id> <year> <month> <day> <hour>
  ```
  *Sets the in-game date/time to an absolute value. Supports rewinding (shows a warning) and fast-forwarding. Useful for starting a new chapter, time-skips, or correcting mistakes.*

- **View Current Time**:
  ```bash
  ./ttrpg-engine campaign get-time <campaign_id> [--json]
  ```
  *Displays the full calendar state: year, month, day, hour, time of day, season, total day count, and total elapsed hours.*

- **Rest Auto-Advance**:
  *Short rests automatically advance the clock by 1 hour. Long rests advance by 8 hours. No separate command needed — the rest commands handle it.*

**Unified decay** applies to all reputation systems:

| System | Decay trigger | Display |
|---|---|---|
| Faction standings | `faction set-standing` touches timestamp | `faction get-standing` shows raw + decayed |
| Character↔NPC standings | `npc set-char-standing` and `shop haggle` touch timestamp | Decay computed at query time |
| NPC↔NPC relationships | `npc set-relationship` touches timestamp | `can-enter` access checks use decayed score |
| Wanted heat | `wanted crime` and `wanted set` touch timestamp | `wanted get` and `wanted list` show decayed heat |

**Decay formula:** `standing × e^(-0.05 × days_elapsed)` — half-life of ~14 days. After 30 days without interaction, standing drops to ~22% of its original value.

**Wanted heat decay** uses the same exponential curve, calculated per-hour: `heat × e^(-0.05/24 × hours_elapsed)`. The finer granularity prevents edge cases on day 0 (the first day of a campaign).


### 21. Wanted & Crime System

Track criminal heat per character/NPC, per faction (jurisdiction), per location. Wanted levels decay over time, inherit through the location hierarchy, and map to 0–5 narrative tiers the AI DM uses to describe guard behavior.

**Design.** The system answers one question: "Who is wanted, where, by whom, and for what?" It was built as a world-consistency harness — the AI DM queries it to ground its narrative in canonical state rather than hallucinating jurisdictional boundaries across sessions.

#### Core concepts

| Concept | Description |
|---|---|
| **Heat points** | Internal simulation value (0–100+). Crimes add heat; time decays it. |
| **Tier** | AI-facing narrative level (0–5), derived from heat. Each tier has a label and guard behavior. |
| **Jurisdiction** | A faction that enforces law (e.g. "Waterdeep Watch", "Thieves' Guild"). Heat is per-faction — you can be Hunted by the Watch but Protected by the Guild. |
| **Location** | Where the crime happened. Wanted levels propagate up the location tree — being wanted in a child location inherits from the parent unless explicitly overridden. |
| **Crime log** | Immutable audit trail of every crime: who did what, where, when, and how much heat it added. |

#### Tier mapping

| Heat | Tier | Label | Guard behavior |
|---|---|---|---|
| 0 | 0 | Clean | Ignore |
| 1–15 | 1 | Suspicious | Question |
| 16–35 | 2 | Wanted | Detain |
| 36–60 | 3 | Hunted | Attack on sight |
| 61–85 | 4 | Infamous | Mobilize guards |
| 86+ | 5 | Legendary Fugitive | Scry & strike |

#### CLI reference

- **Commit a Crime** (logs the crime AND auto-applies heat):
  ```bash
  ./ttrpg-engine wanted crime <char|npc> <actor_id> <faction_id> <location_id> <severity> <description>
  ```
  *Adds severity heat points to the actor's wanted level for that faction+location. Resets the decay timer. Logs the crime to the crime_log table. Severity is in heat points — typical values: petty theft 5, assault 15, murder 40, arson 25.*

- **Get Wanted Status** (with decay and location inheritance):
  ```bash
  ./ttrpg-engine wanted get <char|npc> <actor_id> <faction_id> [location_id] [--json]
  ```
  *If `location_id` is given: walks the location parent chain to find the effective wanted level. Reports raw heat, decayed heat, tier, label, guard behavior, and whether the result was inherited from a parent location. If `location_id` is omitted: lists wanted entries across all locations for that actor+faction pair.*

- **Set Heat Directly** (DM override):
  ```bash
  ./ttrpg-engine wanted set <char|npc> <actor_id> <faction_id> <location_id> <heat>
  ```
  *Overrides heat points to an exact value. Resets the decay timer to the current in-game hour.*

- **Clear Wanted Level**:
  ```bash
  ./ttrpg-engine wanted clear <char|npc> <actor_id> <faction_id> <location_id>
  ```
  *Removes the wanted record entirely — the actor is clean at this location for this faction.*

- **List Wanted Entities at a Location**:
  ```bash
  ./ttrpg-engine wanted list <faction_id> <location_id> [--json]
  ```
  *Shows every character and NPC with a wanted record at this location for this faction, including names, decayed heat, tiers, and guard behaviors.*

#### Location inheritance

When you query `wanted get` for a specific location, the engine walks the `parent_id` chain upward:

1. Check for an explicit `wanted_heat` row at the requested location
2. If none found, check the parent location
3. Continue until a row is found or the root is reached

An **explicit row at a child location takes precedence** over the parent — this is the opt-out mechanism. A character wanted at Heat 3 in Waterdeep can be explicitly set to Heat 0 (Clean) in the Dock Ward (e.g., "Thieves' Guild protection"), and `wanted get` for the Dock Ward will return Clean.

#### Decay

Wanted heat decays exponentially with the same ~14-day half-life as
faction standings. The decay is computed **at query time** from the
`last_decay_hour` timestamp (stored as `total_elapsed_hours`) and never
persisted back — the raw heat remains unchanged, only the displayed
value decays. Setting heat via `crime` or `set` resets the decay timer.

Actors without a campaign assignment can still accumulate wanted heat (decay timer is 0, meaning "never decays"). Assign the actor to a campaign and advance time to enable decay.

#### Example

```bash
# Create a jurisdiction and locations
./ttrpg-engine faction create "Waterdeep Watch" "City guards of Waterdeep"
./ttrpg-engine campaign add-location 1 "Waterdeep" "The City of Splendors"
./ttrpg-engine campaign add-location 1 "Dock Ward" "The rough docks district"
./ttrpg-engine location set-parent 2 1   # Dock Ward is in Waterdeep

# Grimgar murders a noble in Waterdeep
./ttrpg-engine wanted crime char 1 1 1 40 "Murdered a noble in Castle Ward"
# Output: Heat: 40 (+40) [Tier 3: Hunted]  Location: #1 | Faction: #1

# Check status in the Dock Ward — inherits from Waterdeep
./ttrpg-engine wanted get char 1 1 2
# Output: Effective heat: 40 (raw: 40) [Tier 3: Hunted]
#         Inherited from location #1 (queried #2)
#         Guard behavior: Attack on sight

# Grimgar commits another crime — heat accumulates
./ttrpg-engine wanted crime char 1 1 1 15 "Assaulted a guard"
# Output: Heat: 55 (+15) [Tier 3: Hunted]

# 30 days pass — heat decays
./ttrpg-engine campaign advance-time 1 720
./ttrpg-engine wanted get char 1 1 1
# Output: Heat: 12 (raw: 55) [Tier 1: Suspicious]

# List everyone wanted by the Watch in Waterdeep
./ttrpg-engine wanted list 1 1
```


## Automatic Database Schema Migrations
The tool handles schema updates automatically using SQLite's internal versioning integer `PRAGMA user_version`. 

When the CLI starts up, it reads the current schema version of
`ttrpg-engine.db`. If the database is new or has an older version, the
tool executes all missing forward-only SQL migration blocks sequentially
and stamps the new version number onto the file. This requires zero
setup or manual commands from the Dungeon Master, keeping campaign data
intact.

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
./ttrpg-engine character set-temp-hp 1 2d6+3
# Output: Character HP now: 60/60 (Temp HP: 11) (rolled 2d6+3)

./ttrpg-engine character damage 1 2d6+3 # Grog takes 2d6+3 slashing damage
# Output: Character HP now: 55/60 (Temp HP: 0) (Took 10 slashing damage)

./ttrpg-engine character damage 1 1d8+2 # Grog takes another 1d8+2 damage
# Output: Character HP now: 48/60 (Temp HP: 0) (Took 7 damage)

# 6b. Short Rest (spend hit dice to heal after taking damage)
./ttrpg-engine rest short 1 2
# Output: Short rest: character 1 healed 13 HP, spent 2 hit dice.

# 6c. Combat Encounter — full turn with the new engine
# Setup: create goblin scout, equip Grog with a greataxe
./ttrpg-engine creature create "Goblin Scout" 7 7 14 10 12 12 8 10 1 1 1 1
./ttrpg-engine item upsert "Greataxe" "A heavy axe" weapon 1d12 slashing 0 "heavy,two-handed" 7 30
./ttrpg-engine inventory add character 1 3 1       # give Grog the greataxe
./ttrpg-engine inventory equip character 1 3 1      # equip it
./ttrpg-engine combat start 1 1
./ttrpg-engine combat join 1 character 1 1d20+3      # Grog rolls initiative (d20 + DEX + Alert)
./ttrpg-engine combat join 1 creature 1 1d20         # Goblin rolls flat initiative
./ttrpg-engine combat init 1

# Round 1, Turn 1: Grog rages and attacks
./ttrpg-engine combat use-feature 1 character 1 Rage
# Output: Grog uses Rage (Rage: 3 → 2) — B/P/S resistance active, +2 damage
./ttrpg-engine combat strike 1 character 1 creature 1
# Output: Grog hits Goblin Scout: 14 + 5 = 19 vs AC 14 → HIT | 1d12+3 slashing → 9/14 HP

# Round 1, Turn 2: Goblin attacks Grog
./ttrpg-engine combat next 1
# Output: Round 1, turn 2: Goblin Scout (creature 1)
./ttrpg-engine combat attack 1 creature 1 character 1 d20+2 dex
# Output: Goblin Scout attacks Grog: 7 + 2 = 9 vs AC 15 → MISS

# Round 2, Turn 1: Grog's second rage-powered attack
./ttrpg-engine combat next 1
./ttrpg-engine combat strike 1 character 1 creature 1
# Output: Grog hits Goblin Scout: 18 + 5 = 23 vs AC 14 → HIT | 1d12+3 slashing → 0/14 HP | Killed

# Grog tries a skill check to intimidate the remaining goblins
./ttrpg-engine combat check 1 character 1 intimidation 12
# Output: Grog intimidation check (cha): 15 + 2 + 0 = 17 vs DC 12 → PASS

./ttrpg-engine combat end 1

# 7. Log Story Actions and Link Actors
./ttrpg-engine faction create "Harpers" "Defenders of peace."
./ttrpg-engine faction join char 1 1
./ttrpg-engine campaign add-action 1 "Defeated goblin scouts near Phandalin" 1 1 5 3 "completed"
./ttrpg-engine campaign link-actor 1 char 1

# 8. View Complete Campaign Status
./ttrpg-engine campaign get-story-state 1
```
