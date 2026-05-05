---
date: 2026-05-05
topic: settings-page-reshape
---

# Settings page reshape

## Summary

Reshape the Settings tab into four sections — Camera (with diagnostics and disconnect folded in), User (camera-side operator profiles for organizing data), Match Setup (game formats per sport, extending the existing Sport setups), and Streaming Setup (per-user destinations across RTMP/RTMPS/RTSP) — with the App cluster anchored at the bottom and a full-screen "no camera" empty state matching Match and Teams.

---

## Problem Frame

Today's Settings tab carries cards that don't belong: Recording defaults are already controlled per-match in the Match flow, the Connectivity card exposes BLE/WiFi toggles that aren't actually optional (BLE is the only command channel; WiFi-AP is the only download path), and the "Connect a different camera" row implies multi-camera support that doesn't exist (the app pairs to one camera at a time). The page also has no notion of a User, even though all camera-stored data — teams, rosters, match history, and now streaming destinations — is meant to be segmented by who owns it. And when no camera is connected, the page still renders a half-functional list of settings rather than steering the user toward the one action that matters.

Two new capabilities also need a home. Operators want to keep multiple identities organized on a single camera (one camera shared across coaches or programs), and they want to configure live-streaming destinations per identity so they can go live to YouTube / TikTok / Facebook / Instagram, plus self-managed RTMP and RTSP endpoints, without re-typing keys per match.

---

## Actors

- A1. Camera operator (phone-side): the person holding the phone, paired to one camera over BLE. Picks the active user, manages teams/matches/streams under that user, and runs matches. The only human actor in this tab.
- A2. ScoutCamera (camera-side): owns persistent state — users, teams, matches, streaming destinations. All segmentation lives here; the phone is a thin client.

---

## Key Flows

- F1. Connect from empty state
  - **Trigger:** A1 opens Settings with no camera connected.
  - **Actors:** A1, A2.
  - **Steps:** Settings renders the full-screen "No camera connected" prompt (same shape as Match/Teams). A1 taps "Connect camera". The app pushes the existing scan & pair flow. A1 selects a camera and pairs.
  - **Outcome:** Settings renders the full four-section layout, scoped to the camera's currently active user.
  - **Covered by:** R1, R2.

- F2. Disconnect and reconnect
  - **Trigger:** A1 taps "Disconnect" on the connected-camera card.
  - **Actors:** A1, A2.
  - **Steps:** App drops the BLE link. Settings re-renders the empty state. A1 taps "Connect camera"; the app reconnects to the last-known camera in one tap, without rescanning.
  - **Outcome:** Same camera, same active user, same data. The disconnect was a transport pause, not a re-pair.
  - **Covered by:** R3, R4.

- F3. Switch active user
  - **Trigger:** A1 taps the active-user row in the User section and picks a different user.
  - **Actors:** A1, A2.
  - **Steps:** App tells the camera to set the active user. App reloads camera-scoped state (teams, matches, streaming destinations).
  - **Outcome:** Every tab now shows the chosen user's data; the prior user's data is untouched on the camera.
  - **Covered by:** R8, R9.

- F4. Add a streaming destination for a known provider
  - **Trigger:** A1 taps "Add destination" in the Streaming Setup section.
  - **Actors:** A1, A2.
  - **Steps:** App shows a form. A1 picks a provider (YouTube / TikTok / Facebook / Instagram). Protocol is fixed to RTMP for these providers. A1 enters a name (defaulted from provider), URL, and stream key. A1 saves.
  - **Outcome:** Camera persists the destination under the active user; it appears in the Streaming Setup list and becomes selectable in the Match setup screen.
  - **Covered by:** R14, R15, R16, R17.

- F5. Add a streaming destination for a custom platform
  - **Trigger:** A1 taps "Add destination" and picks "Custom".
  - **Actors:** A1, A2.
  - **Steps:** A1 picks a protocol from {RTMP, RTMPS, RTSP}. The form's fields adapt: RTMP/RTMPS asks URL + stream key; RTSP asks URL + optional username + optional password. A1 names the destination and saves.
  - **Outcome:** Same as F4, but provider is recorded as "custom" and the protocol field carries the choice.
  - **Covered by:** R14, R15, R17, R18.

