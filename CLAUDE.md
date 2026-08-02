# CLAUDE.md — SiteSignal

> Read this fully before any create/modify/refactor. Code on disk is the single source of truth; this file is the standard; memory is not a shortcut. Applies to every AI agent working this repo (Claude, Codex, or otherwise) — treat it as `AGENTS.md` too.

---

## 0. Core Philosophy

SiteSignal is a small, local-first, cross-platform website-uptime monitor (macOS/Windows/Linux/iOS/Android). Its value is **monitoring accuracy and background reliability**, not feature surface area. Optimize for: deterministic behavior, a small readable codebase, predictable UI, low review overhead. **Correctness of a health transition and its notification > any UI polish.** Reuse > reinvention. A three-line duplication is better than a premature abstraction (§7).

## 1. Mandatory Execution Flow

Before any code: ① read this file fully ② read the on-disk implementation you're touching — don't guess at an API ③ grep for an existing pattern before writing a new one (§3) ④ match this repo's structure (§4) ⑤ self-audit against §5 before calling it done. **Scope = the request only** — no drive-by rename/reformat/refactor riding along in the same diff.

## 2. Project Structure

```text
lib/
  app/                       — root app widget, wiring
  core/
    async/                   — mapConcurrent (async_pool.dart), serial_task_queue
    platform/                — package_info_extensions
    text/                    — string_extensions
    theme/                   — app_theme, app_dimensions, app_accent_color,
                               app_semantic_colors, app_theme_preference
    widgets/                 — small reusable shared widgets
  features/monitoring/
    domain/                  — entities, repository interface, service interfaces
                               and pure services (monitoring_policy,
                               health_result_reducer). No concrete/plugin imports.
    data/                    — adapters: Http*, Sqlite*, Mobile/Desktop bridges,
                               background_monitor_snapshot_codec. Owns plugins,
                               HTTP, SQLite, platform channels.
    presentation/             — MonitorController (ChangeNotifier-style) + views
                               (overview/history/settings) + widgets.
test/
  support/fakes.dart          — ScriptedHealthChecker, FakeFaviconResolver,
                               FakeDesktopBridge and friends
  <mirrors lib/ one file per unit under test>
```

One feature module today (`monitoring`). `domain/` stays pure and platform-neutral — it is what makes the reducer testable identically on the main isolate and the background worker (§4.6). `data/` is the only layer allowed to touch a plugin, `Platform.is*`, `dart:io`, or SQL. `presentation/` observes the controller; it does not compute health state itself.

## 3. Pre-Edit Search

Grep before writing anything new:

```sh
grep -rln 'mapConcurrent\|AppDimensions\|AppSemanticColors\|applyHealthResult' lib/
```

Priority: ① the existing service/entity that already owns this concern in `domain/` ② `core/theme` for any visual token ③ `core/async` before writing a new concurrency helper ④ `test/support/fakes.dart` before writing a new test double.

## 4. Non-Negotiable Invariants

**4.1 No force-unwrap.** No Dart `!` postfix null-assertion, no Kotlin `!!`, no Swift force-unwrap. Promote/bind a local, use `?.`/`??`, an early return, or a guarded pattern instead. (Logical negation `!enabled` and `!=` are normal — the ban is the postfix assertion only.) Enforced by `tool/check_code_rules.dart` across `lib/ test/ tool/ android/ ios/ macos/`.

**4.2 Async safety.** Reserve shared state before the first `await`, then re-validate mutable state after the asynchronous boundary before writing back. Await any future that affects persisted state; if a future is intentionally detached, wrap it in `unawaited(...)` and make the callee contain its own failures — an uncaught detached future from a platform callback is a crash risk, not a style nit.

**4.3 Bounded concurrency.** Network fan-out goes through `mapConcurrent` (`core/async/async_pool.dart`), not raw `Future.wait` over unbounded input. `MonitoringPolicy.maximumConcurrentSiteChecks` is the current ceiling — respect it, don't invent a second concurrency knob.

**4.4 Health state is sacred.** Device/network connectivity failure must never mutate a site's health or history — a local outage is not a site outage (see `internet_connectivity` + `health_result_reducer`). Persist a transition before delivering its notification, and use stable notification keys (`incident_notification_key.dart`) so retries and re-checks never double-fire an alert.

**4.5 Never log the payload.** No monitored URL, response body, credential, or raw platform error in a user-facing notification or a log line reachable from one. Notification copy is one state word + one evidence line — nothing more.

**4.6 One isolate boundary, one reducer.** Foreground config lives on the main isolate; background runtime observation happens in the worker (`mobile_background_monitor.dart` / `desktop_app_bridge.dart`). The two only ever merge through the shared pure `applyHealthResult` reducer — never re-implement health-transition logic separately in the UI path and the background path.

**4.7 Theme-driven, native typography.** Never hardcode a color, spacing value, radius, or `TextStyle` in a feature widget — use `AppDimensions`, `colorScheme`, `textTheme`, `AppSemanticColors`. The shared `TextTheme` in `core/theme/app_theme.dart` intentionally leaves `fontFamily` unset so each platform uses its native system font. No feature widget, dialog, or one-off `Text` may pass its own `fontFamily` — if a widget needs a different weight or size, pull it from `textTheme`, don't hand-roll a `TextStyle`.

