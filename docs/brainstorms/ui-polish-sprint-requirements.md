---
date: 2026-05-19
topic: ui-polish-sprint
tags: [navigation, layout, copy, assets, settings, splash]
---

# UI Polish Sprint

## Summary

Eight targeted improvements: add back navigation from the live session screen pre-kickoff so users can correct a wrong match selection; bring Video and Match landing pages to layout parity with Teams (search + sport filter chips); fix count labels as non-scrolling headers; update copy throughout to reflect phone-local storage; replace the old app icon with the new SVG/PNG set; relocate mock fixtures from `assets/mock/` into `lib/`; implement the native splash screen from the `splash-screen.html` design; and restructure Settings so every multi-option section collapses into a single nav row opening a sub-page.

---

## Problem Frame

The app has reached a stage where UI inconsistency, stale copy, and scattered assets make it harder to use and extend. Specifically: the Match session screen traps users who tapped the wrong match, with no escape until they formally end it; the Video and Match landing pages lack the search and filter affordances Teams has; "Your teams · 4" and similar count labels need consistent placement; copy in empty states and confirmations still refers to data living on the camera, which is wrong; the app ships with a placeholder icon; mock data is bundled as a runtime asset rather than staying in test code; there is no native splash screen; and Settings is a flat list that grows worse as more sections are added.

---

## Requirements

### 1 — Match session back navigation (pre-kickoff)

- R1.1. On the `_SessionScreen`, show a back arrow in `_TopBar` when `state.phase == MatchPhase.idle` (in addition to when `isEnded`).
- R1.2. Tapping the back arrow in `idle` phase calls `_leave(wasEnded: false)`, which resets `liveMatchProvider` and returns to the landing list. No match is removed from the upcoming list because it was never started.
- R1.3. The session screen back arrow during `idle` phase is visually identical to the one shown after a match ends.
- R1.4. No back arrow is shown during `period`, `periodBreak`, or `ended` phases (same as current behaviour for all except `ended`, which already shows one).
- R1.5. Re-entering setup for the same match (after going back) works normally — the setup screen initialises from the `UpcomingMatch` as before.

### 2 — Video and Match landing: search + filter parity with Teams

