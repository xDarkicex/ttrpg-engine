# Campaign AI Continuity — Design Notes

Status: **DRAFT, pending review**.

## Problem

The AI DM agent is stateless. Every interaction starts from a cold load
of the campaign state. Unlike a human DM who remembers last session's
cliffhanger, the AI has to reconstruct "where we are and what happened"
from the data store each time.

The campaign system must capture enough context for the AI to:

1. Know what happened last session (recap)
2. Know the current state of the world (who is where, what's active)
3. Know what decisions players made (branching narrative)
4. Know what's next (active quests, unresolved threads)
5. Know who the NPCs are and what they want (motivations)

## Current state (v17)

| Feature | Status | Notes |
|---------|--------|-------|
| Campaign metadata | ✓ | name, chapter, session_num |
| Locations with sub-locations | ✓ | parent_id recursive |
| Houses, shops, encounters, setpieces | ✓ | v15 |
| Story actions log | ✓ | story_actions + story_action_actors |
| NPCs linked to locations | ✓ | npc.location_id |
| Characters linked to locations | ✓ | character.location_id |
| Creatures linked to locations | ✓ | creature.location_id |
| Relationships | ✓ | npc_relationships with type |
| Conditions on entities | ✓ | conditions table |

## What's missing for AI agent context

### 1. Session recap / campaign journal

The `story_actions` table is a flat log of plot events. It doesn't
capture the "last time on D&D" recap the AI needs to start a session.

**Proposal**: Add `campaign_journal` table. Each entry is a timestamped
note with a type, description, and actor references. The AI loads
the last N entries for context.

```sql
CREATE TABLE campaign_journal (
    id INTEGER PRIMARY KEY,
    campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
    session_num INTEGER DEFAULT 0,
    entry_type TEXT DEFAULT 'narrative',  -- narrative, combat, decision, npc_interaction, quest_update, dm_note
    description TEXT NOT NULL,
    location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

When the AI loads the campaign, it gets the last ~10 journal entries
sorted by id DESC. The `description` field is free text — the AI writes
the recap itself. No fancy NLP needed.

For a more structured approach, `story_actions` already exists and can
be the canonical log. But `campaign_journal` fills the gap for
"flavor text" entries that don't fit the action model (e.g. "The party
discussed their next move over ale at the Ironjaw Bakery").

### 2. World state snapshot — who is where right now

The AI needs a "world at a glance" view showing where each entity is.
Currently `get-story-state` only lists locations by campaign; it
doesn't show which NPCs/characters/creatures are at each location.

**Proposal**: Enhance `get-story-state` to include:
- For each location: sub-locations (via parent_id), houses, shops,
  encounters, setpieces
- For each location: which NPCs, characters, creatures are there
- A "world summary" section: all entities grouped by location

This is a display/query change, not a schema change. The data already
exists in the location_id columns.

### 3. Quest tracking

No quest system exists. The AI needs to track:
- What quests are active
- Who gave the quest (NPC)
- What the objective is
- What the reward is
- Status (active, completed, failed)
- What chapter the quest belongs to

**Proposal**: Add `quests` table:

```sql
CREATE TABLE quests (
    id INTEGER PRIMARY KEY,
    campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    quest_giver_npc_id INTEGER REFERENCES npcs(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'active',  -- active, completed, failed, abandoned
    reward_description TEXT DEFAULT '',
    chapter TEXT DEFAULT '',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

Plus a `quest_objectives` table for step-by-step tracking:

```sql
CREATE TABLE quest_objectives (
    id INTEGER PRIMARY KEY,
    quest_id INTEGER REFERENCES quests(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    status TEXT DEFAULT 'incomplete',  -- incomplete, complete
    sort_order INTEGER DEFAULT 0
);
```

And `quest_actors` to link characters/NPCs to quests:

```sql
CREATE TABLE quest_actors (
    id INTEGER PRIMARY KEY,
    quest_id INTEGER REFERENCES quests(id) ON DELETE CASCADE,
    actor_type TEXT NOT NULL,  -- char, npc
    actor_id INTEGER NOT NULL,
    role TEXT DEFAULT 'participant',  -- leader, participant, target, observer
    UNIQUE(quest_id, actor_type, actor_id)
);
```

### 4. Decision / branching tracking

When players make a pivotal choice ("side with the Ironjaw family vs.
the rival smith"), the AI needs to know which branch the story is on.

**Proposal**: Add a `decisions` field to `story_actions` or use
`campaign_journal` with `entry_type='decision'`. The description
can capture "Players chose to side with Ted Ironjaw. The rival smith
Gorim Stonehand became hostile."

No new schema needed — the journal table handles this.

### 5. Campaign-level DM notes

Private notes for the DM/AI. Separate from public story log.

**Proposal**: Add `dm_notes TEXT` column to `campaigns` table (simple ALTER).

### 6. In-game calendar

Currently no concept of in-game time. The AI needs to know what day
it is, what season, time of day.

**Proposal**: Add to `campaigns`:
- `in_game_day INTEGER DEFAULT 0` (elapsed days since campaign start)
- `in_game_time TEXT DEFAULT 'morning'` (morning, afternoon, evening, night)
- `current_season TEXT DEFAULT 'spring'`

These are manually set by the AI (or DM) as the session progresses.

### 7. Party tracking

The `characters.party` field is a free-text string. For proper party
management:

**Proposal**: Add a `parties` table (deferred — complex, involves
inventory sharing, group decisions). For v18, the `party` string
field is sufficient. The AI can query "characters with party='The Iron Vanguard'".

### 8. Chronicle / timeline view

A unified timeline showing everything that happened in order.
Currently `story_actions` has a `story_progression` int but no
guaranteed ordering.

**Proposal**: Add `sort_order` or use `id` as the canonical order
(auto-increment guarantees insertion order). The `get-story-state`
command should return story_actions sorted by id ASC for timeline view.

---

## Implementation plan (v18)

### Schema

```sql
-- Campaign journal
CREATE TABLE campaign_journal (
    id INTEGER PRIMARY KEY,
    campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
    session_num INTEGER DEFAULT 0,
    entry_type TEXT DEFAULT 'narrative',
    description TEXT NOT NULL,
    location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Campaign DM notes + in-game time
ALTER TABLE campaigns ADD COLUMN dm_notes TEXT DEFAULT '';
ALTER TABLE campaigns ADD COLUMN in_game_day INTEGER DEFAULT 0;
ALTER TABLE campaigns ADD COLUMN in_game_time TEXT DEFAULT 'morning';
ALTER TABLE campaigns ADD COLUMN current_season TEXT DEFAULT 'spring';

-- Quests
CREATE TABLE quests (
    id INTEGER PRIMARY KEY,
    campaign_id INTEGER REFERENCES campaigns(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    quest_giver_npc_id INTEGER REFERENCES npcs(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'active',
    reward_description TEXT DEFAULT '',
    chapter TEXT DEFAULT '',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE quest_objectives (
    id INTEGER PRIMARY KEY,
    quest_id INTEGER REFERENCES quests(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    status TEXT DEFAULT 'incomplete',
    sort_order INTEGER DEFAULT 0
);

CREATE TABLE quest_actors (
    id INTEGER PRIMARY KEY,
    quest_id INTEGER REFERENCES quests(id) ON DELETE CASCADE,
    actor_type TEXT NOT NULL,
    actor_id INTEGER NOT NULL,
    role TEXT DEFAULT 'participant',
    UNIQUE(quest_id, actor_type, actor_id)
);
```

### New CLI commands

- `campaign add-journal-entry <id> <entry_type> <description> [location_id] [session_num]`
- `campaign list-journal <id> [limit]` — returns last N entries
- `campaign set-dm-notes <id> <text>`
- `campaign set-time <id> <day> <time_of_day> <season>`
- `quest add <campaign_id> <name> [description] [quest_giver_npc_id]`
- `quest add-objective <quest_id> <description> [sort_order]`
- `quest complete-objective <id>`
- `quest set-status <quest_id> <status>`
- `quest add-actor <quest_id> <char|npc> <actor_id> [role]`
- `quest list <campaign_id> [status]`
- `quest get <id>`

### Enhanced `get-story-state`

The existing `get-story-state` output should be enhanced to include:
- In-game time info
- Journal entries (last N)
- Active quests with objectives
- For each location: nested sub-locations, houses, shops, encounters,
  setpieces, and which NPCs/characters/creatures are present

### Display for AI context window

The AI should call `get-story-state` and get back a structured JSON
that includes everything needed to reconstruct the game state:

```
{
  "campaign": { name, chapter, session_num, in_game_day, in_game_time, season },
  "dm_notes": "...",
  "journal_last_10": [...],
  "active_quests": [...],
  "locations_tree": [
    {
      id, name, parent_id,
      sub_locations: [...],
      houses: [...],
      shops: [...],
      npcs_present: [...],
      characters_present: [...],
      creatures_present: [...]
    }
  ],
  "story_actions": [...]
}
```

This is the "minimum context packet" the AI needs to start a session.

---

## Out of scope for v18 (v19+)

- Party/inventory sharing
- Calendar with actual date strings (parse ISO dates)
- Weather system
- Random encounter tables linked to locations
- Faction standing auto-updates based on story actions
- Loot/treasure tables linked to locations
- Travel time between locations
- Random NPC name generation
