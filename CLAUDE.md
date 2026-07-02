# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MyShortcuts is a collection of PowerShell launcher scripts that provide quick access to development projects. `MyShortcuts.ps1` is the management hub; all other `.ps1` files are per-project shortcut scripts that open a single project directory, launch IDEs, start services, and compile solutions.

## Setup

Scripts must be unblocked before first use:
```powershell
Get-ChildItem -Path .\ -Recurse -Filter *.ps1 | Unblock-File
```

## Architecture

### MyShortcuts.ps1 — The Manager

Manages the shortcut collection itself. Key capabilities:
- `-new` launches an interactive wizard to create a new shortcut script from feature snippets in `templates/snippets/`. The wizard first asks for a **project type** (from `config/projectTypes.json`), which pre-checks a set of features in the checklist; the user can then freely toggle any feature. At the end it optionally offers to save the current selection as a new project type.
- `-edit` opens an action menu for an existing shortcut: **Add predefined feature**, **Add custom command**, or **Open in editor**.
- `-list` lists all available `.ps1`/`.bat` shortcuts.
- `-directory` / `-d` opens the MyShortcuts folder (in Explorer or terminal with `-t`).
- The MyShortcuts directory is auto-registered in the user's `PATH` on first run, and the user is prompted for `devDirectory` on first run if it isn't configured yet.

### Configuration

`settings.json` stores user-level config:
- `devDirectory` — base development folder used to resolve relative project paths
- `editorPath` — editor to open scripts with (defaults to `notepad.exe`)
- `tunnelName` — default Cloudflared tunnel name (optional)

`config/features.json` defines the predefined feature registry — "the big list." Each feature has an `id`, display `label`, `snippet` filename, `scope` (`"project"` or `"global"`), `params` array (switch name, alias, type), and optional `prompts` array for config variable requirements. Two optional fields keep feature-specific behavior in data rather than in the engine:
- `inGroupByDefault` (bool, default `true`) — whether the feature is pre-checked when building a `-all`/group trigger. `compile` sets this to `false`.
- `placeholders` (object) — extra `{{name}} -> value` substitutions passed to the snippet beyond the standard `dir`/`switch`/`label`. `compile` uses this for `{{switchRelease}}`/`{{switchDebug}}`.

The engine references **no feature by id** — all feature-specific behavior is declared in these data fields, so new features never require engine changes.

- **project-scoped** features (`directory`, `explorer`, `project`, `code`, `claude`, `compile`) operate on the script's single `$projectDir`.
- **global** features (`tunnel`, `azurite`) have no directory association.

Prompts may declare a `default` (e.g. `"{{projectName}}.sln"` for `sln`) which is shown as `(Enter = <expanded default>)` and used when the user presses Enter without typing a value. Prompts with `settingsKey` instead pull their default from `settings.json` (e.g. `tunnelName`).

`config/projectTypes.json` defines the project-type registry — a grouping layer over features. Each type has an `id`, display `label`, and a `features` array of feature ids. A type only sets the **initial checkbox state** in the wizard; it locks nothing, and the full feature list is always shown. The `blank` type (empty `features`) exists so the tool never forces a stack. Types are pure editable data; users grow the list by editing this file or by answering "save this selection as a project type" at the end of the wizard (which appends/replaces by `id`). If the file is missing/empty, the wizard skips the type step and falls back to an all-unchecked checklist.

### lib/InteractiveMenu.ps1

Two reusable console UI functions used by the wizard and edit flows:
- `Show-SelectionMenu -Title -Options` — single-select arrow-key menu, returns selected index.
- `Show-ChecklistMenu -Title -Items` — multi-select checklist (space to toggle, enter to confirm), returns array of selected indices. Items are `@{ label = "..."; checked = $true/$false }`.

### Per-Project Shortcut Scripts

Each shortcut script maps to exactly one project directory and follows a consistent pattern:

**Configuration block** (top of every script):
- `$projectDir` — the project's folder path (e.g. `"$($settings.devDirectory)\MyProject"` or an absolute path)
- `$sln` — solution file name, if the `project`/`compile` feature was selected
- `$tunnelName` — Cloudflared tunnel name (global)

**Switch naming:** every feature param uses its plain name — `-directory`, `-claude`, `-code`, `-project`, etc. (no per-directory suffixing).

**Common switches** (present in most scripts):
| Switch | Alias | Action |
|--------|-------|--------|
| `-directory` | `-d` | Open the project directory |
| `-explorer` | `-exp` | Open the project directory in Windows Explorer |
| `-project` | `-p` | Open `.sln` in Visual Studio |
| `-all` | `-a` | Run all launch actions together |
| `-release` | | dotnet build in Release config |
| `-debug` | | dotnet build in Debug config |
| `-code` | | Open project in VS Code |
| `-tunnel` | | Start Cloudflared tunnel |
| `-claude` | | Open Claude Code in the project directory |

Not every script has every switch — check the `param()` block at the top of each file.

### Templates

`templates/snippets/` contains individual feature snippets. Project-scoped snippets use `{{placeholders}}`:
- `{{dir}}` — always `$projectDir`
- `{{switch}}` — switch variable name (e.g. `directory`)
- `{{label}}` — project name, used in comments
- `{{sln}}` — the `$sln` solution variable
- `{{switchRelease}}` / `{{switchDebug}}` — for compile snippet

Global snippets (`tunnel.ps1`, `azurite.ps1`) remain as plain `if($switchName){ ... }` blocks.

### Helper Functions

- `Expand-Snippet` — reads a snippet template and replaces `{{placeholders}}` with provided values.
- `Get-ProjectDirRef` — checks whether a script already defines `$projectDir`, for use by `-edit` actions that need to reference the project folder.

### Marker Comments & Feature Injection

Scripts created by the `-new` wizard contain three marker comments that enable programmatic editing via `-edit`:

- `# [/params]` — last line inside `param()`, before closing `)`. New switch declarations are injected here.
- `# [/help]` — inside the help block, before `Write-Host ""` + `exit`. New help lines are injected here.
- `# [/commands]` — very last line of the script. New command blocks are injected here.

The generated script layout also uses two config section delimiters that the injection code searches for:
- `# =============== Script =============== #` — top of config section (settings line goes after this)
- `# ===== C O N F I G U R A T I O N ====== #` — bottom of config section (new config vars go before this)

**Injection mechanics:** The edit functions read the file as an array of lines, find marker positions, then insert new content in reverse index order (commands → group trigger → help → config → params) to avoid index shifting. The last param line before the marker gets a trailing comma appended before new params are inserted.

**Add predefined feature** (`Exec-AddFeature`) lists features not already present (by checking existing param names), prompts for any required config vars, and injects params/help/snippet/config lines for the script's single project.

**Add custom command** (`Exec-AddCustomCommand`) adds a new switch with a placeholder command block, `cd`-ing into `$projectDir` if the script defines one.

## Conventions

- Follow the existing template structure: `param()` block, configuration variables section (`$projectDir` plus any feature config vars), then conditional blocks per switch.
- Generated scripts must preserve the three marker comments (`# [/params]`, `# [/help]`, `# [/commands]`) for `-edit` injection to work.
- Use `-all` to group the common launch actions (directory, project, tunnel, etc.).
- Use `pushd`/`popd` when temporarily changing directories within a switch block.
- Use `wt --window 0` to spawn new Windows Terminal tabs for long-running processes (tunnels, claude).
- Keep `$projectDir` as the first configuration variable after the settings line.
- New snippets in `templates/snippets/` should use `{{placeholders}}` for project-scoped features (`{{dir}}`, `{{switch}}`, `{{label}}`).
