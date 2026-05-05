---
title: "feat: Settings UI reshape (compact user, streaming page, sport filter)"
type: feat
status: active
date: 2026-05-05
origin: docs/brainstorms/settings-page-reshape-requirements.md
---

# feat: Settings UI reshape (compact user, streaming page, sport filter)

## Summary

The data layer and page shell from the earlier reshape plan (001) are complete. This plan re-shapes three sections whose UI did not match the revised requirements: the User section becomes a compact dropdown-plus-add row with a "Manage users" nav destination; the Streaming Setup section becomes a nav row that opens a new `StreamingDestinationsPage`; and the Sport setups page gains sport filter chips, an inline single-line row layout, and teams-page visual parity.

---

## Problem Frame

Post-implementation review identified three UI shape mismatches against the updated requirements:

1. The User section renders a large expanded card listing every user. R7 calls for a compact inline dropdown with an "Add user" action and a separate nav path for delete operations.
2. The Streaming Setup section renders all destinations inline on the Settings page. R17 calls for a compact nav row (with count badge) opening a dedicated destinations page.
3. The Sport setups page lacks sport filter chips (R14), uses a two-line stacked row layout instead of the required inline single-line row (R15), and its visual density does not match the Teams page (R16).

See origin: `docs/brainstorms/settings-page-reshape-requirements.md` for the full problem frame.

---

## Requirements

- R7. User section is compact: active user name + inline dropdown to switch + "Add user" action.
- R8. Active user can be switched from the Settings page inline (no navigation).
- R9. Add user accessible directly from the Settings page via bottom-sheet form.
- R10. Delete user accessible from a "Manage users" nav destination; delete rules (active / last / live-match blocks) preserved.
- R14. Sport setups page shows a sport filter chip row at the top (matching Teams page pattern).
- R15. Each preset row is inline (single line): `[Default chip — only if built-in]  name  format-summary`. Sport label is in the section header, not the row name. Format summary is muted monospace at the trailing end.
- R16. Sport setups page visual style matches the Teams page (filter bar treatment, row density, typography).
- R17. Streaming Setup section is a compact nav row opening a Streaming destinations page. Nav row shows a count badge when destinations exist.
- R21. Add / edit / delete streaming destinations from the Streaming destinations page (behavior unchanged from current implementation).

**Origin actors:** A1 (camera operator, phone-side), A2 (ScoutCamera, camera-side).
**Origin flows:** F3 (switch active user), F4 (add known-provider destination), F5 (add custom destination).
**Origin acceptance examples:** AE3 (R7/R8), AE4 (R9/R10), AE5 (R12/R13/R15), AE6 (R14), AE7 (R17).

---

## Scope Boundaries

- Data layer, `BleService` interface, `DevDataStore`, and Riverpod providers — no changes.
- `user_form_sheet.dart`, `streaming_destination_form_sheet.dart` — no changes.
- Camera section, empty state, App section — no changes.
- Delete-rule semantics (R10 active / last / live-match blocks) — behavior preserved as-is, only the page surface that exposes them changes.
- Sport setups page content (built-in vs custom logic, `SportPreset` model, `BleService` sport preset methods) — only the presentation layer changes.

---

## Context & Research

### Relevant Code and Patterns

- `lib/pages/settings_page.dart` — User section (`_UserSection`, `_ActiveUserCard`, `_NoActiveUserCard`, `_OtherUserRow`) and Streaming section (`_StreamingSection`, `_DestinationRow`) to be reshaped.
- `lib/pages/sport_presets_page.dart` — Sport setups page; `_PresetRow` to be made inline; filter chips to be added.
- `lib/pages/teams_page.dart` — Reference for `_SportFilterChips` pattern (`WfChip` list, `ListView.separated` horizontal, `availableSportsProvider`, `teamsSportFilterProvider`), `_SearchField` treatment, row density, typography.
- `lib/pages/manage_users_page.dart` — Does not exist yet; will mirror the shell of `sport_presets_page.dart`.
- `lib/pages/streaming_destinations_page.dart` — Does not exist yet; will receive the `_StreamingSection` / `_DestinationRow` logic.
- `lib/state/app_data.dart` — `teamsSportFilterProvider` and `availableSportsProvider` patterns to follow for `sportPresetsFilterProvider`.
- `lib/models/team.dart` — `kSports` constant; source for filter chip options.
- `lib/widgets/wf_card.dart`, `lib/widgets/wf_chip.dart`, `lib/theme/tokens.dart` — visual primitives.
- `test/pages/settings_user_section_test.dart` — needs update for new shape.
- `test/pages/settings_streaming_section_test.dart` — needs update for new shape.
- `test/pages/sport_presets_built_in_test.dart` — needs update for inline row + filter.
- `test/integration/settings_page_test.dart` — AE3/AE4/AE6/AE7 paths need update.

