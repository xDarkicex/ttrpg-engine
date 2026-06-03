# Changelog

All notable changes to this project will be documented in this file.

## [0.1.2] - 2026-06-03

### Fixed
- **Resistance + Vulnerability stacking**: Per PHB 5e rules, Resistance and Vulnerability both apply in sequence (Resistance first, then Vulnerability). Multiple instances of the same type don't stack. Previous implementation treated them as mutually exclusive.

## [0.1.1] - 2026-06-03

### Fixed
- **Release workflow**: Added `libsqlite3-dev` installation on Linux, enabled `SQLITE3_SYSTEM_LIB` define for proper sqlite3 linking

## [0.1.0] - 2026-06-03

### Added
- Initial release with full CLI for D&D campaign management
- Character, NPC, item, spell, faction, and campaign tracking
- SQLite database with automatic schema migrations
- JSON output mode for scripting
- GitHub Actions release workflow for macOS and Linux
