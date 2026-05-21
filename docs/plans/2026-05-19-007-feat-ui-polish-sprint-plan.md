---
title: "feat: UI Polish Sprint — navigation, layout parity, copy, assets, and settings"
type: feat
status: completed
date: 2026-05-19
origin: docs/brainstorms/ui-polish-sprint-requirements.md
---

# feat: UI Polish Sprint

## Summary

Twelve implementation units across three categories: (1) UX fixes — pre-kickoff back navigation and count-label anchoring; (2) layout parity — search + sport filter chips on Video and Match landing pages, matching Teams; (3) housekeeping — phone-local copy, app icon wiring, mock fixture relocation, native splash screen, and Settings section collapse. No new features; every unit either fixes a gap or applies an existing pattern to a new surface.

---

## Problem Frame

The app has reached a stage where several inconsistencies create friction: the Match session screen traps users who tapped the wrong match pre-kickoff; the Video and Match landing pages lack the search and filter affordances Teams has; count labels ("Your teams · 4") scroll off screen; copy still implies camera-side storage; the dev icon is the scaffold placeholder; mock JSON fixtures are bundled as runtime assets; there is no native splash; and Settings is a flat list that adds carrying cost with each new section. (see origin: `docs/brainstorms/ui-polish-sprint-requirements.md`)

---

## Requirements

- R1.1–R1.5. Pre-kickoff back navigation on Match session screen.
- R2.1–R2.6. Search + sport filter chip parity on Video and Match landing pages.
- R3.1–R3.4. Count labels as fixed, non-scrolling headers.
- R4.1–R4.4. Copy updates: phone-local data storage framing.
- R5.1–R5.6. App icon replacement with new launcher PNG set.
- R6.1–R6.5. Mock fixture relocation out of `assets/mock/`.
- R7.1–R7.5. Native splash screen implementation and `splash-screen.html` deletion.
- R8.1–R8.9. Settings restructuring: multi-option sections collapse to single nav rows.

**Origin acceptance examples:** AE1–AE11 (all in `docs/brainstorms/ui-polish-sprint-requirements.md`)

---

## Scope Boundaries

- No changes to BLE protocol, firmware contract, or camera-side storage model.
- No changes to `ManageUsersPage`, `DiagnosticsPage`, `SportPresetsPage`, or `StreamingDestinationsPage` internals.
- No iOS/Android flavor configuration beyond what `flutter_launcher_icons` config supports.
- No animated splash; no light-mode splash variant.
- The `mock-video.mp4` file: audit during U7 and delete if unreferenced; move if still needed.
- The existing `settings-page-reshape-requirements.md` plan (plan `002`) is out of scope here — this sprint does not duplicate that work. U10–U12 must not conflict with any in-progress reshape work.

### Deferred to Follow-Up Work

- Adaptive icon background color configuration for Android 8+: `flutter_launcher_icons` supports `adaptive_icon_background`; configure in a follow-up once the brand color is confirmed for launcher backgrounds.
- Per-flavor (dev/prod) icon switching via Flutter flavors: the launcher config below wires dev icons; a flavor setup enabling automatic prod switching lives in a future build-config PR.

---

## Context & Research

### Relevant Code and Patterns

- `lib/state/app_data.dart` lines 809–841 — complete Teams filter provider triple (`teamsSearchQueryProvider`, `teamsSportFilterProvider`, `availableSportsProvider`, `filteredTeamsProvider`). Mirror exactly for Video and Match.
- `lib/pages/teams_page.dart` — `_SearchField` (`ConsumerStatefulWidget` with `TextEditingController`), `_SportFilterChips` (horizontal `ListView.separated` at height 32), `_TeamsList` (`WfSection` above `Expanded(ListView)`) — reference implementations for U3, U4, U5.
- `lib/pages/match_page.dart` — `_TopBar.onBack` gating (`isEnded ? onLeave : null`), `_MatchPageState._leave(wasEnded:)`, `_SessionScreen` render path — location of U1 fix.
- `lib/pages/settings_page.dart` — `_NavRow` (lines 703–738), `_UserSection`, `_StreamingSection`, `_DataSection` — patterns for U10–U12 collapse.
- `lib/ble/mock_ble_service.dart` line 273 — `rootBundle.loadString('assets/mock/fixtures/recordings.json')` — fixture consumer 1.
- `lib/db/mock_data_seeder.dart` line 123 — `rootBundle.loadString('assets/mock/fixtures/$name.json')` — fixture consumer 2.
- `lib/theme/tokens.dart` — `T.bg` = `Color(0xFF0A0A0A)` — splash background color.
- `lib/models/team.dart` — `kSports` constant for filter chip label ordering.
- `launcher/` — pre-rendered `icon-dev-*.png` and `icon-prod-*.png` at 16, 24, 32, 48, 64, 96, 192, 512, 1024 px plus foreground variants.

