# Repository Guidelines

## Project Structure & Module Organization

`src/` contains the files installed for Codex Prompt Coach: PowerShell entry points, the CMD editor wrapper under `src/bin/`, and the prompt asset under `src/prompts/`. `scripts/install.ps1` installs those files and registers the launcher in the PowerShell profile. `tests/` contains the automated smoke test and the opt-in live test. `docs/project_description.md` records implementation details and validation results; `README.md` is the user guide.

Keep runtime resources in `src/` and preserve their relative paths, since the scripts resolve the prompt and wrapper from their locations.

## Build, Test, and Development Commands

There is no separate build step. Run commands from the repository root with PowerShell 7:

- `pwsh -NoProfile -File .\tests\smoke.ps1` runs automated checks with test doubles and Vim.
- `pwsh -NoProfile -File .\tests\live.ps1` exercises the installed tool with a real Codex model call and Vim; use it when live integration validation is needed.
- `pwsh -NoProfile -File .\scripts\install.ps1` installs the tool and updates the PowerShell profile. Use `-VimPath 'C:\path\vim.exe'` when Vim is not auto-detected.

## Coding Style & Naming Conventions

Use four spaces for PowerShell indentation, `$camelCase` for local variables and parameters, and approved `Verb-Noun` names for functions. Use lowercase directory names and descriptive filenames such as `codex-prompt-coach.ps1`. Keep scripts compatible with PowerShell 7 and use literal-path APIs for filesystem operations. No formatter or linter is configured; follow the surrounding style.

## Testing Guidelines

Name automated checks `tests/*.ps1`. Add behavior coverage to `smoke.ps1` when changing installation, path handling, editor invocation, or session restoration. The live test makes a real model call, so reserve it for changes that need end-to-end confirmation. Update `docs/project_description.md` when recorded behavior or validation results change.

## Commit & Pull Request Guidelines

The repository has no commit history yet, so no established commit-message convention can be inferred. Use concise imperative subjects, for example `Update installer source paths`. Pull requests should describe the user-visible change, list relevant validation commands and results, and link an issue when one exists. Include screenshots only when a change affects a visual interface; this project is command-line based.

## Security & Configuration

Never commit credentials, profile backups, or machine-specific installation paths. Keep model-call behavior and environment-variable changes scoped to the coach, and document changes that affect the PowerShell profile or child processes.