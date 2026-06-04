# World & Entities — Planning Document

Status: **DRAFT, pending review**. Source material is conversation
between the maintainer and the contributor review feedback on Ted
(half-orc blacksmith, NPC 3) and Jenny (human baker, NPC 4) NPCs
created during the v13/v14 work.

This document captures the design intent for: sub-locations,
sub-things inside a location (houses, shops, encounters, setpieces),
access control, relationship_status math, faction modulation, and
the formatter hygiene bugs that were found while stress-testing the
display.

---

## 1. World model

### 1.1 Hierarchy

```
campaigns
└── locations (top level — Novigrad, Ashwick, etc.)
    └── locations (sub-locations via parent_id — Blacksmith District, Market, Slum, Harbor, Castle, ...)
        ├── houses     (residential properties; npc_id is the resident)
        ├── shops      (commercial properties; npc_id is the proprietor)
        ├── encounters (wandering, scripted, or repeatable events in the area)
        └── setpieces  (story-driving locations tagged to chapter events)
```

`locations.parent_id` is a nullable FK to `locations.id`. Top-level
locations have `parent_id IS NULL`. The campaign view is then
"campaign → list of root locations → each root's sub-locations →
their sub-things".

The user-clarified separation: `locations` is the *world / district*
(an explorable area), not a specific building. So "Ashwick Blacksmith
District" is a location; "The Anvil & Flame, Ted's smithy" is a
shop inside that location.

### 1.2 Sub-things (separate tables, not polymorphic)

The four sub-things have different columns. Keeping them as separate
tables keeps the schemas clean.

| Table        | Purpose                                                      | Key columns |
|--------------|--------------------------------------------------------------|-------------|
| `houses`     | Residential properties                                       | `name`, `description`, `npc_id` (resident), `scale`, `restricted`, `restricted_until`, `inventory` |
| `shops`      | Commercial properties                                        | `name`, `description`, `npc_id` (proprietor), `scale`, `open_hours`, `restricted`, `inventory` |
| `encounters` | Wandering / scripted / repeatable events in an area          | `type`, `description`, `npc_id` (the encounter's NPC actor, if any) |
| `setpieces`  | Story-driving locations tagged to chapter events             | `name`, `description`, `chapter_event` (text describing the trigger) |

All four tables have `location_id INTEGER REFERENCES locations(id) ON
DELETE CASCADE`. Cascade so deleting a location cleans up its content.

### 1.3 `scale` enum (used by both `houses` and `shops`)

The `scale` field is the loot/pricing tier *and* the social-status
indicator. Same enum, used in both tables. Display in the sheet with
the social-status connotation since that's what the DM uses at a glance.

| Value     | Houses meaning                              | Shops meaning                                 |
|-----------|----------------------------------------------|------------------------------------------------|
| `abandon` | Ruined; squatters, drug dens, or ghosts     | (n/a — not a shop tier)                       |
| `slave`   | Slave house (illegal operation, fantasy)     | (n/a)                                          |
| `slum`    | Poor, low-tier tenant                        | Low-end goods, basic provisions                |
| `low`     | Cheap commoner home                          | Cheap crafts, mass goods                       |
| `mid`     | Middle class, decent                         | Mid-tier goods, journeyman work                |
| `high`    | Wealthy merchant                             | High-quality, master craftsman                 |
| `estate`  | Minor noble                                  | Elite purveyors                                |
| `royal`   | Monarch / royal family                       | (n/a)                                          |
| `boutique`| (n/a)                                        | Custom crafts, named artisan                   |
| `illegal` | (n/a)                                        | Black market, thieves' fence, no questions    |

`shops` can also be `illegal` (for fence goods, etc.). The user
explicitly said "illegal" is one tier; I'll keep it in shops only.

### 1.4 `restricted` access flag

A property (house, shop, or whole location) can be `restricted` — off-limits
to non-owner characters and NPCs. Plus a `restricted_until` field that
indicates when restriction ends.

- For an **individual's house**: `restricted_until = "24/7"` (always
  restricted, only the owner and trusted guests).