### Institutional Learnings

- `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md` — New UI pages (Settings sub-pages) that gate on camera connection must use `connectionStateProvider`, never `kAppEnv.isDevBackend` as a bypass.
- `docs/solutions/developer-experience/bool-fromEnvironment-default-tied-to-app-env-2026-05-19.md` — Any new dart-define flags (e.g., splash skip) must use `defaultValue: _envName == 'dev'`.

### External References

- `flutter_launcher_icons` package (pub.dev) — generates Android mipmap and iOS AppIcon assets from a single source image; supports `adaptive_icon_foreground` for Android 8+.
- `flutter_native_splash` package (pub.dev) — generates platform splash configs; accepts `background_color` and `image` (PNG); supports `android_12` key for Material You splash.

---

## Key Technical Decisions

- **Mock fixture path stays under `assets/`**: `rootBundle` cannot resolve `lib/` paths. New path: `assets/ble/fixtures/`. `pubspec.yaml` `assets:` entry updated accordingly. Two consumers updated: `mock_ble_service.dart` and `mock_data_seeder.dart`.
- **Splash image: `launcher/icon-dev-1024.png`**: User confirmed. `flutter_native_splash` config points at this file. The SC monogram in the HTML design is consistent with the dev icon.
- **Count labels extracted above `Expanded`**: `WfSection` is currently nested inside `_TeamsList`'s inner `Column` (which is inside the `Expanded`), so it scrolls. The fix moves `WfSection` to be a sibling of `Expanded` in the outer `Column`. Applied to all three list pages.
- **Settings sub-pages are thin shells**: Each sub-page (`UsersSettingsPage`, `DataSettingsPage`, `AppSettingsPage`) is a `Scaffold` with an AppBar and a `ListView` containing the widgets extracted from the parent page. No new state management needed; existing providers are inherited.
- **Filter state is page-local `StateProvider`**: Matching the Teams pattern. No new `ChangeNotifier`, no `AutoDispose` needed — the state intentionally resets when the page is popped.
- **`flutter_launcher_icons` added as `dev_dependency`**: It generates platform files at build-config time and is not a runtime dependency.

---

## Open Questions

### Resolved During Planning

- **Splash image format**: `flutter_native_splash` requires PNG. User confirmed: use `launcher/icon-dev-1024.png`. Resolved.
- **Mock fixtures destination**: Cannot be `lib/`; must stay under `assets/`. New path: `assets/ble/fixtures/`. Resolved.
- **Count label scroll behavior**: Research confirmed `WfSection` is inside `Expanded` and does scroll. Structural change needed. Resolved.

### Deferred to Implementation

- **`assets/mock/mock-video.mp4`**: Audit references during U7. If unreferenced, delete. If still needed by a stub or integration test, move to `assets/ble/mock-video.mp4` and update references.
- **`assets/brand/` directory removal**: After removing the `app_icon.png` reference, confirm no other files remain in `assets/brand/` before removing the directory and its `pubspec.yaml` entry.
- **`flutter_native_splash` Android 12 splash**: The package supports an `android_12` sub-key for the new splash API; decide during implementation whether to configure it or let the package apply its default.

---

## Implementation Units

### U1. Pre-kickoff back navigation on Match session screen

**Goal:** Allow the user to exit the session screen and return to match selection when the match is in `idle` phase (not yet kicked off).

**Requirements:** R1.1, R1.2, R1.3, R1.4, R1.5

**Dependencies:** None

**Files:**
- Modify: `lib/pages/match_page.dart`