---

## Requirements

**Empty state**
- R1. When no camera is connected, the Settings tab renders a full-screen "No camera connected" prompt with a single primary "Connect camera" CTA. No section cards are visible.
- R2. The empty state visually matches the existing Match and Teams empty states (same icon, copy register, button shape) so the three tabs feel like one product when no camera is paired.

**Camera section (top of populated Settings)**
- R3. The connected-camera card shows the camera's display name, firmware version, proto version, and a connection indicator dot.
- R4. The card exposes three actions: Reboot, Update firmware, Disconnect. Disconnect drops the BLE link only — the camera stays in the known list and one tap on "Connect camera" reconnects it without rescanning.
- R5. The Camera section also exposes a "Diagnostics" row (inside or directly below the camera card, visually grouped with it) that opens the existing Diagnostics page unchanged.
- R6. The "Connect a different camera" row is removed. The single-camera model is the contract.

**User section**
- R7. The User section is compact: it shows the active user's name with an inline dropdown selector to switch users, and an "Add user" action (inline button or + icon). All camera-stored data on every tab is scoped to the active user.
- R8. The user can switch the active user via the inline dropdown on the Settings page without navigating away. Switching causes the app to reload teams, matches, and streaming destinations to reflect the new user's data.
- R9. The user can add a new user directly from the User section on the Settings page via a bottom-sheet form (matching the existing team / sport-preset form-sheet pattern). Minimum field: a display name.
- R10. The user can delete a user from a "Manage users" nav destination (a nav row in the User section opens it). Deleting a non-active user is a single confirm step. Deleting the active user is blocked with an inline message until another user is selected; deleting the last user on the camera is blocked outright.

**Match Setup section (Game Formats)**
- R11. The Match Setup section is a nav row that opens the Sport setups page; the page is the canonical home for game formats.
- R12. Each sport has one or more built-in default formats that appear at the top of that sport's group, marked with a "Default" chip, and are read-only (cannot be edited or deleted).
- R13. The user can add, edit, and delete custom formats per sport. Custom formats appear under the built-ins for the same sport and have edit/delete affordances.
- R14. The Sport setups page shows a sport filter chip row at the top (matching the Teams page pattern) so the user can narrow the list to one sport.
- R15. Each preset row is rendered inline (single line): `[Default chip — only if built-in]  name  format-summary`. The sport label is the section header and is not repeated in the row name. The format summary (e.g. `2 × 35 min`) renders in a muted monospace style at the trailing end of the row.
- R16. The Sport setups page visual style matches the Teams page (search/filter bar treatment, row density, typography).

**Streaming Setup section**
- R17. The Streaming Setup section is a compact nav row that opens a Streaming destinations page (mirrors the Sport setups nav row pattern). The nav row shows a count badge (e.g. "3 destinations") when destinations exist.
- R18. A streaming destination is identified by `{ name, provider, protocol, config }` where `provider ∈ {youtube, tiktok, facebook, instagram, custom}`, `protocol ∈ {rtmp, rtmps, rtsp}`, and `config` is a protocol-specific record. Destinations live on the camera; the phone fetches them per active user.
- R19. For provider in {youtube, tiktok, facebook, instagram}, the protocol is fixed to RTMP and the form prompts for a URL and a stream key.
- R20. When provider is "custom", the user picks the protocol; the form's fields adapt: RTMP and RTMPS prompt for URL + stream key; RTSP prompts for URL + optional username + optional password.
- R21. The user can add, edit, and delete streaming destinations from the Streaming destinations page.
- R22. URL fields are validated against the chosen protocol's expected scheme (rtmp://, rtmps://, rtsp://) before save.

**App section (bottom)**
- R23. The App section is anchored at the bottom of the populated Settings list and contains: Theme, Permissions, About. Diagnostics is removed from this section because R5 places it under Camera.

**Removals (no replacement on this page)**
- R24. The "Recording defaults" card is removed from Settings. Per-match quality is set in the Match setup screen and is the only place those values are configured.
- R25. The "Connectivity" card (WiFi AP auto-enable, stay-awake on download, keep BLE alive in background) is removed. These are not user-tunable; BLE and WiFi-AP are the camera's only transports.

---

