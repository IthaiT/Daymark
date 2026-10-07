# Repository Guidelines

## Project Structure & Module Organization

`daymark/` contains the Python desktop application. `app.py`, `dialogs.py`, and `timeline.py` implement the Tkinter interface; `widgets.py` provides tree, calendar, and time pickers; `model.py` handles time calculations; `storage.py` validates and persists records; `instance.py` locks the data directory; `__main__.py` starts the application. Keep calculations and persistence independent of UI code.

`tests/` contains storage and desktop integration tests. `environment.yml` defines the Conda environment; `start.cmd` and `start.ps1` are Windows launchers. There is no separate asset directory. Runtime `data/` and generated `.test-artifacts/` are ignored by Git.

## Build, Test, and Development Commands

Run these PowerShell commands from the repository root:

```powershell
# Create the Python 3.12 / Tk environment.
conda env create --prefix ./.conda --file environment.yml
# Launch directly without activating Conda.
./.conda/python.exe -m daymark
# Run storage tests without opening windows.
./.conda/python.exe -m unittest discover -s tests -p test_storage.py -v
# Run all tests, including real Tk windows.
$env:DAYMARK_UI_TESTS = '1'
./.conda/python.exe -m unittest discover -s tests -v
```

No compilation or packaging step is required.

## Coding Style & Naming Conventions

Use four-space indentation, `snake_case` functions and variables, `PascalCase` classes, and `UPPER_CASE` constants. Prefer standard-library modules, type hints for models, and short docstrings. Keep user-facing text in Chinese. Update `environment.yml` if dependencies change.

No formatter or linter is configured. Follow neighboring code and run `git diff --check`. `.gitattributes` specifies LF except for CMD launchers, which use CRLF.

## Testing Guidelines

Use `unittest`, naming files `test_*.py` and methods `test_<behavior>`. Add regression tests for changed persistence or time-accounting behavior, especially tag moves, midnight boundaries, overlaps, legacy-data compatibility, and failed writes. Test right-click, drag, and picker interactions when changing the UI. Use isolated temporary directories under `.test-artifacts/`.

UI tests require a desktop session and `DAYMARK_UI_TESTS=1`; otherwise they are skipped. Run affected tests before committing. No numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

Follow existing prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, and `chore:`. Keep commits small and focused; preserve linear history through rebase or fast-forward integration.

PR descriptions should explain the problem, resulting behavior, and validation performed. Link relevant issues when available; include screenshots for interface changes and describe storage-format changes.

## Data Safety

Preserve stable tag IDs, JSON versioning, CSV columns, and UTF-8 BOM encoding for CSV. Retain atomic writes, single-instance locking, and corrupt-file protection. Use local timestamps consistently. Never commit personal records or test against the user's live `data/` directory.

Events may use any tag level or remain unclassified. Adding or moving child tags must preserve existing event-to-tag IDs.