**Approach:**
- In `_SessionScreen.build()`, pass `onBack` to `_TopBar` when `state.phase == MatchPhase.idle` (in addition to when `isEnded`). The callback calls `onLeave` (the `_leave(wasEnded: false)` path, which resets `liveMatchProvider` without removing the match from the upcoming list).
- `_TopBar` already accepts a nullable `VoidCallback? onBack`; the back arrow already renders when `onBack != null`. No change to `_TopBar` itself is needed.
- In `_MatchPageState._leave()`, the `wasEnded: false` path skips the `removeMatch` call and resets both `_selected = null` and `_setupConfirmed = false`, returning to `_LandingScreen`. This is existing behaviour; the only change is surfacing the button.
- No confirmation dialog: the match is not started, so there is nothing to lose. Keep it as a direct back action.

**Patterns to follow:**
- `_TopBar.onBack` is already `isEnded ? onLeave : null`; extend the condition to `(isEnded || state.phase == MatchPhase.idle) ? onLeave : null`.

**Test scenarios:**
- Happy path: Given `phase == idle` and `_setupConfirmed == true`, the session screen renders a back arrow. Tapping it returns to `_LandingScreen`; `liveMatchProvider` is reset; the match still appears in the upcoming list.
- Edge case: Given `phase == period`, no back arrow is shown.
- Edge case: Given `phase == periodBreak`, no back arrow is shown.
- Edge case: Given `phase == ended`, a back arrow is shown (existing behavior preserved). Covers AE2.
- Integration: After using back from idle, re-selecting the same match from the landing list and tapping "Start match" again successfully enters setup → session.

**Verification:**
- The back arrow is visible on the session screen immediately after "Start match" is tapped and before "Kickoff" is tapped.
- Tapping back returns to the landing list with the match still present.
- No back arrow appears during an active period.

---

### U2. Filter providers for Video library and Match landing pages

**Goal:** Add the Riverpod `StateProvider` triple and derived filtered provider for both the Video library page and the Match landing page, mirroring the Teams page filter pattern.

**Requirements:** R2.1, R2.2, R2.3, R2.4, R2.6

**Dependencies:** None

**Files:**
- Modify: `lib/state/app_data.dart`

**Approach:**
- After the existing Teams filter block (lines 809–841), add a **Match landing filter block**:
  - `upcomingSearchQueryProvider = StateProvider<String>((_) => '')`
  - `upcomingMatchSportFilterProvider = StateProvider<String?>((_) => null)`
  - `filteredUpcomingMatchesProvider = Provider<List<UpcomingMatch>>` — derives from `upcomingMatchesProvider`; filters by query (team name and opponent) and sport chip
- Add a **Library filter block**:
  - `librarySearchQueryProvider = StateProvider<String>((_) => '')`
  - `librarySportFilterProvider = StateProvider<String?>((_) => null)`
  - `filteredLibraryTeamsProvider = Provider<List<TeamRecord>>` — same derivation as `tiles` in `VideoPage.build()` but after applying search (team name) and sport filter

**Patterns to follow:**
- `filteredTeamsProvider` at `lib/state/app_data.dart` lines 828–841 — exact structure to mirror.
- `availableSportsProvider` for sport set derivation — reuse for library sports by watching library entries' team sport values.

**Test scenarios:**
- Happy path: `filteredUpcomingMatchesProvider` with no query and no sport filter returns all upcoming matches.
- Filter: given a sport filter of "Soccer", only soccer matches are returned.
- Search: given query "Arsenal", only matches where team name or opponent contains "Arsenal" (case-insensitive) are returned.
- Empty: given a search query that matches nothing, the provider returns an empty list.
- Library search: given query "City", only library team entries whose team name contains "City" are returned.
- Library sport filter: given filter "Basketball", only basketball teams are included in library tiles.

**Verification:**
- Providers compile without errors; existing Teams page still works unchanged.
- `filteredUpcomingMatchesProvider` and `filteredLibraryTeamsProvider` exist and are exported.

---

### U3. Search + filter UI on Match landing page

**Goal:** Add a search field and sport filter chip row to `_LandingScreen`, consuming the providers from U2.

**Requirements:** R2.1, R2.2, R2.5, R2.6

**Dependencies:** U2

**Files:**
- Modify: `lib/pages/match_page.dart`