## Acceptance Examples

- AE1. **Covers R1, R3.** Given the app has no camera connection, when the user opens the Settings tab, the page renders the full-screen empty state and no camera/user/match/streaming section cards are visible. When the user then connects a camera, the four-section layout appears with the camera card populated and the active user shown.
- AE2. **Covers R4.** Given a camera is connected, when the user taps Disconnect, the BLE link drops and the empty state renders. When the user then taps "Connect camera" from the empty state, the app reconnects to the same camera without scanning.
- AE3. **Covers R7, R8.** Given user A is active, the User section on the Settings page shows a compact row with "A" displayed and a dropdown indicator. When the user taps the dropdown and selects user B, the active user switches inline (no navigation) and the Teams tab reloads to user B's data.
- AE4. **Covers R9, R10.** Given the User section is visible, when the user taps "Add user", the bottom-sheet form appears. When the user opens "Manage users" and deletes a non-active user, it succeeds after one confirm step. When the active user is the only user, the delete action is blocked.
- AE5. **Covers R12, R13, R15.** Given the user is on the Sport setups page for soccer, when the page loads, the built-in soccer format(s) appear at the top with a "Default" chip and no edit/delete affordance; custom formats appear below without the chip and with edit/delete affordances. Each row reads as a single inline line: `[Default]  Standard  2 × 35 min`.
- AE6. **Covers R14.** Given the user has selected "Soccer" in the sport filter chips on the Sport setups page, only soccer presets are shown; all other sports are hidden.
- AE7. **Covers R17.** Given the Streaming Setup section nav row shows "2 destinations", when the user taps it, the Streaming destinations page opens listing those two destinations.
- AE8. **Covers R19.** Given the user is adding a streaming destination and selects provider = YouTube, when the form renders, the protocol is fixed to RTMP (not user-selectable) and only Name, URL, and Stream key fields are visible.
- AE9. **Covers R20.** Given the user selects provider = Custom and protocol = RTSP, when the form renders, the visible fields are URL, optional Username, optional Password — and Stream key is not visible. When the user changes protocol to RTMP, the visible fields become URL and Stream key, and the username/password fields are gone.
- AE10. **Covers R22.** Given the user has selected protocol = RTMP and entered a URL beginning with `https://`, when they tap Save, the save is rejected with an inline error pointing at the URL field.

---

## Success Criteria

- An operator opening Settings with no camera connected sees one obvious next action and takes it without scrolling past dead controls.
- An operator running two programs on one camera can keep their teams, matches, and streaming credentials cleanly segmented and switch contexts without re-entering anything.
- An operator can configure a YouTube destination once and reuse it across matches without retyping the URL or key.
- A planning agent reading this document does not have to invent which sections exist on the page, what a User scopes, what a streaming destination looks like, or which protocols are in v1.

---

## Scope Boundaries

- Forget / unpair camera flow. Disconnect drops the link only; there is no "remove from known list" action in v1.
- Cloud-synced or remote-auth users. Users are camera-only — no email, no password, no cloud account, no sync. They exist purely to organize and segment camera-side data.
- Multi-camera support. The app pairs to one camera at a time; the "Connect a different camera" row is gone.
- Streaming protocols beyond RTMP / RTMPS / RTSP (no SRT, HLS push, WebRTC, etc.).
- Per-platform OAuth (no "Sign in with YouTube" to fetch a stream key automatically). All streaming credentials are entered manually.
- Redesign of the Diagnostics page itself. It is relocated under the Camera section but its internals do not change.
- Migrating the deleted cards' settings into other pages. Recording defaults already exist in the Match setup flow; the connectivity toggles are simply removed.
- Schema authoring of the proto messages and firmware-side implementation of the new BLE commands. That is its own track on the firmware side; this document captures the phone-side product contract only.

---

## Key Decisions