### Institutional Learnings

None — `docs/solutions/` does not exist in this repo.

---

## Key Technical Decisions

- **Dropdown widget for inline user switch: `PopupMenuButton`-based row, not a native `DropdownButton`.** The OS-native `DropdownButton` renders with default material chrome that clashes with the dark `WfCard` aesthetic; a `PopupMenuButton` on the active-user row gives the same list-of-options UX with full dark-theme control. A user tap opens the popup, each item is a `PopupMenuItem<UserRecord>`, selecting one calls `usersController.setActive`. (See also: "Deferred to Implementation" in original plan 001 — this resolves that deferral.)
- **"Manage users" page is a full Scaffold, not a bottom sheet.** R10 describes a nav destination, not a modal. A `Scaffold` with `AppBar` mirrors `sport_presets_page.dart` and keeps the delete-rule UX (disabled icon + subtitle) visible without cramping. No FAB — add user happens from the Settings page (R9).
- **`StreamingDestinationsPage` is a new file extracting current inline logic.** The `_StreamingSection` card body, `_DestinationRow`, and the `_onAdd`/`_onEdit`/`_onDelete` handlers in `settings_page.dart` move verbatim into a new page file; no behavior changes. The settings page replaces that block with a single nav row.
- **`sportPresetsFilterProvider` lives in `app_data.dart` alongside `teamsSportFilterProvider`.** Consistent location; the two filter providers have the same shape (`StateProvider<String?>`). Filter chip options come from `kSports` directly (every sport has at least one built-in) rather than deriving from loaded preset data.
- **Sport preset row name is not modified at the data layer.** Built-in preset names like "Standard" already don't carry the sport prefix (that was added by the old row renderer). The row change is purely visual: remove the sport-prefixed text from the row and render `[Default chip?] name  summary` inline on one line.

---

## Open Questions

### Resolved During Planning

- *Does the "Manage users" nav show up only when delete is the intent, or is switching also possible there?* — Page shows all users with active badge; tapping a non-active user row from this page switches to them (same dialog + confirmation as current). This makes the page useful even if the inline dropdown handles quick switching — both surfaces remain consistent.
- *Where do sport filter options come from?* — `kSports` directly; every sport has at least one built-in preset after the U2 seed in plan 001.
- *Does the Streaming nav row count badge come from the controller's loaded data?* — Yes: `streamingDestinationsControllerProvider.value?.length ?? 0`. When loading, no badge is shown (same as showing 0).

### Deferred to Implementation

- Exact `PopupMenuButton` vs `InkWell`-on-row + `showMenu` choice for the user dropdown — both satisfy R7/R8. Pick whichever avoids menu-position jank at the card's edge during U1.
- Whether the "Manage users" page AppBar has a subtitle or a count badge. Minor presentation detail.
- Whether `_SportFilterChips` on the sport presets page uses a `SizedBox(height: 32)` wrapper (matching teams page exactly) or a slightly different vertical rhythm. Visual review during U3.

---

## Implementation Units

- U1. **User section compact reshape**

**Goal:** Replace `_ActiveUserCard`, `_NoActiveUserCard`, `_OtherUserRow` in `settings_page.dart` with a compact `WfCard` containing an inline user selector row (active name + dropdown indicator) and an "Add user" row. A "Manage users" nav row below the card opens the page built in U2.

**Requirements:** R7, R8, R9.

