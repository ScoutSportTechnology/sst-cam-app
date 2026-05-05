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
- R7. The User section shows the currently active camera-side user inline at the top of the section (no nav-row wrapping). All camera-stored data on every tab is scoped to this user.
- R8. The user can switch the active user from this section. Switching causes the app to reload teams, matches, and streaming destinations to reflect the new user's data.
- R9. The user can add a new user from this section via a bottom-sheet form (matching the existing team / sport-preset form-sheet pattern). Minimum field: a display name.
- R10. The user can delete a user. Deleting a non-active user is a single confirm step. Deleting the active user is blocked with an inline message until another user is selected; deleting the last user on the camera is blocked outright.

**Match Setup section (Game Formats)**
- R11. The Match Setup section continues to be a nav row that opens the existing Sport setups page; the page itself is extended to be the canonical home for game formats.
- R12. Each sport has one or more built-in default formats that appear at the top of that sport's group and are read-only (cannot be edited or deleted).
- R13. The user can add, edit, and delete custom formats per sport. Custom formats appear under the built-ins for the same sport and are clearly distinguished from them.

**Streaming Setup section**
- R14. The Streaming Setup section lists every streaming destination configured for the active user. Each destination shows its name, provider badge (YouTube / TikTok / Facebook / Instagram / Custom), and protocol.
- R15. A streaming destination is identified by `{ name, provider, protocol, config }` where `provider ∈ {youtube, tiktok, facebook, instagram, custom}`, `protocol ∈ {rtmp, rtmps, rtsp}`, and `config` is a protocol-specific record. Destinations live on the camera; the phone fetches them per active user.
- R16. For provider in {youtube, tiktok, facebook, instagram}, the protocol is fixed to RTMP and the form prompts for a URL and a stream key.
- R17. When provider is "custom", the user picks the protocol; the form's fields adapt: RTMP and RTMPS prompt for URL + stream key; RTSP prompts for URL + optional username + optional password.
- R18. The user can add, edit, and delete streaming destinations from this section.
- R19. URL fields are validated against the chosen protocol's expected scheme (rtmp://, rtmps://, rtsp://) before save.

**App section (bottom)**
- R20. The App section is anchored at the bottom of the populated Settings list and contains: Theme, Permissions, About. Diagnostics is removed from this section because R5 places it under Camera.

**Removals (no replacement on this page)**
- R21. The "Recording defaults" card is removed from Settings. Per-match quality is set in the Match setup screen and is the only place those values are configured.
- R22. The "Connectivity" card (WiFi AP auto-enable, stay-awake on download, keep BLE alive in background) is removed. These are not user-tunable; BLE and WiFi-AP are the camera's only transports.

---

## Acceptance Examples

- AE1. **Covers R1, R3.** Given the app has no camera connection, when the user opens the Settings tab, the page renders the full-screen empty state and no camera/user/match/streaming section cards are visible. When the user then connects a camera, the four-section layout appears with the camera card populated and the active user shown.
- AE2. **Covers R4.** Given a camera is connected, when the user taps Disconnect, the BLE link drops and the empty state renders. When the user then taps "Connect camera" from the empty state, the app reconnects to the same camera without scanning.
- AE3. **Covers R8.** Given user A is active and shows teams `[Lions, Tigers]`, when the user switches the active user to user B, the Teams tab now shows user B's teams and never `[Lions, Tigers]` until user A is reselected.
- AE4. **Covers R10.** Given user A is the active user and is the only user on the camera, when the user taps Delete on user A, the action is blocked with a message explaining at least one user must remain. When a second user B is added and made active, deleting user A succeeds.
- AE5. **Covers R12, R13.** Given the user is on the Sport setups page for soccer, when the page loads, the built-in soccer format(s) appear at the top of the soccer group with no edit/delete affordance, and any custom formats appear below with edit/delete affordances.
- AE6. **Covers R16.** Given the user is adding a streaming destination and selects provider = YouTube, when the form renders, the protocol is fixed to RTMP (not user-selectable) and only Name, URL, and Stream key fields are visible.
- AE7. **Covers R17.** Given the user selects provider = Custom and protocol = RTSP, when the form renders, the visible fields are URL, optional Username, optional Password — and Stream key is not visible. When the user changes protocol to RTMP, the visible fields become URL and Stream key, and the username/password fields are gone.
- AE8. **Covers R19.** Given the user has selected protocol = RTMP and entered a URL beginning with `https://`, when they tap Save, the save is rejected with an inline error pointing at the URL field.

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
- [Affects R7, R8, R9, R10][Technical] How the User section presents — single combined card with the active user up top and an "Add user" / list-of-users affordance below, vs. an active-user row plus a nav row to a "Manage users" sub-page. Both are workable; weight against existing card density and the volume of users a typical operator will have.
- [Affects R8][Technical] How `teamsProvider` / `matchStateProvider` / streaming-destinations provider are re-keyed or invalidated on active-user switch. Implementation choice; doesn't change product behavior.
- [Affects R15][Technical][Needs research] Final proto message shape for streaming destinations. The product contract is `{name, provider, protocol, config}` with `config` being protocol-specific; the wire-format choice (oneof in proto3, vs. a flat record with optional fields per protocol) is for planning.
- [Affects R10][Technical] What happens to data owned by a deleted user — does the camera cascade-delete their teams, matches, and streaming destinations, or does it orphan and reclaim later? Affects firmware contract more than the phone UI.
- [Affects R4][Technical] Whether a one-tap reconnect from the empty state needs a new "reconnect last camera" path on `BleService`, or whether the existing `DiscoveryPage` already short-circuits when a known device is in range.