- **A user is a camera-side operator profile, not a phone identity or a cloud account.** Rationale: it matches the existing camera-as-source-of-truth model already used for teams, rosters, and match history. Adding a phone-only or cloud user would create a second source of truth for the same segmentation, with sync as the cost.
- **Disconnect drops the BLE link but keeps the camera in the known list — no separate "Forget camera" action.** Rationale: with a single-camera model, the only realistic reasons to disconnect are a quick handoff or troubleshooting. A "forget" action would mostly be a foot-gun.
- **Diagnostics moves into the Camera section, not the App section.** Rationale: diagnostics is exclusively about the camera link and protocol; co-locating it with the camera card matches its actual scope and frees the App section to be exclusively about the phone app itself.
- **Recording defaults and connectivity toggles are deleted, not relocated.** Rationale: per-match quality is already set in the Match setup screen, and BLE/WiFi-AP are not user-configurable transports. Re-homing them would propagate dead controls into another tab.
- **Streaming destinations live on the camera, scoped per user.** Rationale: the camera is what actually goes live; storing creds anywhere else means syncing them down at match time, with no benefit. Per-user scoping mirrors how teams and matches are already segmented.
- **v1 protocols are RTMP, RTMPS, RTSP only.** Rationale: covers the four social platforms (RTMP) and self-hosted / camera-network (RTSP); SRT/HLS/WebRTC can land later without breaking the data shape (`{name, provider, protocol, config}` is protocol-extensible).
- **Built-in game formats per sport are read-only; custom formats are user-managed.** Rationale: matches the existing built-in-vs-custom split in `SportPresetsPage`; preserves a known-good fallback per sport.

---

## Dependencies / Assumptions

- The firmware does not yet expose BLE commands for user management or streaming destinations. The phone-side UI will be built against the existing abstract `BleService` interface plus a `MockBleService` test double. End-to-end shipping waits on the firmware contract for: list / create / delete user, set active user, list / create / update / delete streaming destination, plus a way to scope existing team / match queries by active user.
- The existing `DiscoveryPage` and `DiagnosticsPage` are reused unchanged. Reshape work is on the Settings page itself, not its destinations.
- The existing `SportPresetsPage` already separates built-in from custom presets per sport. Match Setup work extends behavior on that page (default per sport, distinguishing built-ins visually) — no new page is added.
- Add / edit forms for users and streaming destinations follow the existing bottom-sheet form pattern (`team_form_sheet.dart`, `sport_preset_form_sheet.dart`).
- Switching the active user causes `teamsProvider`, `matchStateProvider`, and a new streaming-destinations provider to refetch. Existing providers are keyed by `deviceId`; they will need to also re-fetch on active-user changes (or be re-keyed by `(deviceId, activeUserId)`) — exact mechanism is a planning concern.

---

## Outstanding Questions

### Resolve Before Planning

- *(none — every product-shaping question was resolved in dialogue.)*

### Deferred to Planning

- [Affects R5][Technical] Diagnostics under Camera: a single nav row inside the camera card vs. a sibling card directly beneath it. Both satisfy R5; pick the one that lands cleaner visually with the existing `WfCard` styling.
- [Affects R7][Technical] Exact widget for the inline user dropdown — a `DropdownButton`, a custom `PopupMenuButton`-based row, or a bottom sheet list triggered by tapping the active-user row. All satisfy R7/R8; pick the one that matches the dark-theme aesthetic without OS-default widget chrome.
- [Affects R8][Technical] How `teamsProvider` / `matchStateProvider` / streaming-destinations provider are re-keyed or invalidated on active-user switch. Implementation choice; doesn't change product behavior.
- [Affects R18][Technical][Needs research] Final proto message shape for streaming destinations. The product contract is `{name, provider, protocol, config}` with `config` being protocol-specific; the wire-format choice (oneof in proto3, vs. a flat record with optional fields per protocol) is for planning.
- [Affects R10][Technical] What happens to data owned by a deleted user — does the camera cascade-delete their teams, matches, and streaming destinations, or does it orphan and reclaim later? Affects firmware contract more than the phone UI.
- [Affects R4][Technical] Whether a one-tap reconnect from the empty state needs a new "reconnect last camera" path on `BleService`, or whether the existing `DiscoveryPage` already short-circuits when a known device is in range.
- [Affects R17][Technical] Whether the Streaming destinations page is a new file (`streaming_destinations_page.dart`) mirroring `sport_presets_page.dart`, or whether the existing streaming-section logic in `settings_page.dart` is extracted and promoted. Both are workable; a new file is cleaner given the existing page already has the nav-row entry point.
