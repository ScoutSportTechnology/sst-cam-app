---
title: "Tie bool.fromEnvironment defaultValue to APP_ENV to avoid dev/prod flag conflicts"
date: 2026-05-19
category: docs/solutions/developer-experience/
module: tooling
problem_type: developer_experience
component: tooling
severity: high
applies_when:
  - Adding a boolean dart-define flag that should default to on in dev and off in prod
  - Any compile-time flag guarding dev-only behavior (seeding, logging, mock toggles)
tags:
  - dart-define
  - environment-flags
  - mock-data
  - dev-workflow
  - flutter
---

# Tie bool.fromEnvironment defaultValue to APP_ENV to avoid dev/prod flag conflicts

## Context

`lib/env.dart` uses compile-time constants to control runtime behavior. Two key constants are `kAppEnv` (wraps `APP_ENV`) and `kUseMockData` (wraps the `kUseMockData` dart-define). `MockDataSeeder.seed()` is called at app startup when `kUseMockData` is true, populating the local Drift database from fixture files in `assets/mock/fixtures/`. This seeder is the sole source of developer fixture data (teams, matches, events).

During a code review, `defaultValue: true` was changed to `defaultValue: false` because a reviewer correctly noted that production builds that forget `--dart-define=kUseMockData=false` would seed fake data into real user databases. The fix silently broke the dev workflow — no error, no warning, just an empty database on the next `flutter run`.

This pattern recurs whenever a boolean flag must be:
- On by default in dev (for convenience)
- Off by default in prod (for safety)
- Explicitly overridable in either direction

## Guidance

Tie the `defaultValue` to the `APP_ENV` environment variable rather than hardcoding `true` or `false`:

```dart
// lib/env.dart

// Already present — _envName is a compile-time const:
const String _envName = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

// Key insight: _envName == 'dev' is a valid const bool expression.
// Both sides are compile-time constants, making == resolvable at compile time.
const bool kUseMockData = bool.fromEnvironment(
  'kUseMockData',
  defaultValue: _envName == 'dev',
);
```

Behavior matrix:

| Command | APP_ENV | kUseMockData | Seeder runs? |
|---|---|---|---|
| `flutter run` | `dev` (default) | `true` (default from env) | Yes |
| `flutter run --dart-define=APP_ENV=prod` | `prod` | `false` (default from env) | No |
| `flutter run --dart-define=kUseMockData=false` | `dev` | `false` (explicit override) | No |
| `flutter run --dart-define=kUseMockData=true` | anything | `true` (explicit override) | Yes |

Production CI/CD should always pass `--dart-define=APP_ENV=prod`. This means even if a developer accidentally omits `--dart-define=kUseMockData=false`, the seeder will not run.

## Why This Matters

`defaultValue` in `bool.fromEnvironment` is evaluated at compile time. It must be a `const bool` expression. The expression `_envName == 'dev'` satisfies this because `_envName` is a `const String` (result of `String.fromEnvironment`) and `'dev'` is a string literal — both compile-time constants.

Without this pattern, there are only two bad options:
- `defaultValue: true` — convenient for dev, dangerous for production if CI forgets the flag
- `defaultValue: false` — safe for production, but silently empties the developer database with no warning

The `APP_ENV` indirection gives you both without tradeoffs: safe by default in prod, convenient by default in dev, and always overridable by explicit dart-define.

## When to Apply

Apply this pattern to any boolean dart-define flag that should behave differently in dev vs. production:
- Feature flags gating in-progress work
- Seeder/fixture flags
- Debug logging flags
- Telemetry/diagnostics flags

Do NOT apply it when the flag semantics are environment-independent (e.g., a flag controlling a specific experimental UI variant that has no safety implications in production).

## Examples

**Before (dangerous for prod):**
```dart
const bool kUseMockData = bool.fromEnvironment(
  'kUseMockData',
  defaultValue: true, // production could seed fake data if CI forgets the flag
);
```

**Before (breaks dev workflow):**
```dart
const bool kUseMockData = bool.fromEnvironment(
  'kUseMockData',
  defaultValue: false, // dev gets empty DB, no error or warning
);
```

**After (correct — env-aware default):**
```dart
const String _envName = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

const bool kUseMockData = bool.fromEnvironment(
  'kUseMockData',
  defaultValue: _envName == 'dev',
);
```

Apply the same pattern to any other env-sensitive flag:
```dart
const bool kVerboseLogging = bool.fromEnvironment(
  'kVerboseLogging',
  defaultValue: _envName == 'dev',
);
```

## Related

- `lib/env.dart` — canonical location for all compile-time environment constants
- `lib/db/mock_data_seeder.dart` — guarded by `kUseMockData`
- `lib/main.dart` — calls `MockDataSeeder(db).seed()` when `kUseMockData` is true