**4.8 Generated assets are generated, not hand-edited.** Launcher artwork, tray icons, and notification sounds come from their checked-in generators (`tool/generate_tray_icons.swift`, `tool/generate_notification_sound.dart`). Never hand-edit one platform's copy in isolation — regenerate from source so every platform stays byte-identical where `tool/check_code_rules.dart` expects it (accent color, sound bytes, product name/bundle id).

**4.9 Version truth.** `pubspec.yaml`'s `version:` is release truth. Read the installed Flutter/package version at runtime through package metadata (`package_info_extensions.dart`); never hardcode it in a widget. The MSIX four-part version must equal `major.minor.patch.build` — `tool/check_code_rules.dart` enforces the mapping, don't bump one without the other.

## 5. Self-Audit Before You're Done

Re-read your diff (not your intent) against this list:

- **Layering** — did `domain/` stay free of plugin/`dart:io`/SQL imports? Did `presentation/` avoid computing health state itself?
- **Async** — post-`await` re-validation done? Detached futures `unawaited()` + self-contained failure? No new unbounded `Future.wait` over network calls?
- **Null safety** — zero new `!`/`!!` force-unwraps, in Dart or the platform channel code?
- **Notifications** — persisted before delivered? Stable key used? No URL/body/credential in the copy?
- **Theme** — no literal color/spacing/radius/`TextStyle`; no per-widget `fontFamily` override?
- **Tests** — new domain logic has a unit test; new adapter has a fake in `test/support/fakes.dart` exercising normal/empty/failure; a reducer change is covered on both the UI-path and background-path callers.
- **Consistency** — a teammate opening this diff recognizes the pattern; nothing invented that duplicates an existing widget/service/token.

Uncertain on any line? Re-search → simplify → reuse. Don't ship it and leave it for review to catch.

## 6. Anti-Hallucination

Never invent a repository method, a service interface, a theme token, or a plugin API that doesn't exist on disk. If it's missing: search first, then extend the existing interface minimally, staying inside the layering in §2. Grep-found-no-caller is not sufficient reason to delete a field or method that a platform callback, a background isolate path, or a test double still depends on — check all three before removing anything.

## 7. Structure & Reuse

- A pure function that combines several domain types (e.g. `applyHealthResult`) belongs in `domain/services/`, not as an extension. An extension is for behavior that naturally belongs to one existing value type (date formatting, transition-history merging) — never use one to hide a dependency or a side effect.
- Reuse before create: grep `core/theme` and `core/widgets` before writing a new widget; promote a pattern to `core/` the second time it's needed, not the first.
- No `Helper`/`Utils`/`Manager`/`Wrapper`/`Impl` class names. Suffix by role: `XxxRepository` (interface) / `SqliteXxxRepository` or `HttpXxx` (adapter) / `XxxController` / `XxxView` / `XxxBridge` / `XxxChecker` / `XxxResolver`.
- Files `snake_case`, classes `PascalCase`.

## 8. Testing

Contract-style unit test per adapter using the fakes in `test/support/fakes.dart` (`ScriptedHealthChecker`, `FakeFaviconResolver`, `FakeDesktopBridge`, …) covering the normal path, the empty/no-op path, and the failure path. Pure domain logic (`monitoring_policy`, `health_result_reducer`, notification key derivation) gets direct unit tests with no fakes needed. Widget tests for the three views live alongside; prefer testing the controller's public state over pumping a whole page when the logic under test is not layout.

## 9. Modification Safety & Git

Preserve architecture and public APIs when editing existing code; minimize the diff; don't reformat lines you didn't otherwise touch. **Never `git commit`, push, or open a PR unless the user explicitly asks in that turn** — edit, format, analyze, and test freely, but the commit step waits for an explicit ask, every time, not just the first time.

## 10. Hard Bans

`!`/`!!` force-unwrap anywhere · hardcoded color/spacing/radius/`TextStyle` in a feature widget · per-widget `fontFamily` override · logging a monitored URL, response body, or credential · computing health/notification state independently in more than one place · unbounded concurrent network fan-out · hand-edited generated asset (icon/tray/sound) · silent `catch` that drops a background-isolate failure.

## 11. Decision Priority

When rules tension, higher wins:

1. **Monitoring correctness** — no false transition, no dropped/duplicated notification, no crash.
2. **Async/isolate safety** — no stale write, no unbounded fan-out, no silent background failure.
3. **This file's rules.**
4. **Reuse** → 5. **Simplicity** → 6. **Consistency with existing patterns** → 7. **Conciseness**.

Never trade away #1 or #2 to satisfy a lower-priority rule.

## 12. Automated Enforcement

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/check_code_rules.dart   # null-safety guard + cross-platform metadata/asset parity
flutter analyze
flutter test
```

`tool/check_code_rules.dart` is the deterministic guard — it fails the build on any new force-unwrap, on `pubspec.yaml`/MSIX version drift, on product-name/bundle-id/icon mismatches across platforms, on the default accent color drifting between `app_accent_color.dart` / `generate_tray_icons.swift` / the web manifest, and on notification-sound byte drift between the Flutter asset and its Android `res/raw` copy. Fix the source it's pointing at — never work around a failing check. Platform or background-runtime changes also need the manual device checks in `BUILD.md`.

---

**Highest-miss rules, restated:** read the on-disk implementation before editing it (§1) · connectivity failure never touches health/history (§4.4) · persist-before-notify + stable key (§4.4) · one reducer shared by both isolates (§4.6) · font set once at theme level, never per-widget (§4.7) · never commit/push/PR unless asked, every time (§9).