- For a **shop**: `open_hours` controls "during business hours, not
  restricted; off-hours, restricted". So `restricted` is the "after
  hours" flag and the binary shop-open check uses `open_hours` to decide
  whether the property is currently accessible.
- For a **location (district)**: `restricted_until` is a global flag.
  E.g. "Castle: restricted, gate guarded, do not enter" or "Slum: no
  restrictions, anyone can walk in".

`restricted_until` is text for flexibility:
- `"24/7"` — always
- `"open_hours"` — defer to the open_hours schedule (shops)
- `"campaign_end"` — until the campaign finishes
- A specific in-game date `"1492-03-15"` — once past, restriction lifts
- An empty string — uses faction + relationship access rules (see §2)

### 1.5 Schema (proposed v15 migration)

```sql
-- Sub-locations: every location can have a parent.
ALTER TABLE locations ADD COLUMN parent_id INTEGER REFERENCES locations(id) ON DELETE CASCADE;
ALTER TABLE locations ADD COLUMN restricted INTEGER DEFAULT 0;
ALTER TABLE locations ADD COLUMN restricted_until TEXT DEFAULT '';

-- Houses
CREATE TABLE IF NOT EXISTS houses (
    id INTEGER PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    npc_id INTEGER REFERENCES npcs(id) ON DELETE SET NULL,
    scale TEXT DEFAULT 'mid',
    restricted INTEGER DEFAULT 0,
    restricted_until TEXT DEFAULT '',
    inventory TEXT DEFAULT '',
    UNIQUE(location_id, name)
);

-- Shops
CREATE TABLE IF NOT EXISTS shops (
    id INTEGER PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    npc_id INTEGER REFERENCES npcs(id) ON DELETE SET NULL,
    scale TEXT DEFAULT 'mid',
    open_hours TEXT DEFAULT '06:00-22:00',
    restricted INTEGER DEFAULT 0,
    inventory TEXT DEFAULT '',
    UNIQUE(location_id, name)
);

-- Encounters
CREATE TABLE IF NOT EXISTS encounters (
    id INTEGER PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    type TEXT DEFAULT 'wander',
    description TEXT DEFAULT '',
    npc_id INTEGER REFERENCES npcs(id) ON DELETE SET NULL
);

-- Setpieces (story-driving places)
CREATE TABLE IF NOT EXISTS setpieces (
    id INTEGER PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    chapter_event TEXT DEFAULT '',
    UNIQUE(location_id, name)
);
```

Linking entities to a specific sub-thing is via the existing
`location_id` column on `characters`/`npcs`/`creatures`. For a
"this NPC is at this specific house" link, the simplest is: the
NPC's `location_id` points to the sub-location. The sub-location
itself has `parent_id` pointing to the district. Walking up the
parent chain gives the full district path.

**Future option (defer to v16+):** Add `setpiece_id` to characters/npcs
for "I am *at* the Anvil Bench, not just in the Blacksmith District".
For now, `location_id` is sufficient.

---

## 2. Access control

### 2.1 Existing primitive: `npc_relationships`

We already have `npc_relationships(npc_id_1, npc_id_2, friendship_level,
notes)` where `friendship_level` is an int from `-10` to `+10`. This is
the per-pair relationship between two NPCs. We can reuse it for the
"DMs/PvP" case ("how does NPC X feel about character Y?") and extend
with a `relationship_status` float on `characters` for the broader
"this character vs everyone" case.

### 2.2 `relationship_status: float` (per character)

Each `character` row gains a `relationship_status: float` column
defaulting to `0.0` (the mean — neutral). This is the
"character-generic charisma / disposition" stat: a character with
high `relationship_status` walks into a room and NPCs warm up faster
by default. This is **not** the per-pair score — that's still in
`npc_relationships`.

Range: `0.0` (hostile default) to `1.0` (universally loved). Default
`0.5` (neutral).

### 2.3 Per-property access math

When a character tries to enter a `restricted` property:

