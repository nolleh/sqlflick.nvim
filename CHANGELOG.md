# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [0.6.0] - 2026-10-01

### Added

- Add native schema-aware SQL omni-completion for PostgreSQL, MySQL, and SQLite.
- Suggest tables, views, columns, aliases, and SQL keywords from the selected database.
- Cache schema metadata in memory and add `:SQLFlickRefreshSchema` for explicit refreshes.
- Retry schema loading on user-triggered completion and pause after three consecutive failures until an explicit refresh.

### Changed

- Bump the backend version to `0.6.0` for the new schema metadata endpoint.

## [0.5.3] - 2026-09-17

### Added

- Add a local Neovim test workflow with Plenary and Make targets.

### Fixed

- Preserve count-query errors instead of treating them as zero rows and
  executing an unpaginated query.

## [0.5.2] - 2026-02-27

### Added

- Add `CHANGELOG.md` for release tracking.
- Restore pagination runtime module integration.

### Changed

- Improve query pagination performance and reduce unnecessary data processing.
- Bump backend/plugin version to `0.5.2`.

### Fixed

- Fix a critical regression where the plugin failed to load because `sqlflick.pagination` module resolution broke.
- Adjust MySQL pagination fallback behavior for safer default limits.

## [0.5.1] - 2026-01-30

### Changed

- Improve pagination performance flow (`chore: more-efficent pagignation`).

### Fixed

- Improve MySQL query error notification handling.

### Docs

- Update demo video assets.

## [0.5.0] - 2025-12-04

### Added

- Add pagination feature and page navigation flow in result view.
- Add demo content and docs updates for new UX.

### Changed

- Refresh docs/media assets (GIF/video and links).

## [0.4.0] - 2025-08-03

### Added

- Add column navigation feature in result view.
- Add configuration options for column min/max width.
- Add debug output for backend information.

### Changed

- Change default backend port to reduce common port conflicts.
- Update highlighting API usage to current `hl.range` style.

### Fixed

- Fix display column options not being applied.
- Fix header highlight behavior when wrapped columns are displayed.

### Notes

- Baseline version before pagination count-flow update.

## [0.3.1] - 2025-08-02

### Added

- Add backend version check and install guard for outdated binaries.

## [0.3.0] - 2025-06-27

### Added

- Add Oracle DB support.
- Improve result-view usability including word wrap-related updates.

## [0.2.0] - 2025-06-18

### Changed

- Internal plugin rename and related migration updates.

## [0.1.3] - 2025-06-15

## [0.1.2] - 2025-06-11

## [0.1.1] - 2025-06-10

## [0.1.0] - 2025-06-01

## [0.0.7] - 2025-05-07

## [0.0.6] - 2025-05-02

## [0.0.5] - 2025-04-27

## [0.0.4] - 2025-04-26

## [0.0.3] - 2025-04-15

## [0.0.2] - 2025-04-15

## [0.0.1] - 2025-04-15

### Notes

- These versions are preserved from existing git tags.
