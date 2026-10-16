# Repository Guidelines

## Project Structure & Module Organization

`lib/` contains the Flutter / Dart Windows desktop application. `domain/` implements local calendar models, overlap segmentation, timeline drag calculations, Unicode compatibility and snapshot history. `data/` validates and persists JSON/CSV and locks the data directory. `application/journal_controller.dart` serializes mutations and combines event changes with legacy-gap compatibility in one atomic write. `ui/` implements the tag tree, pickers, dialogs, event table, inline editing and timeline. Keep calculations and persistence independent of UI code.

`windows/` is the standard Flutter desktop host. `test/` contains unit and headless Widget interaction tests; `test/fixtures/` contains synthetic Python-baseline compatibility samples. `tools/smoke_windows.ps1` runs the built application on an inactive private Windows desktop. `start.cmd` and `start.ps1` launch the Release build. Runtime `/data/`, `.test-artifacts/`, SDKs, caches and build outputs are ignored by Git.

## Build, Test, and Development Commands

Run from the repository root with Flutter stable (verified 3.47.7 / Dart 3.13.5) and the Visual Studio C++ Windows toolchain:

```powershell
flutter pub get
flutter run -d windows
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --release
./tools/smoke_windows.ps1
git diff --check
```

For this workspace's ignored SDK, use `./.tools/flutter/bin/flutter.bat` and `./.tools/flutter/bin/cache/dart-sdk/bin/dart.exe`; set `$env:PUB_CACHE = Join-Path $PWD '.tools/pub-cache'`. Plugin symlinks require Windows Developer Mode or suitable link permissions. This workstation uses project-local NTFS junctions instead; never modify system settings without explicit authorization. Distribute the entire Release directory, not just its EXE.

## Coding Style & Naming Conventions

Use `dart format`, `flutter_lints`, strict analyzer types, `lowerCamelCase` members, `UpperCamelCase` types and `snake_case.dart` filenames. Keep user-facing text in Chinese. Use standard Material 3 components and Material color swatches instead of custom palettes. Prefer immutable domain values, standard libraries and short docstrings. Update `pubspec.yaml` and `pubspec.lock` when dependencies change.

`.gitattributes` specifies LF except for CMD launchers, which use CRLF. `lib/domain/unicode_data.dart` contains a compressed Unicode 15.0 snapshot matching original Python 3.12 casefold and printable classification. Do not casually replace it with Dart lowercasing or UTF-16 ordering.

## Testing Guidelines

Use Flutter `test` and `testWidgets`, naming files `*_test.dart`. Add regression tests for changed persistence and time-accounting behavior, especially tag moves, midnight boundaries, overlaps, legacy-data compatibility and failed writes. Test right-click, drag, pickers and inline editing when changing the UI. Use isolated temporary directories under `.test-artifacts/`; never test against personal `/data/`.

Widget tests run without native windows. The Release smoke test requires Windows and a desktop session. It creates a private inactive desktop without desktop-switch access and owns every process it launches. Never activate that desktop or fall back to opening test windows on the active desktop. Creation failures must stop validation. Run affected tests before committing; no numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

Follow existing prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, and `chore:`. Keep commits small and focused; preserve linear history through rebase or fast-forward integration.

PR descriptions should explain the problem, resulting behavior, and validation performed. Link relevant issues when available; include screenshots for interface changes and describe storage-format changes.

## Data Safety

Preserve stable tag IDs, JSON version 1, the original six CSV columns and UTF-8 BOM. Retain flushed same-directory atomic replacement, `.daymark.lock` first-byte Windows locking and corrupt-file protection. Keep the lock reachable for the entire Release application's lifecycle. Preserve local calendar fields without timezone conversion; UTC `DateTime` values are only zone-neutral containers for these fields. Never commit personal records or test against the user's live `data/` directory.

Events may use any tag level or remain unclassified. Tag moves must preserve event associations. Retain legacy seconds and incomplete records; do not create automatic gaps between events. Remove default legacy gaps without notes, while keeping derived `undefined:` IDs and customized legacy gaps compatible. Drafts stay in memory and disappear on date change or exit. Save failures must retain prior persisted state and the user's editing input.