1. Look up the `friendship_level` between the character's owner and
   the property's `npc_id` from `npc_relationships` (default to 0 if no
   row).
2. Add the character's `relationship_status` (0.0–1.0) as a
   flat bonus mapped to a -5 to +5 modifier.
3. Convert `friendship_level + modifier` to a 0.0–1.0 score:
   - Score 0.0–0.6: **Guarded, no entry** (NPC won't open the door).
   - Score 0.6–0.7: **Wary, allowed entry** (NPC lets you in but
     watches you).
   - Score 0.7–0.85: **Friendly, welcomed.**
   - Score 0.85+: **Trusted, may have access to private areas.**
4. If `restricted_until = "open_hours"`, the property is non-restricted
   during `open_hours` window — skip the check.

### 2.4 Faction modulation

Faction membership flips the access math. The `factions` table exists
and `factions_id` is on `characters`/`npcs`/`creatures`.

- If visitor and owner share a faction: skip the friendship check
  entirely (auto-allowed).
- If visitor and owner are in **opposing** factions: instant -0.3
  relationship penalty, restricted flag is set on the property
  regardless of stored value (until the faction war ends), and
  the NPC may attack on sight depending on standing.
- **Lying-in-wait** test: even if a character is in the same faction,
  the local *chapter* of the faction may not recognize them. The
  `faction_standings` table already has per-character standing with
  factions; `0` is neutral, negative is hostile, positive is allied.
  Use this as a tie-breaker: same-faction but standing is 0 →
  still need friendship check; same-faction and standing > 0 → auto.

`opposing` is derived, not stored: two factions are opposing if there's
a row in a new `faction_relations` table with `relation = 'enemy'`.
Deferred to v16+.

---

## 3. NPC display formatter hygiene (from Ted/Jenny review)

Bugs found while reviewing the NPC stat block for Ted and Jenny that
also apply to creatures. Fix in v15 alongside the world model.

| # | Issue                                                  | Where                                          | Fix |
|---|--------------------------------------------------------|------------------------------------------------|-----|
| 1 | Skills show only the ability modifier, not the prof bonus | `print_character_skills_text` and `print_npc_skills_text` | Compute `total_mod = ability_mod + prof_level * prof_bonus`. Ted (STR 16, prof 1) athletics should be `+5`, not `+1`. |
| 2 | `Location: None (ID: 0)`                              | npc, creature, character `get` display          | Only print `(ID: N)` when `location_id > 0` and name is real. Otherwise `Location: None`. |
| 3 | `Combat: no` is misleading on NPCs / non-engaged stat blocks | creature `get`, npc `get` (carryover)    | Omit `Combat: no` on stat blocks. Only show `Combat: Yes` if the flag is set. |
| 4 | `Abilities: None` is misleading on monsters (the traits/actions ARE the abilities) | creature `get` | Drop the `Abilities:` table call for monsters. |
| 5 | `CR: 0` for commoners                                  | npc `get`                                       | Don't print a CR line for NPCs (it's a creature stat). |
| 6 | `Daily Role: Daily Role` echo                          | input handling                                  | Already fixed in this session by passing the right arg; document the order: `npc set-details <id> <ac> <story_role> <daily_role> <backstory>`. |
| 7 | No `help` subcommand for `npc`                         | route_npc                                      | Add `case "help":` that prints the same help table as the top-level `dnd-agent help` filtered to npc, or just lists `npc` subcommands. |

---

## 4. Open questions for the contributor

1. **Should `locations.parent_id` be many levels deep (recursive tree)
   or only one level (district → sub-location, no district-of-district)?**
   Recommendation: recursive (a sub-location *can* itself have a
   sub-location, e.g. "Castle" → "Castle Keep" → "Throne Room"). The
   display walks the parent chain to print
   `Castle > Keep > Throne Room`.

2. **Should `relationship_status` be a per-character scalar, or
   per-(character, location-type) like `(char, slum) = 0.3,
   (char, castle) = 0.8`?**
   Recommendation: scalar for v15. The per-(char, location) is a v16+
   concern and adds combinatorial complexity.