- R2.1. `_LandingScreen` in `lib/pages/match_page.dart` adds a search field and a sport filter chip row directly below the AppBar, matching the structure in `TeamsPage`: search field first, then a horizontal chip strip with "All" as the leading chip.
- R2.2. The match list is filtered by the search query (searches opponent name and team name) and by the selected sport chip.
- R2.3. `VideoPage` in `lib/pages/video_page.dart` adds the same search field and sport filter chip row.
- R2.4. The video list is filtered by the search query (searches team name) and by the selected sport chip (derived from the team's sport).
- R2.5. Both pages use the same `_SearchField` component style as `TeamsPage` (pill container, `#4FC3F7` icon tint, clear button when non-empty).
- R2.6. Filter state is local to each page and resets when the page is rebuilt (no provider required for v1).

### 3 — Count labels: fixed non-scrolling placement

- R3.1. The count label text ("Your teams · N", "Upcoming · N", etc.) must always sit in a fixed position above the scrollable list — it must not scroll with list items.
- R3.2. The current `WfSection` sitting in a `Column` above an `Expanded(ListView)` already satisfies this for Teams; the same pattern must be applied consistently to every list-with-count in the app.
- R3.3. Where a count label is currently inside the `ListView` (as a first item), it must be extracted out to be a sibling of the `Expanded(ListView)` in the enclosing Column.
- R3.4. The label style (`WfSection`) is unchanged.

### 4 — Copy updates: phone-local storage

- R4.1. Remove all copy that implies teams, matches, or recordings live primarily on the camera. Update it to reflect that the data is stored on the phone.
- R4.2. Specific strings to change (non-exhaustive — implementation should audit all):
  - `teams_page.dart` empty state body: "Teams live on the camera. Add your first one to start recording matches." → "Add your first team to start organising matches."
  - `teams_page.dart` confirm-delete body: "…will be removed from the camera." → "…will be permanently deleted."
  - `settings_page.dart` `_ConnectCameraBanner` body: "Connect a camera to manage users, formats, and streaming destinations." → keep as-is (this is accurately camera-gated data).
  - `match_page.dart` `_NoUpcomingState` body: "Past matches live in the Video and Teams tabs." → "Past matches are in the Video and Teams tabs."
  - `video_page.dart` empty state body: "Connect a camera to browse recordings and download them to this phone." → "Record a match to start building your library."
- R4.3. Settings switch-user dialog body: "Your teams, matches, and streaming destinations will reload to show their data." — this is already correct; leave unchanged.
- R4.4. No functional behaviour changes; copy-only.

### 5 — App icon: replace with new icon set

- R5.1. The dev build icon uses `launcher/icon-dev-*.png` (pre-rendered at 16, 24, 32, 48, 64, 96, 192, 512, 1024 px) and `launcher/icon-dev-foreground.png` (adaptive icon foreground for Android).
- R5.2. The prod build icon uses the equivalent `icon-prod-*.png` and `icon-prod-foreground.png` files.
- R5.3. `assets/brand/app_icon.png` is no longer referenced in code or `pubspec.yaml`.
- R5.4. The `assets/brand/` directory may be removed once no references remain.
- R5.5. `assets/icon-dev.svg` and `assets/icon-prod.svg` are added to the `pubspec.yaml` assets list (for in-app use, e.g. splash or about screen).
- R5.6. Icon placement follows Flutter platform conventions: Android mipmap directories, iOS `Assets.xcassets/AppIcon.appiconset`.

### 6 — Mock fixtures: move out of `assets/mock/`

- R6.1. The JSON fixture files currently at `assets/mock/fixtures/*.json` are moved into `lib/ble/mock_fixtures/` so they are co-located with `lib/ble/mock_ble_service.dart`.
- R6.2. `MockBleService` loads fixtures from the new location (using `rootBundle` with updated paths, or switching to compile-time strings/constants).
- R6.3. `assets/mock/` and all its entries are removed from `pubspec.yaml`.
- R6.4. The mock video file (`assets/mock/mock-video.mp4`), if referenced at runtime, is either kept in assets under a different path or removed; if it is only referenced in dead/stub code it may be deleted outright.
- R6.5. No test or integration test currently relies on the old asset path; if any do, they are updated.

### 7 — Native splash screen

- R7.1. The native splash screen uses the design from `splash-screen.html`: solid `#0A0A0A` background, centered SC monogram logo (yellow `#E8FF3C` rounded rect, `SC` text in `#0A0A0A`, a red circle on a baseline rule), "ScoutCamera" wordmark below, and a version string anchored near the bottom in muted monospace.
- R7.2. Implementation uses the `flutter_native_splash` package (added to `pubspec.yaml`). The package is configured in `pubspec.yaml` under the `flutter_native_splash:` key.
- R7.3. The splash is generated for both Android and iOS via `dart run flutter_native_splash:create`.
- R7.4. `splash-screen.html` is deleted once the native splash is implemented and verified to render.
- R7.5. Dark background (`#0A0A0A`) is used for both light and dark mode splash; no light-mode variant is required for v1.

### 8 — Settings: compact, section-collapsed layout

- R8.1. Any Settings section that currently contains more than one interactive option is collapsed into a single `_NavRow` that opens a dedicated sub-page. The sub-page handles the multi-option content.
- R8.2. Sections that already have exactly one nav row remain unchanged (Match setup → Sport setups, Streaming setup → Streaming destinations).
- R8.3. The **User** section collapses: replace the current "active user picker card + Manage users nav row" pattern with a single `_NavRow` labelled "Users" that shows the active user name as a badge and opens a Users sub-page. The Users sub-page shows the active-user picker and the Manage users CTA.
- R8.4. The **Data** section collapses: replace the two-row "Export backup / Restore backup" card with a single `_NavRow` labelled "Backup & restore" that opens a Data sub-page. The Data sub-page contains the existing export and restore flows.
- R8.5. The **App** section collapses: replace the three-row "Theme / Permissions / About" list with a single `_NavRow` labelled "App" that opens an App settings sub-page with those three rows.
- R8.6. The Camera card at the top of the populated Settings page remains as a full card (not collapsed), since it is the primary status element and its actions (Reboot, Update fw, Disconnect, Diagnostics) are camera-state-dependent and not a simple list.
- R8.7. The resulting Settings page (when connected) has this structure:
  ```
  [Camera card]
  ─────────────
  Camera          (existing camera card, unchanged structurally)
  ─────────────
  Users           → Users sub-page
  Match setup     → Sport setups page
  Streaming       → Streaming destinations page
  ─────────────
  App             → App settings sub-page
  Backup & restore → Data sub-page
  ```
- R8.8. Every sub-page introduced in R8.3–R8.5 uses a standard `Scaffold` with an AppBar back arrow. Visual style inherits existing `WfCard` / `_NavRow` / `_RowItem` patterns.
- R8.9. The existing `settings-page-reshape-requirements.md` requirements (R1–R25 in that doc) remain in effect and are not superseded by this document. This document extends that work.

---

## Acceptance Examples

- AE1. **Covers R1.1–R1.3.** Given the user has selected a match and tapped "Start match" but has not yet tapped "Kickoff", the session screen shows a back arrow in the top bar. Tapping it returns the user to the match landing list and the match remains in the upcoming list.
- AE2. **Covers R1.4.** Given the user is in an active period (phase = `period`), no back arrow is shown.
- AE3. **Covers R2.1, R2.5.** Given the user is on the Match landing screen, a search field and sport filter chip row appear below the AppBar, visually identical to the Teams page.
- AE4. **Covers R2.2.** Given the user types "Arsenal" in the Match landing search field, only upcoming matches for teams or opponents containing "Arsenal" are shown.
- AE5. **Covers R3.2.** Given the Teams page shows 6 teams and the user scrolls to the bottom of the list, the "Your teams · 6" label remains visible at the top of the list body (does not scroll away).
- AE6. **Covers R4.2.** Given the user opens the Teams tab for the first time with no teams added, the empty state body reads "Add your first team to start organising matches." — not "Teams live on the camera."
- AE7. **Covers R5.3, R5.5.** Given a dev build, the app launches with the dev icon (yellow/dark design); `assets/brand/app_icon.png` is not referenced anywhere; `assets/icon-dev.svg` appears in `pubspec.yaml` assets.
- AE8. **Covers R6.1, R6.3.** Given `pubspec.yaml`, no `assets/mock/` entry exists. `lib/ble/mock_fixtures/` contains the JSON files. `MockBleService` loads them from the new path without error.
- AE9. **Covers R7.1, R7.4.** Given the app is launched on Android or iOS, the native splash screen shows a dark background with the SC monogram logo and "ScoutCamera" wordmark. `splash-screen.html` does not exist in the repo.
- AE10. **Covers R8.3, R8.7.** Given the Settings page is open with a camera connected, the User section renders as one tappable `_NavRow` row showing "Users" with the active user name as a badge. Tapping it opens a Users sub-page with the user picker and Manage users CTA.
- AE11. **Covers R8.4.** Given the Settings page is open, the Data section renders as one row "Backup & restore". Tapping it opens a sub-page with the existing export and restore flows.

---

## Success Criteria

- A user who taps the wrong match and reaches the session screen can escape without ending the match.
- Every list page in the app has search and filter parity — a user learns the pattern once.
- Count labels never scroll away; they are always visible as anchored section headers.
- No empty state or confirmation copy refers to teams or matches "living on the camera".
- The app ships with the correct icon (dev vs. prod) and a polished native splash.
- Mock data is not bundled as a runtime asset.
- The Settings page requires at most two taps to reach any setting, with no flat multi-row sections cluttering the main view.

---

## Scope Boundaries

- This document does not add new features to any section — it restructures existing content and adds navigation parity.
- The Settings sub-pages introduced here are thin containers for existing functionality, not redesigns of that functionality.
- Splash screen is v1 only — no animation, no light-mode variant, no A/B.
- The `flutter_native_splash` package generates platform files; the generated platform files are committed to the repo but not manually edited.
- This document does not change the BLE protocol, firmware contract, or camera-side storage model.

---

## Dependencies / Assumptions

- `flutter_native_splash` package is not yet in `pubspec.yaml` and must be added.
- `assets/icon-dev.svg` and `assets/icon-prod.svg` already exist in the repo root `assets/` folder.
- The `launcher/` folder at the repo root contains pre-rendered icon PNGs at the required Android/iOS resolutions.
- `MockBleService` currently reads fixtures via `rootBundle`; paths are string literals that can be updated without structural changes.
- The existing `settings-page-reshape-requirements.md` spec (Settings R1–R25) is assumed to be implemented or in progress; this document extends it without conflicting.
- A Settings "Users sub-page" and "Data sub-page" are new files; they follow the `*_page.dart` naming convention in `lib/pages/`.

---

## Outstanding Questions

### Resolve Before Planning

- *(none)*

### Deferred to Planning

- [R6.4] Whether `assets/mock/mock-video.mp4` is actively referenced (e.g. in a video player stub or integration test). Audit during implementation; delete if dead.
- [R7.2] Whether `flutter_native_splash` supports the full SC monogram SVG as the splash image, or whether a PNG export from the SVG is needed. The package accepts PNG; the SVG may need to be rasterised at 1024×1024 before passing to the tool.
- [R8.3] Exact shape of the Users sub-page: whether it uses the existing `ManageUsersPage` as its destination, or introduces a new wrapper. Both satisfy R8.3; planning should pick the lowest-carrying-cost option.