**Approach:**
- In `_LandingScreen.build()`, restructure the `body` `Column` to add:
  1. `Padding` wrapping `_MatchSearchField` (same pill shape as `_SearchField` in teams_page, reading `upcomingSearchQueryProvider`)
  2. `SizedBox(height: 32)` wrapping `_MatchSportFilterChips` (horizontal `ListView.separated`, reading `upcomingMatchSportFilterProvider`)
  3. Existing loading/error/data switch, but the `data` branch reads `filteredUpcomingMatchesProvider` instead of the raw `upcomingMatchesProvider`
- `_MatchSearchField` and `_MatchSportFilterChips` are private widgets defined in `match_page.dart`, following the same `ConsumerStatefulWidget` / `ConsumerWidget` pattern as `_SearchField` / `_SportFilterChips`.
- The "All" chip prepends `null` to the sport list. Sports list derives from the sports present in `upcomingMatchesProvider` results (to avoid empty chips).
- The count label in the `data` branch becomes `WfSection('Upcoming · ${filtered.length}')` where `filtered` is from `filteredUpcomingMatchesProvider`.

**Patterns to follow:**
- `_SearchField` in `lib/pages/teams_page.dart` — exact widget shape.
- `_SportFilterChips` in `lib/pages/teams_page.dart` — exact chip row shape.

**Test scenarios:**
- Happy path: The match landing page renders a search field and filter chips when matches exist. Covers AE3.
- Typing a search query narrows the match list; clearing the field restores all matches. Covers AE4.
- Selecting a sport chip filters the list to that sport; selecting "All" restores all.
- Empty state when filter produces no results shows "No matches match your filters" (matching Teams pattern).
- Widget test: `_LandingScreen` builds without error with `MockBleService` override.

**Verification:**
- Search field and chip row are visible on the Match landing screen.
- Filtering and searching narrow the list in real time.

---

### U4. Search + filter UI on Video library page

**Goal:** Add a search field and sport filter chip row to `VideoPage`, consuming the providers from U2.

**Requirements:** R2.3, R2.4, R2.5, R2.6

**Dependencies:** U2

**Files:**
- Modify: `lib/pages/video_page.dart`

**Approach:**
- Replace the current `body: Column` in `VideoPage.build()` with the same three-part layout: search field, sport filter chips, filtered list.
- Extract the `tiles` computation into `filteredLibraryTeamsProvider` (from U2) consumed via `ref.watch`.
- Replace the `WfNote('Videos saved on this phone')` note — move it inside the empty state, or remove if redundant given the new search/filter header.
- The count label uses the same `WfSection` pattern; placed above `Expanded`.

**Patterns to follow:**
- `_SearchField` / `_SportFilterChips` in `lib/pages/teams_page.dart`.
- `VideoPage._TeamLibraryRow` already handles the tap and row rendering; no change needed.

**Test scenarios:**
- Happy path: Search field and chip row render above the library list.
- Searching by team name narrows the displayed tiles.
- Sport filter chip narrows to teams with that sport.
- No-results case shows appropriate empty state.
- Widget test: `VideoPage` builds without error with mocked providers.

**Verification:**
- Video library page layout matches Teams page visual structure (search, chips, list).

---

### U5. Pin count labels as non-scrolling headers

**Goal:** Ensure `WfSection` count labels ("Your teams · N", "Upcoming · N") do not scroll with list content — they stay fixed above the `ListView`.

**Requirements:** R3.1, R3.2, R3.3, R3.4

**Dependencies:** U3, U4 (to avoid double-editing the same files)

**Files:**
- Modify: `lib/pages/teams_page.dart`
- Modify: `lib/pages/match_page.dart` (already handled in U3 — confirm no duplication)
- Modify: `lib/pages/video_page.dart` (already handled in U4 — confirm no duplication)

**Approach:**
- In `_TeamsList.build()` (teams_page.dart), the current structure is:
  ```
  Column(
    children: [
      WfSection('Your teams · N'),    ← currently INSIDE expanded Column
      Expanded(child: ListView(...)),
    ],
  )
  ```
  The `_TeamsList` widget itself is the `Expanded` child of the outer page `Column`. Because `_TeamsList` returns a plain `Column` (not constrained), the `WfSection` is inside the `Expanded` region and scrolls when the `ListView` is full.
  
  Fix: Move `WfSection` out of `_TeamsList` and into the outer page `Column` in `TeamsPage.build()`:
  ```
  Expanded(
    child: _TeamsList(teams: filtered, totalShown: filtered.length),
  )
  ```
  becomes:
  ```
  if (filtered.isNotEmpty) WfSection('Your teams · ${filtered.length}', ...),
  Expanded(child: _TeamsList(teams: filtered, ...)),
  ```
  where `_TeamsList` no longer renders `WfSection` internally.