3. **Is `restricted_until = "open_hours"` the only schedule format?**
   The `open_hours` field is plain text today
   (e.g. `"06:00-22:00"`). Should it parse as a real schedule
   with days, or is "we trust the DM" the right answer? Recommendation:
   plain text, no parser. The display shows the raw text and the
   check is a substring match.

4. **Should `setpieces` require a chapter_event, or can a setpiece
   just be flavor?**
   Recommendation: `chapter_event` is optional. Empty = flavor.
   Non-empty = "this location drives plot when the chapter
   event triggers".

5. **For `houses`/`shops`, do we want a "loot table" reference
   (table name) or a freeform `inventory` text?**
   Recommendation: freeform `inventory` text for v15. Real loot
   tables (id-based reference to a future `loot_tables` table) is
   v16+.

---

## 5. Implementation order

1. **v15 migration** — `locations.parent_id`, `restricted`,
   `restricted_until`; create `houses`, `shops`, `encounters`,
   `setpieces` tables.
2. **Setters and getters** — `house add/list/get/delete`,
   `shop add/list/get/delete`, `encounter add/list`,
   `setpiece add/list`, `location set-parent`,
   `location set-restricted`, `location list-sub`.
3. **Access-check helper** — `can_enter(visitor_id, property_kind,
   property_id) -> enum {allowed, wary, denied, auto}`. Reused by
   any `enter-location` command (also new in v15).
4. **Formatter hygiene fixes** — items 1–7 in §3.
5. **Build the Ashwick test world** — see §6.
6. **Test the full flow** — set Ted to a sub-location, verify display
   shows `Location: Blacksmith District > The Anvil & Flame (ID: N)`.

## 6. Ashwick test world (post-v15)

```
locations
├── Ashwick (town, top-level, parent_id=null)
│   ├── Blacksmith District
│   │   ├── house: "The Forge House" (scale=mid, restricted=24/7, npc=Ted)
│   │   └── shop: "The Anvil & Flame" (scale=mid, open_hours="06:00-22:00", npc=Ted)
│   ├── Market District
│   │   ├── shop: "Ironjaw Bakery" (scale=mid, open_hours="05:00-15:00", npc=Jenny)
│   │   └── setpiece: "The Old Bell Tower" (chapter_event="Rings three times at midnight during Chapter 3")
│   ├── Residential Quarter
│   │   ├── house: "The Ironjaw Farmstead" (scale=mid, restricted=24/7, npc=Ted & Jenny)
│   │   ├── house: "Widdershins Cottage" (scale=low, restricted=24/7, npc=4)
│   │   ├── house: "Old Glassblower's Row" (scale=abandon, npc=null)
│   │   └── shop: "Morning Glory Florist" (scale=mid, open_hours="07:00-18:00", npc=Jenny)
│   ├── Slum
│   │   ├── house: "Rats End" (scale=slave, npc=6)
│   │   ├── house: "The Hollow" (scale=abandon, npc=null)
│   │   └── encounter: "Pickpocket ring" (type=crime, npc=6)
│   └── Outskirts
│       └── setpiece: "The Old Mill" (chapter_event="When the party investigates the plague, the mill has the answer")
```

NPCs and creatures link via their existing `location_id` column.
Ted (NPC 3) → location_id = "The Anvil & Flame" (sub-location).
Jenny (NPC 4) → location_id = "Ironjaw Bakery" OR "The Ironjaw Farmstead"
(their actual home). For a married couple, one row in
`npc_relationships` with `friendship_level = 10` already exists
from the v13 work; the access check uses it.

---

## 7. Out of scope for v15 (track for v16+)

- Per-(character, location-type) relationship tables.
- Faction `opposing` relation table.
- Loot tables (currently freeform `inventory` text).
- `setpiece_id` on characters/npcs/creatures (currently `location_id`
  only).
- `enter <location>` command that uses the access check.
- Schedule parser for `open_hours` (currently a text substring).
- Per-character "scars / history" log.

Each of these is a v15.1, v15.2, etc. or v16 candidate.
