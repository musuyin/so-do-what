# Repository Guidelines

## Project Status & Scope

This repository has no application scaffold or commit history. Build an offline, free, ad-free random event picker. Default to Flutter and Android per the supplied v0.1 PRD. Implement P0 before P1; exclude accounts, backends, analytics, and paid features.

## Project Structure & Module Organization

At initialization, preserve the supplied requirements in `docs/PRD.md`. Organize `lib/` by feature: collections, items, drawing, history, review, settings. Keep sampling, statistics, and persistence independent of widgets and animation. Put unit and widget tests in `test/`, device flows in `integration_test/`, and artwork and sounds in `assets/`. Register assets in `pubspec.yaml`; retain the dependency lockfile in version control.

## Build, Test, and Development Commands

These commands apply after Flutter scaffolding exists:

- `flutter doctor`: inspect the local toolchain and Android setup.
- `flutter pub get`: resolve dependencies.
- `dart format lib test`: format source and tests; include `integration_test` when present.
- `flutter analyze`: run static analysis using `analysis_options.yaml`.
- `flutter test`: run unit and widget tests.
- `flutter run`: launch on a connected device or emulator.
- `flutter build apk --debug`: build an installable Android test package.

## Coding Style & Naming Conventions

Use Dart formatter output, two-space indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Enable Flutter lints when scaffolding. Prefer small feature modules, stable IDs, UTC persistence, and explicit error handling. Keep interface wording in Chinese and implementation details out of user-facing messages.

## Business Rules & Testing Guidelines

Use `flutter_test`; name tests `*_test.dart`. Inject deterministic randomness. Verify all three draw modes, persisted cycles, idempotent status changes, historical snapshots, and atomic backup restoration. Save each result and cycle consumption atomically before animation. Completion belongs to a draw record; redrawing creates another record. Global execution rate is total completions divided by total draws. No coverage percentage is established; prioritize these invariants. Check actual layouts, reduced motion, and offline flows; report unavailable device checks honestly.

## Commit & Pull Request Guidelines

No commit convention exists yet. Prefer imperative messages such as `feat(draw): persist cycle consumption`. PRs should describe behavior, link requirements or issues, report validation and limitations, and include screenshots or recordings for visual changes. Do not stage, commit, push, or publish without explicit user authorization.

## Security & Licensing

Never commit personal collections, action histories, backups, credentials, or signing keys. Use fictional fixtures. Verify asset and dependency licenses; the owner must select the project license before public release.
