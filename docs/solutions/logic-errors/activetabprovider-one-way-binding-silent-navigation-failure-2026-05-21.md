---
title: activeTabProvider one-way binding causes silent repeated navigation failure
module: app_shell
date: "2026-05-21"
category: docs/solutions/logic-errors/
problem_type: logic_error
component: frontend_stimulus
severity: high
symptoms:
  - "Programmatic navigation to a tab via activeTabProvider appears to succeed once but silently fails on repeat writes of the same value"
  - "User taps a tab manually (widget state advances) while provider value lags behind; subsequent programmatic write is a no-op because ref.listen only fires on change"
  - "No error or assertion is thrown; navigation failure is invisible to the developer"
root_cause: logic_error
resolution_type: code_fix
tags:
  - riverpod
  - state-provider
  - navigation
  - one-way-binding
  - tab-navigation
  - flutter
  - desync
---

# activeTabProvider one-way binding causes silent repeated navigation failure

## Problem

When `NavigationBar.onDestinationSelected` updates local `_index` state without writing back to `activeTabProvider`, the provider and the widget's local state diverge. A subsequent programmatic navigation to a tab the user is already "on" silently fails because Riverpod's `ref.listen` equality check suppresses the callback when the provider value has not changed.

## Symptoms

- Tapping a `NavigationBar` destination works visually, but `activeTabProvider` retains its previous value.
- Programmatic cross-page navigation (e.g., a team detail page writing `ref.read(activeTabProvider.notifier).state = AppTab.match`) intermittently does nothing — the target tab never activates.
- The failure is non-deterministic: navigation works the first time but silently fails on a second attempt if the user has manually tapped away and back in between.
- No exception or error is thrown; the NavigationBar stays on the wrong tab with no feedback.

## What Didn't Work

Caught in code review before manifesting in production. Static analysis of the `ref.listen` + `onDestinationSelected` interaction was sufficient to identify the divergence; no runtime investigation was needed.

## Solution

In `lib/app_shell.dart`, `onDestinationSelected` must write back to `activeTabProvider` in addition to updating local `_index`:

**Before:**
```dart
onDestinationSelected: (i) => setState(() => _index = i),
```

**After:**
```dart
onDestinationSelected: (i) {
  setState(() => _index = i);
  ref.read(activeTabProvider.notifier).state = i;
},
```

Additionally, replace magic tab index integers with named constants. In `lib/state/app_data.dart`:

```dart
abstract final class AppTab {
  static const int main = 0;
  static const int teams = 1;
  static const int match = 2;
  static const int video = 3;
  static const int settings = 4;
}
```

Use `AppTab.match` (etc.) at every call site instead of bare integers:

```dart
// Before:
ref.read(activeTabProvider.notifier).state = 2;

// After:
ref.read(activeTabProvider.notifier).state = AppTab.match;
```

## Why This Works

`ref.listen` uses `==` equality to decide whether to invoke the callback. If `activeTabProvider` holds `2` and a programmatic write sets it to `2` again, Riverpod treats this as a no-op — the listener never fires, leaving `_index` unchanged. The root cause is that `NavigationBar` taps advanced only the ephemeral local widget state while leaving the provider stale, creating a hidden one-way binding. Keeping both sides in sync means the provider always reflects ground truth, so a subsequent write of the same value is a genuine no-op (the user is already there) rather than a masked state divergence.

## Prevention

- **Bidirectional sync rule:** Any widget that drives local state from a `StateProvider` via `ref.listen` must also write back to that provider whenever local state changes. The provider is the single source of truth — local widget state must never advance without updating it.
- **Simpler alternative:** Eliminate the local `_index` field entirely. Read `ref.watch(activeTabProvider)` directly in `build()` for `NavigationBar.selectedIndex`. This removes the sync problem at the source — there is no secondary state to diverge.
- **Named constants:** Never use magic integers for tab indices. Define an `AppTab` constants class (or enum with `.index`) so all cross-page navigation references are refactor-safe and readable.
- **Test:** Add a widget test that (1) writes `activeTabProvider` to tab X, (2) simulates a user `NavigationBar` tap to a different tab, then (3) writes `activeTabProvider` back to X and asserts the correct tab is visible — this covers the exact silent-failure scenario.

## Related Issues

- `lib/app_shell.dart` — `AppShell` widget containing the `NavigationBar` + `activeTabProvider` binding
- `lib/state/app_data.dart` — `activeTabProvider` declaration and `AppTab` constants class
- `lib/pages/team_detail_page.dart` — cross-page navigation consumer using `activeTabProvider`