**Dependencies:** U2 (for the "Manage users" nav row push; the nav row can render before U2 is written — it just won't have a destination yet during development).

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Test: `test/pages/settings_user_section_test.dart`

**Approach:**
- Remove `_ActiveUserCard`, `_NoActiveUserCard`, `_OtherUserRow` widget classes.
- New `_UserSection` renders a `WfCard(padding: EdgeInsets.zero)` with two rows separated by a `Divider`:
  - **Active user row:** leading `Icon(Icons.person_outline)`, active user name (or "No user" in the null-active-user state), trailing `PopupMenuButton` with one `PopupMenuItem<UserRecord>` per user. Selected item calls `usersController.setActive`. Confirmation dialog for switching is preserved (same copy from U8 of plan 001). The row is tappable (the `PopupMenuButton` is the entire trailing zone).
  - **Add user row:** `Icon(Icons.person_add_outlined)` + "Add user" label, taps to open `showUserFormSheet`.
- Below the `WfCard`, a second `WfCard(padding: EdgeInsets.zero)` holds a `_NavRow` "Manage users" → that pushes `ManageUsersPage` (built in U2).
- No-active-user state: the active user row shows a `WfNote("Pick a user")` in place of the name; the dropdown still lists all users with "Make active" semantics (first selection sets active). The "Add user" row remains.
- Loading / error states for `usersControllerProvider` retain the existing spinner/error card treatment.

**Patterns to follow:**
- Existing `_NavRow` widget in `lib/pages/settings_page.dart` (already present — the "Sport setups" nav row uses it).
- `lib/pages/sport_preset_form_sheet.dart` / `lib/pages/user_form_sheet.dart` for the bottom-sheet invocation pattern.

**Test scenarios:**
- **Covers AE3.** Happy path: with two seed users (A active, B not), the User section card shows user A's name with a dropdown indicator; opening the dropdown lists both users; selecting B triggers the switch dialog with correct copy; confirming switches active user inline and the card re-renders with B's name.
- Happy path: tapping "Add user" opens the bottom sheet; submitting a non-empty name adds the user and it appears in the next dropdown open.
- Happy path: "Manage users" nav row is present below the user card and navigates to `ManageUsersPage`.
- Edge case: with `activeUserProvider` null, the active user row shows the "Pick a user" note; the dropdown still lists users with make-active semantics.
- Edge case: loading state — card renders a spinner; no crash when users not yet loaded.
- Error path: `setActive` throws → `SnackBar` "Couldn't switch user — try again." appears; active user row does not change.

**Verification:**
- `just test test/pages/settings_user_section_test.dart` passes.
- `_ActiveUserCard`, `_NoActiveUserCard`, `_OtherUserRow` class names no longer exist in `settings_page.dart`.

---

- U2. **`ManageUsersPage` — full-page user management with delete rules**

**Goal:** New page (nav destination from U1's "Manage users" row) listing all users with active badge, switch affordance, and delete affordance following the R10 disable rules.

**Requirements:** R10 (delete path), R8 (switch also available from this page).

**Dependencies:** U1 (nav row that pushes this page; the page is functional independently).

**Files:**
- Create: `lib/pages/manage_users_page.dart`
- Test: `test/pages/manage_users_page_test.dart`

**Approach:**
- Scaffold with `AppBar(title: Text('Manage users'))`, `backgroundColor: T.bg`.
- Body: `usersControllerProvider.when(...)` — loading spinner, error text, data → `ListView`.
- Each row: `InkWell` wrapping a `Padding` row with leading `Icon(Icons.person_outline)`, user name + optional "Active" `WfChip`, a trailing `IconButton(Icons.delete_outline)`.
  - Tapping the row (non-active user): opens the switch dialog (same copy/rules as current code in `settings_page.dart`) → calls `usersController.setActive`.
  - Tapping the row (active user): no-op (or light visual disabled treatment).
  - Delete icon disabled + inline subtitle under name for the same three conditions as current `_OtherUserRow`:
    - Last remaining user → "Add another user before deleting the last one"
    - Active user → "Switch to another user before deleting"
    - Live match in progress → "End the live match before deleting"
  - Confirmed delete: same destructive `AlertDialog` with cascade enumeration body.
- No FAB — add user remains on the Settings page (R9).
- After any mutation, the controller refreshes — page rerenders.

**Patterns to follow:**
- `lib/pages/sport_presets_page.dart` — Scaffold + `AsyncNotifier.when` body + `InkWell` rows + `AlertDialog` confirm.
- Existing `_OtherUserRow` delete-rule logic in `lib/pages/settings_page.dart` — carry the disable conditions and subtitle copy verbatim.

**Test scenarios:**
- **Covers AE4.** Happy path: page renders both seed users; active user row shows "Active" chip; its delete icon is disabled with subtitle "Switch to another user before deleting".
- Happy path: tapping a non-active user row opens the switch dialog with correct copy; confirming switches active user (chip moves to the tapped row).
- Happy path: confirming delete of a non-active, non-last user opens the cascade dialog body containing "teams, match history, sport setups, and streaming destinations"; confirming removes the row.
- Edge case: with only one user, both the active-user and the last-user disable rules fire on the same row; subtitle says "Add another user before deleting the last one" (last-user takes precedence over active-user).
- Error path: `setActive` throws → `SnackBar` appears; row does not change.
- Edge case: delete blocked while live match in progress — subtitle "End the live match before deleting"; icon disabled.

**Verification:**
- `just test test/pages/manage_users_page_test.dart` passes.
- No delete or switch logic remains in the User section within `settings_page.dart` — it lives exclusively in `manage_users_page.dart`.

---

- U3. **Sport setups page: filter chips + inline row + teams-page visual parity**

**Goal:** Add a `sportPresetsFilterProvider` and a `_SportFilterChips` widget to `sport_presets_page.dart`; replace the two-line stacked `_PresetRow` with an inline single-line row matching R15; update visual density to match the Teams page.

**Requirements:** R14, R15, R16.

**Dependencies:** None (standalone page change).

**Files:**
- Modify: `lib/pages/sport_presets_page.dart`
- Modify: `lib/state/app_data.dart`
- Test: `test/pages/sport_presets_built_in_test.dart`

**Approach:**
- **Provider:** Add `sportPresetsFilterProvider = StateProvider<String?>((_) => null)` to `app_data.dart`, alongside `teamsSportFilterProvider`. Filter options come from `kSports` (not derived from loaded data, since every sport has a built-in).
- **Filter chips:** New `_SportFilterChips` widget mirroring `teams_page.dart`'s `_SportFilterChips`: a `SizedBox(height: 32)` wrapping a horizontal `ListView.separated` of `WfChip` items from `[null, ...kSports]`, where `null` = "All". Active chip uses `WfChip(active: true)`.
- **Page layout:** Replace the current `ListView` in the `data` branch with a `Column`:
  - `SizedBox(height: 32, child: _SportFilterChips())` pinned above the list.
  - `Expanded(child: ListView(...))` for the preset rows.
- **Filter application:** In `_groupBySport`, pre-filter the preset list by `sportPresetsFilterProvider` before grouping. When a sport is selected, only that sport's group renders; the "All" selection shows all groups.
- **`_PresetRow` inline layout:** Single `Row` with no inner `Column`. Layout left to right:
  - If `preset.builtIn`: `WfChip(label: 'Default')` + `SizedBox(width: 8)`.
  - `Expanded(child: Text(preset.name, ...))` — name with no sport prefix.
  - `SizedBox(width: 8)`.
  - `Text(preset.summary, style: mono muted)` — e.g., "2 × 35 min".
  - If not `preset.builtIn`: trailing `IconButton(Icons.delete_outline)`.
- Typography matches the Teams page team-row style: name at `fontSize: 14, fontWeight: w500, color: T.ink`; summary at `fontFamily: T.mono, fontSize: 11, color: T.ink2`.
- Vertical padding per row: `EdgeInsets.symmetric(horizontal: 14, vertical: 12)` — same as current.

**Patterns to follow:**
- `lib/pages/teams_page.dart` `_SportFilterChips` widget — chip list, filter state, horizontal scroll.
- `lib/pages/teams_page.dart` team row density (single-line, `fontSize: 14`, `fontWeight: w500`).
- `lib/widgets/wf_chip.dart` for both the filter chips and the "Default" badge.

**Test scenarios:**
- **Covers AE5.** Happy path: soccer group built-in rows render with a `WfChip(label: 'Default')` and no delete icon; custom soccer rows have no chip and carry a delete icon.
- **Covers AE5 (inline).** Happy path: a built-in preset row is a single `Row` — no nested `Column`; the name and format summary are on the same horizontal line.
- **Covers AE6.** Happy path: selecting "Soccer" in the filter chips renders only the Soccer group; switching to "All" restores all groups.
- Happy path: every `kSports` entry has at least one row after seed (regression guard).
- Edge case: selecting a sport with no custom presets still renders its built-in(s) under the sport header.
- Edge case: `sportPresetsFilterProvider` is null ("All") by default on page open.
- Error path: attempting to delete a built-in via the controller surfaces the store-level exception (regression guard from plan 001's U2).

**Verification:**
- `just test test/pages/sport_presets_built_in_test.dart` passes.
- `grep "Column" lib/pages/sport_presets_page.dart` does not appear inside `_PresetRow.build` — the row is a flat `Row`.

---

- U4. **Streaming section → nav row + `StreamingDestinationsPage`**

**Goal:** Replace the inline `_StreamingSection` card in `settings_page.dart` with a compact nav row (count badge when destinations exist). Extract `_StreamingSection`, `_DestinationRow`, and their handlers into a new `streaming_destinations_page.dart`.

**Requirements:** R17, R21.

**Dependencies:** None (standalone extraction; `streamingDestinationsControllerProvider` already exists).

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Create: `lib/pages/streaming_destinations_page.dart`
- Test: `test/pages/settings_streaming_section_test.dart`
- Test: `test/pages/streaming_destinations_page_test.dart`

**Approach:**
- **Settings page streaming section:** Replace `_StreamingSection` widget reference with a `WfCard(padding: EdgeInsets.zero)` nav row:
  - Leading: `Icon(Icons.stream)` or `Icon(Icons.cast)`.
  - Label: "Streaming destinations".
  - Trailing: if `streamingDestinationsControllerProvider.value?.isNotEmpty == true`, a `Text('${n} destinations', style: TextStyle(color: T.ink2, fontSize: 12))` badge before the chevron; otherwise just the chevron.
  - `onTap`: push `StreamingDestinationsPage`.
- **Remove from `settings_page.dart`:** `_StreamingSection`, `_DestinationRow`, `_onAdd`, `_onEdit`, `_onDelete` that belonged to the streaming section.
- **`streaming_destinations_page.dart`:** New `ConsumerWidget` (or `ConsumerStatefulWidget` if needed) with:
  - `Scaffold(appBar: AppBar(title: Text('Streaming destinations')), backgroundColor: T.bg)`.
  - Body: `streamingDestinationsControllerProvider.when(...)` — loading spinner, error text, data → the same `WfCard` list structure from the old `_StreamingSection`.
  - FAB: `FloatingActionButton` matching the `sport_presets_page.dart` FAB style — square corners, `T.accent` background, `Icons.add` — calls `_onAdd`.
  - Destination rows: `_DestinationRow` moved verbatim; tap to edit, trailing delete icon.
  - Empty state: same `WfNote("No streaming destinations yet...")` inside the card, but without the "Tap below to add one" copy since the FAB handles add.
  - Error handling: same `SnackBar` patterns for create / edit / delete failures.

**Patterns to follow:**
- `lib/pages/sport_presets_page.dart` — full page structure, FAB, `when(...)` body, empty-state card.
- Existing `_StreamingSection` and `_DestinationRow` in `lib/pages/settings_page.dart` — copy the logic verbatim; only the container changes.

**Test scenarios:**
- **Covers AE7.** Happy path: with two seed destinations for the active user, the Settings page streaming section nav row shows "2 destinations" badge; tapping it navigates to `StreamingDestinationsPage` which lists both rows.
- Happy path: with zero destinations, the nav row shows no count badge (or "0 destinations" — pick the cleaner option during implementation, likely no badge); `StreamingDestinationsPage` shows the empty-state note.
- Happy path: tapping the FAB on `StreamingDestinationsPage` opens `showStreamingDestinationFormSheet`; submitting a valid YouTube destination adds a row and updates the nav row badge count back on Settings.
- Happy path: tapping a destination row opens the form sheet in edit mode; saving updates the row in place.
- Happy path: tapping the delete icon on a destination row, confirming, removes the row.
- Edge case: `streamingDestinationsControllerProvider` in loading state — nav row shows no badge; page body shows a spinner.
- Integration scenario: destination created under user A is not visible in `StreamingDestinationsPage` after switching to user B (nav row badge also updates).

**Verification:**
- `just test test/pages/settings_streaming_section_test.dart test/pages/streaming_destinations_page_test.dart` passes.
- `_StreamingSection`, `_DestinationRow` class names no longer appear in `settings_page.dart`.
- `grep "_StreamingSection\|_DestinationRow" lib/pages/settings_page.dart` returns nothing.

---

- U5. **Integration test and existing test updates**

**Goal:** Update `settings_page_test.dart` (integration) and any existing unit tests that assert the old User / Streaming inline shapes so they pass against the new widget structure.

**Requirements:** AE3, AE4, AE6, AE7.

**Dependencies:** U1, U2, U3, U4.

**Files:**
- Modify: `test/integration/settings_page_test.dart`
- Modify: `test/pages/settings_user_section_test.dart` (if still present after U1 rewrites it)
- Modify: `test/pages/settings_streaming_section_test.dart` (if still present after U4 rewrites it)

**Approach:**
- In `settings_page_test.dart`, update the F3 / AE3 scenario to find the dropdown on the Settings page (not an expanded card) and select user B, then verify the Teams tab update.
- Update the AE4 scenario to push `ManageUsersPage` from the nav row, find the delete affordance there, and assert the cascade dialog body.
- Update the AE6 scenario to assert filter chips are present on `SportPresetsPage` and that selecting "Soccer" hides non-soccer rows.
- Update the AE7 scenario to tap the streaming nav row and land on `StreamingDestinationsPage`, then verify the destination list.
- Any test that previously found `_ActiveUserCard`, `_OtherUserRow`, `_StreamingSection` widgets or their child text / icons by old structure should be updated to navigate to the new widget shapes.

**Patterns to follow:**
- `test/integration/main_page_test.dart` — full-app `ProviderScope` override + `WidgetTester.pumpAndSettle` pattern.
- `test/integration/settings_page_test.dart` existing scenarios — extend, don't rewrite from scratch.

**Test scenarios:**
- **Covers AE3.** Integration: Settings page User section shows active user A in a compact row with a popup indicator; tap → popup lists users → select B → switch dialog → confirm → A is no longer highlighted; Teams tab shows B's data.
- **Covers AE4.** Integration: tap "Manage users" nav row → `ManageUsersPage` opens; active user's delete icon is disabled; switch to user B → delete user A → cascade dialog body contains the four collection names; A's row is gone.
- **Covers AE6.** Integration: push `SportPresetsPage` → filter chip "Soccer" present; tap it → only soccer rows remain; tap "All" → all groups return.
- **Covers AE7.** Integration: streaming nav row on Settings shows count badge "2 destinations" (seed); tap → `StreamingDestinationsPage` opens with two rows; tap FAB → add a destination → badge updates to 3 when navigating back.

**Verification:**
- `just test-integration` passes.
- `just test` passes (all unit + widget tests).
- `just analyze` is clean.

---

## System-Wide Impact

- **Interaction graph:** No new provider fan-out. `sportPresetsFilterProvider` is a local UI state provider — it does not affect data fetch providers. All other providers are unchanged.
- **Unchanged invariants:** `streamingDestinationsControllerProvider`, `usersControllerProvider`, `sportPresetsControllerProvider`, `BleService` interface, `DevDataStore` — none are modified. The extract of `_StreamingSection` to `StreamingDestinationsPage` is a pure presentation move.
- **Error propagation:** Unchanged. Delete-rule exceptions from `UsersController.delete` still surface as `SnackBar`s in the new page.
- **State lifecycle risks:** `sportPresetsFilterProvider` is global; it persists across navigations within the session. Filter selection from a previous visit to the Sport setups page will still be selected on re-entry. This is consistent with how `teamsSportFilterProvider` behaves on the Teams page — acceptable.
- **Navigation depth:** Settings → Sport setups (existing), Settings → Manage users (new), Settings → Streaming destinations (new). Both new pages are simple leaf nodes with no further push.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `PopupMenuButton` for user switch may mis-position near the card edge on narrow devices. | U1 defers exact popup trigger placement to implementation; visual review before merge. |
| `sportPresetsFilterProvider` persisting across navigations may confuse returning users. | Consistent with `teamsSportFilterProvider`; acceptable for v1. Reset on page dispose if it becomes a reported issue. |
| Extracting `_StreamingSection` to a new file may silently break the `SnackBar` scaffold context — `ScaffoldMessenger.of(context)` requires a `Scaffold` ancestor. | `StreamingDestinationsPage` has its own `Scaffold`; the context inside its callbacks will have a valid `Scaffold` ancestor. No risk. |
| Existing `settings_user_section_test.dart` assertions on old widget class names will fail until U1 updates them. | U5 updates the tests; the two units should land together in the same commit or sequential commits. |

---

## Sources & References

- **Origin document:** `docs/brainstorms/settings-page-reshape-requirements.md`
- **Prior plan:** `docs/plans/2026-05-05-001-feat-settings-page-reshape-plan.md`
- User section current implementation: `lib/pages/settings_page.dart` (`_ActiveUserCard`, ~line 642)
- Streaming section current implementation: `lib/pages/settings_page.dart` (`_StreamingSection`, ~line 952)
- Sport presets page: `lib/pages/sport_presets_page.dart`
- Teams page filter chip reference: `lib/pages/teams_page.dart` (`_SportFilterChips`, ~line 258)
- Filter provider reference: `lib/state/app_data.dart` (`teamsSportFilterProvider`, ~line 602)
- Sport list: `lib/models/team.dart` (`kSports`)
- Visual primitives: `lib/widgets/wf_card.dart`, `lib/widgets/wf_chip.dart`, `lib/theme/tokens.dart`
