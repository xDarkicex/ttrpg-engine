# dnd-agent — project rules

CLI tool for D&D game management backed by SQLite. Single DM model — the
DM's agent is the sole writer; all players query through the DM.

## Cyclomatic complexity

- **Hard limit: 10 per proc.** McCabe's original threshold.
- Counted as `1 + decision_points`, where decision points are:
  `if`, `else if`, `for`, `case` (in `switch`), `&&`, `||`, `?:`.
- `break`, `continue`, `defer`, and short-circuit exits do not count.
- A proc that exceeds the limit must be split. No exceptions.
- Helper procs that exist only to keep a caller under the limit are
  fine — clarity over cleverness.

## Testing

- **Line coverage floor: 90%. Target: 95%.**
  Coverage is reported by `odin test`; CI / pre-commit must enforce.
- Every **exported** proc (any proc starting with a non-underscore
  name that's reachable from `main`) must have at least one
  `test_*` proc.
- Internal helpers used by exported procs must be tested **iff**
  they contain branching logic. Pure data-shuffling helpers do
  not need their own test.
- Test names: `test_<proc>_<case>` (e.g. `test_character_create`).
- Use `core:testing`. Prefer `testing.expect_value` for exact
  matches, `testing.expect` for booleans, `testing.expect_error`
  for error cases.
- Tests must be hermetic. No network, no filesystem outside
  `os.tmp_dir` for the rare case it's needed. The CLI binary
  itself is exercised manually in the shell, not in tests.
- **Forcing paths is acceptable** to reach 95% on error branches.
  The alternative — uncovered error paths — is not. If a branch
  is genuinely unreachable, remove it; don't ship it untested.

## Code style

- Idiomatic Odin: `package main`, lower_snake_case procs,
  PascalCase types, `core:*` imports, foreign libs only when
  there's a real reason.
- **C interop is a first-class tool here, not a last resort.**
  `ext:sqlite3` with `-collection:ext=./vendor` for all DB access.
  Declare foreign procs with `---` end-of-statement and group them by header.
- Use `when ODIN_OS == .Linux || ODIN_OS == .Darwin { ... }` for
  platform-specific foreign imports. The two platforms this
  project supports. If a third is added, this rule is the place
  to update.
- Error handling: explicit returns with `(value, err)`. No
  panics in library-style procs. `panic` only in `main` for
  truly unrecoverable setup failures.
- No comments that describe *what* the code does. Comments
  describe *why* a non-obvious decision was made.
- Public CLI surface is `dnd-agent <command> [args] [--json]`.
  All commands output JSON when `--json` is passed.
  Every command returns 0 on success, non-zero on failure with a
  descriptive error on stderr.

## Memory management

- **Arenas are mandatory.** All transient allocations (e.g. parse
  buffers, scratch strings) come from a `core:mem/tlsf` arena.
  No `new`, `alloc`, `make([]T)` in hot paths. The arena is
  initialized in `main` and passed through context or as a
  parameter; it is never a global.
- **Zero heap after startup.** The arena may allocate during
  initial setup (argument parsing, arena creation), but after
  the first DB operation the critical path is allocation-free.
  If a proc cannot avoid a transient allocation, it must return
  an error rather than silently heap-allocate.

## Algorithm constraints

- **O(1) only.** All DB operations are constant time relative to
  result set size (single-row lookups, not full table scans unless
  explicitly requested).
- **No linear searches or O(n) string operations** in the hot path.

## Schema

```sql
CREATE TABLE characters (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    class       TEXT,
    level       INTEGER DEFAULT 1,
    current_hp  INTEGER DEFAULT 0,
    max_hp      INTEGER DEFAULT 1,
    backstory   TEXT,
    owner       TEXT,         -- DM identifier
    created_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE items (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    item_type   TEXT           -- weapon, armor, potion, loot
);

CREATE TABLE inventory (
    id           INTEGER PRIMARY KEY,
    character_id INTEGER REFERENCES characters(id),
    item_id      INTEGER REFERENCES items(id),
    quantity     INTEGER DEFAULT 1
);

CREATE TABLE npcs (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT,
    current_hp  INTEGER DEFAULT 0,
    max_hp      INTEGER DEFAULT 1,
    dm_notes    TEXT,           -- hidden DM info
    campaign_id INTEGER REFERENCES campaigns(id)
);

CREATE TABLE campaigns (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    chapter     TEXT DEFAULT '',
    session_num INTEGER DEFAULT 0,
    created_at   TEXT DEFAULT CURRENT_TIMESTAMP
);
```

## Repo layout

```
.
├── CLAUDE.md         # this file
├── README.md         # human-facing build + usage
├── main.odin         # CLI entry, command routing
├── db.odin           # sqlite init, schema, helpers
├── character.odin    # character CRUD
├── inventory.odin    # inventory CRUD
├── npc.odin          # NPC CRUD
├── campaign.odin     # campaign/session management
├── character_test.odin
├── inventory_test.odin
├── npc_test.odin
├── campaign_test.odin
└── Makefile          # build, test, coverage
```

Files in `*_test.odin` are only compiled by `odin test`. Split
tests by unit so a failure in one doesn't hide a failure in
another.