- The same structural fix applies to the count label in U3's `_LandingScreen` and U4's `VideoPage`, which must be placed in the outer `Column` above the `Expanded` (not inside the data branch's inner layout).

**Patterns to follow:**
- The `Column > [SearchField, FilterChips, WfSection?, Expanded(ListView)]` layout is the canonical pattern going forward.

**Test scenarios:**
- Widget test: Given a Teams page with 10 teams, the `WfSection` widget is a sibling of the `Expanded` widget in the Column, not a descendant of it. Covers AE5.
- Scrolling the list does not cause the section header to scroll out of view.

**Verification:**
- Count label is visible regardless of scroll position.

---

### U6. Copy updates: phone-local storage framing

**Goal:** Remove copy that implies teams, matches, or recordings live primarily on the camera. Update it to reflect phone-local storage.

**Requirements:** R4.1, R4.2, R4.4

**Dependencies:** None

**Files:**
- Modify: `lib/pages/teams_page.dart`
- Modify: `lib/pages/match_page.dart`
- Modify: `lib/pages/video_page.dart`
- Modify: `lib/pages/settings_page.dart` (audit only; most copy here is correctly camera-gated)

**Approach:**
- Audit every string containing "camera" in the four page files. Change only those that imply camera-side data ownership; leave copy that correctly describes a camera action (connect, record, stream).
- Specific changes (at minimum):
  - `teams_page.dart` `_NoTeamsYet` body: "Teams live on the camera. Add your first one to start recording matches." → "Add your first team to start organising matches."
  - `teams_page.dart` `_confirmDelete` dialog body: "…will be removed from the camera." → "…will be permanently deleted."
  - `match_page.dart` `_NoUpcomingState` body: "Past matches live in the Video and Teams tabs." → "Past matches are in the Video and Teams tabs." (minor but accurate)
  - `video_page.dart` empty state body: "Connect a camera to browse recordings and download them to this phone." → "Record a match to start building your library."
- Settings copy: "Connect a camera to manage users, formats, and streaming destinations." — keep as-is (this is correctly camera-gated functionality).
- Switch-user dialog: "Your teams, matches, and streaming destinations will reload…" — keep as-is (accurate).

**Test scenarios:**
- Widget test: `_NoTeamsYet` widget does not render any string containing "live on the camera".
- Widget test: `_NoVideosEmptyState` body does not contain "Connect a camera to browse".
- Covers AE6.

**Verification:**
- `grep -r "live on the camera" lib/pages/` returns no results.
- `grep -r "removed from the camera" lib/pages/` returns no results.

---

### U7. Mock fixture relocation

**Goal:** Move mock JSON fixtures from `assets/mock/fixtures/` to `assets/ble/fixtures/`, update both consumers and `pubspec.yaml`, and audit `mock-video.mp4`.

**Requirements:** R6.1, R6.2, R6.3, R6.4, R6.5

**Dependencies:** None

**Files:**
- Move: `assets/mock/fixtures/*.json` → `assets/ble/fixtures/` (5 files: matches, players, recordings, streaming_destinations, teams)
- Modify: `lib/ble/mock_ble_service.dart` (line 273 path update)
- Modify: `lib/db/mock_data_seeder.dart` (line 123 path update)
- Modify: `pubspec.yaml` (assets section)
- Audit + delete or move: `assets/mock/mock-video.mp4`

**Approach:**
- Create `assets/ble/fixtures/` directory.
- Move all five JSON fixture files.
- In `mock_ble_service.dart`, change `'assets/mock/fixtures/recordings.json'` → `'assets/ble/fixtures/recordings.json'`.
- In `mock_data_seeder.dart`, change `'assets/mock/fixtures/$name.json'` → `'assets/ble/fixtures/$name.json'`.
- In `pubspec.yaml`, remove `assets/mock/` and `assets/mock/fixtures/` entries; add `assets/ble/fixtures/`.
- For `mock-video.mp4`: search all Dart files for "mock-video". If no references found, delete the file. If referenced, move to `assets/ble/mock-video.mp4` and add to pubspec assets.
- Once `assets/mock/` is empty, remove the directory.
- `assets/brand/` check: search for references to `assets/brand/app_icon.png` in Dart files; if none, remove directory and its pubspec entry (R5.3/R5.4 — can be combined with this unit).

**Test scenarios:**
- `flutter pub get` succeeds after pubspec change.
- Integration test / mock service test: `MockBleService` loads recordings without error from new path.
- `MockDataSeeder` seeds teams, matches, players, and streaming destinations without asset-not-found errors.
- Unit test for `mock_ble_service_test.dart` passes unchanged (path is internal to service).

**Verification:**
- `grep -r "assets/mock" lib/` returns no results.
- `grep -r "assets/mock" pubspec.yaml` returns no results.
- Running `just test` (unit + widget) passes.

---

### U8. App icon replacement

**Goal:** Wire the pre-rendered launcher PNGs into Android and iOS icon slots using `flutter_launcher_icons`.

**Requirements:** R5.1, R5.2, R5.3, R5.5, R5.6

**Dependencies:** U7 (so `assets/brand/` cleanup is done first)

**Files:**
- Modify: `pubspec.yaml` (add `flutter_launcher_icons` dev_dependency; add SVG assets)
- Create: `flutter_launcher_icons.yaml`
- Generated (do not manually edit): `android/app/src/main/res/mipmap-*/ic_launcher.png`, `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

**Approach:**
- Add `flutter_launcher_icons: ^0.14.x` (or latest stable) to `dev_dependencies` in `pubspec.yaml`.
- Add `assets/icon-dev.svg` and `assets/icon-prod.svg` to the `flutter.assets:` list in `pubspec.yaml` (so they can be used in-app if needed).
- Create `flutter_launcher_icons.yaml` at the repo root:
  ```yaml
  flutter_launcher_icons:
    android: "ic_launcher"
    ios: true
    image_path: "launcher/icon-dev-1024.png"
    adaptive_icon_foreground: "launcher/icon-dev-foreground.png"
    adaptive_icon_background: "#0A0A0A"
    min_sdk_android: 21
    remove_alpha_ios: false
  ```
- Run `dart run flutter_launcher_icons` to generate the platform icon files.
- The generated files are committed to the repo.
- `assets/brand/app_icon.png` is removed (if not already done in U7). `assets/brand/` directory is removed if empty.
- Note: prod icon switching is deferred (see Scope Boundaries). The dev icon is the default for all builds until flavor config is added.

**Test scenarios:**
- Test expectation: none — icon generation is a build-time asset step, not a runtime behavior. Visual verification is the appropriate check.

**Verification:**
- `dart run flutter_launcher_icons` exits successfully with no errors.
- Android mipmap directories contain updated `ic_launcher.png` files.
- iOS AppIcon.appiconset contains updated icon images.
- `assets/brand/app_icon.png` no longer exists (or is not referenced).
- Build (`just build-android`) completes without error.

---

### U9. Native splash screen

**Goal:** Implement the native splash screen using `flutter_native_splash`, matching the dark `#0A0A0A` background with the dev icon as the splash image. Delete `splash-screen.html`.

**Requirements:** R7.1, R7.2, R7.3, R7.4, R7.5

**Dependencies:** U8 (launcher PNGs must be present)

**Files:**
- Modify: `pubspec.yaml` (add `flutter_native_splash` dev_dependency and config block)
- Generated (do not manually edit): `android/app/src/main/res/drawable/launch_background.xml`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/`, and related platform splash files.
- Delete: `splash-screen.html`

**Approach:**
- Add `flutter_native_splash: ^2.x` (latest stable) to `dev_dependencies`.
- Add `flutter_native_splash:` config block to `pubspec.yaml`:
  ```yaml
  flutter_native_splash:
    color: "#0A0A0A"
    image: launcher/icon-dev-1024.png
    android_gravity: center
    ios_content_mode: center
    android_12:
      color: "#0A0A0A"
      image: launcher/icon-dev-1024.png
  ```
- Run `dart run flutter_native_splash:create`.
- The generated platform files are committed.
- Delete `splash-screen.html`.
- No `FlutterNativeSplash.remove()` call is needed in `main.dart` unless the app has a visible loading delay that requires preserving the splash (default Flutter behavior removes it when the first frame is rendered).

**Test scenarios:**
- Test expectation: none — splash is a platform asset, not runtime Dart behavior.

**Verification:**
- `dart run flutter_native_splash:create` exits successfully.
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/` contains updated images (no longer the default white Flutter splash).
- `splash-screen.html` does not exist in the repo.
- `git status` shows modified platform files but no untracked `splash-screen.html`.

---

### U10. Settings — Users sub-page

**Goal:** Replace the `_UserSection` inline widget (two cards) in `SettingsPage` with a single `_NavRow` that opens a new `UsersSettingsPage`.

**Requirements:** R8.1, R8.3, R8.7, R8.8

**Dependencies:** None

**Files:**
- Create: `lib/pages/users_settings_page.dart`
- Modify: `lib/pages/settings_page.dart`

**Approach:**
- Create `UsersSettingsPage` as a `ConsumerWidget` `Scaffold`:
  - AppBar title: "Users"
  - Body: `ListView` containing the existing `_UserSection` widget (moved verbatim, no logic changes — only the containing widget changes)
  - `_UserSection` carries all user-switching, picker, and Manage-users-nav logic unchanged
- In `SettingsPage.build()`, replace the `WfSection('User')` + `_UserSection` block with:
  ```
  WfSection('Users')
  WfCard(
    padding: EdgeInsets.zero,
    child: _NavRow(
      leading: Icon(Icons.person_outline),
      label: 'Users',
      badge: activeName,        // active user's name as badge
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UsersSettingsPage()),
      ),
    ),
  )
  ```
  where `activeName` is derived from `ref.watch(activeUserProvider)` + `usersControllerProvider`.

**Patterns to follow:**
- `_NavRow` in `lib/pages/settings_page.dart` lines 703–738 — badge pattern already used for streaming destinations count.
- `ManageUsersPage` push pattern already in `_UserSection`.

**Test scenarios:**
- Widget test: `SettingsPage` (connected) renders a single "Users" nav row in the Users section, not two cards. Covers AE10.
- Widget test: Tapping the "Users" row navigates to `UsersSettingsPage`.
- Widget test: `UsersSettingsPage` renders the user picker and "Manage users" nav row.
- The active user name appears as a badge on the nav row.

**Verification:**
- Settings page (connected) shows one row for Users, not two cards.
- Users sub-page has full functionality of the original `_UserSection`.

---

### U11. Settings — Data sub-page

**Goal:** Replace the `_DataSection` inline widget in `SettingsPage` with a single `_NavRow` that opens a new `DataSettingsPage`.

**Requirements:** R8.1, R8.4, R8.7, R8.8

**Dependencies:** None

**Files:**
- Create: `lib/pages/data_settings_page.dart`
- Modify: `lib/pages/settings_page.dart`

**Approach:**
- Create `DataSettingsPage` as a `ConsumerWidget` `Scaffold`:
  - AppBar title: "Backup & restore"
  - Body: `ListView` containing the existing `_DataSection` widget (moved verbatim — export and restore logic unchanged)
- In `SettingsPage.build()`, replace the `WfSection('Data')` + `_DataSection` block with:
  ```
  WfSection('Data')
  WfCard(
    padding: EdgeInsets.zero,
    child: _NavRow(
      leading: Icon(Icons.storage_outlined),
      label: 'Backup & restore',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DataSettingsPage()),
      ),
    ),
  )
  ```
- Move `_DataSection` and its `_onExportTapped` / `_onRestoreTapped` methods into `data_settings_page.dart`.

**Patterns to follow:**
- Same `_NavRow` → new `Scaffold` pattern as U10.

**Test scenarios:**
- Widget test: `SettingsPage` renders a single "Backup & restore" row in the Data section. Covers AE11.
- Widget test: Tapping the row navigates to `DataSettingsPage`.
- Widget test: `DataSettingsPage` renders Export and Restore rows.

**Verification:**
- Settings page shows one "Backup & restore" row.
- Sub-page contains the full export/restore flows.

---

### U12. Settings — App sub-page

**Goal:** Replace the three-row App section (Theme, Permissions, About) in `SettingsPage` with a single `_NavRow` opening a new `AppSettingsPage`.

**Requirements:** R8.1, R8.5, R8.7, R8.8

**Dependencies:** None

**Files:**
- Create: `lib/pages/app_settings_page.dart`
- Modify: `lib/pages/settings_page.dart`

**Approach:**
- Create `AppSettingsPage` as a `StatelessWidget` `Scaffold`:
  - AppBar title: "App"
  - Body: `ListView` containing the three existing rows (Theme, Permissions, About) with the long-press `DebugPage` gesture on About preserved
- In `SettingsPage.build()`, replace the `WfSection('App')` block (Theme, Permissions, About rows with Dividers) with:
  ```
  WfSection('App')
  WfCard(
    padding: EdgeInsets.zero,
    child: _NavRow(
      leading: Icon(Icons.settings_outlined),
      label: 'App',
      sub: 'Theme, permissions, about',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AppSettingsPage()),
      ),
    ),
  )
  ```

**Patterns to follow:**
- Same `_NavRow` → new `Scaffold` pattern as U10 and U11.
- The `kAppEnv != AppEnv.prod` long-press guard on the About row must be preserved in the sub-page.

**Test scenarios:**
- Widget test: `SettingsPage` renders a single "App" nav row in the App section.
- Widget test: Tapping navigates to `AppSettingsPage`.
- Widget test: `AppSettingsPage` renders Theme, Permissions, and About rows.
- Widget test: About row has the long-press `DebugPage` gesture wired in non-prod builds.

**Verification:**
- Settings main page is significantly shorter (3 sub-page nav rows instead of expanded sections).
- All sub-page content is fully functional.

---

## System-Wide Impact

- **Interaction graph:** `_MatchPageState._leave` is called from `_SessionScreen` via `onLeave`; the new idle-phase back button reuses the same path — no new callbacks introduced.
- **Error propagation:** No changes to error-handling paths; new sub-pages inherit existing error display conventions from their moved widgets.
- **State lifecycle risks:** Settings sub-pages push/pop on the Navigator stack; `StateProvider` filter state in Video/Match pages resets on pop (expected). User picker in `UsersSettingsPage` uses the same providers as before — no new state lifecycle introduced.
- **API surface parity:** Filter providers added in U2 follow the same `StateProvider` + derived `Provider` pattern as Teams; no new abstraction.
- **Integration coverage:** `MockBleService` fixture loading (U7) must be verified via the integration test (`test/integration/main_page_test.dart`) after path changes — this is the cross-layer scenario.
- **Unchanged invariants:** All existing pages (ManageUsersPage, DiagnosticsPage, SportPresetsPage, StreamingDestinationsPage) are unchanged. `_ConnectCameraBanner` connection guard in Settings is preserved in the parent page (not the sub-pages).

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `flutter_launcher_icons` version conflict with existing deps | Pin to `^0.14.0`; run `flutter pub get` and check for conflicts before generating |
| `flutter_native_splash` generated files differ per Flutter version | Commit generated files; note in PR that regeneration is needed if Flutter SDK is upgraded |
| Settings sub-page `_DataSection` depends on `context` for Navigator push after `await` | The `if (!context.mounted) return` guard is already present in the export/restore methods; preserve it exactly when moving to `DataSettingsPage` |
| Mock fixture path changes break integration test | Update `test/integration/main_page_test.dart` if it references fixture paths directly |
| WfSection count-label extraction in `_TeamsList` may require passing count to outer page | Extract the count from `filteredTeamsProvider` in `TeamsPage.build()` and pass to both `WfSection` and `_TeamsList`; remove `totalShown` param from `_TeamsList` or keep for list-internal use |

---

## Sources & References

- **Origin document:** [`docs/brainstorms/ui-polish-sprint-requirements.md`](docs/brainstorms/ui-polish-sprint-requirements.md)
- Related plan: [`docs/plans/2026-05-05-002-feat-settings-ui-reshape-plan.md`](docs/plans/2026-05-05-002-feat-settings-ui-reshape-plan.md) — prior settings work; U10–U12 must not conflict
- Teams filter pattern: `lib/state/app_data.dart` lines 809–841
- Teams page UI reference: `lib/pages/teams_page.dart`
- Settings `_NavRow` pattern: `lib/pages/settings_page.dart` lines 703–738
- Conventions: `docs/solutions/conventions/isdevbackend-must-not-bypass-connection-state-guards-2026-05-19.md`
