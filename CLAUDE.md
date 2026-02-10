# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MyShortcuts is a collection of PowerShell launcher scripts that provide quick access to development projects. `MyShortcuts.ps1` is the management hub; all other `.ps1` files are per-project shortcut scripts that open directories, launch IDEs, start services, and compile solutions.

## Setup

Scripts must be unblocked before first use:
```powershell
Get-ChildItem -Path .\ -Recurse -Filter *.ps1 | Unblock-File
```

## Architecture

### MyShortcuts.ps1 — The Manager

Manages the shortcut collection itself. Key capabilities:
- `-init` adds the MyShortcuts directory to the user's `PATH` environment variable so scripts can be called by name from anywhere.
- `-new` launches an interactive wizard to create a new shortcut script from feature snippets in `templates/snippets/`.
- `-edit` opens an action menu for an existing shortcut: **Add predefined feature**, **Add custom command**, or **Open in editor**.
- `-list` lists all available `.ps1`/`.bat` shortcuts.
- `-directory` / `-d` opens the MyShortcuts folder (in Explorer or terminal with `-t`).

### Configuration

`settings.json` stores user-level config:
- `devDirectory` — base development folder used to resolve relative project paths
- `editorPath` — editor to open scripts with (defaults to `notepad.exe`)
- `tunnelName` — default Cloudflared tunnel name (optional)

`config/features.json` defines the predefined feature registry: each feature has an `id`, display `label`, `snippet` filename, `params` array (switch name, alias, type), optional `configVars`, and optional `prompts` array for config variable requirements when injecting via `-edit`.

### lib/InteractiveMenu.ps1

Two reusable console UI functions used by the wizard and edit flows:
- `Show-SelectionMenu -Title -Options` — single-select arrow-key menu, returns selected index.
- `Show-ChecklistMenu -Title -Items` — multi-select checklist (space to toggle, enter to confirm), returns array of selected indices. Items are `@{ label = "..."; checked = $true/$false }`.

### Per-Project Shortcut Scripts

Each project script created from MyShortcuts follows a consistent pattern:

**Configuration block** (top of every script):
- `$baseDir` — project root path (absolute, or resolved from `devDirectory` in settings)
- `$baseDirUi` — (some scripts) path to the frontend/UI project
- `$projectName` — solution name
- `$tunnelName` — Cloudflared tunnel name

**Common switches** (present in most scripts):
| Switch | Alias | Action |
|--------|-------|--------|
| `-directory` | `-d` | Open project directory |
| `-explorer` | `-exp` | Open project directory in Windows Explorer |
| `-project` | `-p` | Open `.sln` in Visual Studio |
| `-all` | `-a` | Run all launch actions together |
| `-release` | | dotnet build in Release config |
| `-debug` | | dotnet build in Debug config |
| `-ui` | | Open frontend project in VS Code |
| `-tunnel` | | Start Cloudflared tunnel |
| `-claude` | | Open Claude Code in the backend project directory |
| `-claudeui` | | Open Claude Code in the UI project directory |

Not every script has every switch — check the `param()` block at the top of each file.

### Templates

`templates/snippets/` contains individual feature snippets (e.g. `directory.ps1`, `compile.ps1`, `claude.ps1`). The `-new` wizard assembles a shortcut script by combining the selected snippets. Each snippet is a self-contained `if($switchName){ ... }` block.

### Marker Comments & Feature Injection

Scripts created by the `-new` wizard contain three marker comments that enable programmatic editing via `-edit`:

- `# [/params]` — last line inside `param()`, before closing `)`. New switch declarations are injected here.
- `# [/help]` — inside the help block, before `Write-Host ""` + `exit`. New help lines are injected here.
- `# [/commands]` — very last line of the script. New command blocks are injected here.

The generated script layout also uses two config section delimiters that the injection code searches for:
- `# =============== Script =============== #` — top of config section (settings line goes after this)
- `# ===== C O N F I G U R A T I O N ====== #` — bottom of config section (new config vars go before this)

A feature's `prompts` array in `features.json` specifies config variables needed when injected (e.g. `projectName`, `baseDirUi`). A prompt with a `settingsKey` falls back to `$settings.<key>` when the user leaves the value empty.

**Injection mechanics:** The edit functions read the file as an array of lines, find marker positions, then insert new content in reverse index order (commands → group trigger → help → config → params) to avoid index shifting. The last param line before the marker gets a trailing comma appended before new params are inserted.

**Add custom command** always opens the file in the editor afterwards so the user can fill in the `# TODO` placeholder.

## Conventions

- Follow the existing template structure: `param()` block, configuration variables section, then conditional blocks per switch.
- Generated scripts must preserve the three marker comments (`# [/params]`, `# [/help]`, `# [/commands]`) for `-edit` injection to work.
- Use `-all` to group the common launch actions (directory, project, tunnel, etc.).
- Use `pushd`/`popd` when temporarily changing directories within a switch block.
- Use `wt --window 0` to spawn new Windows Terminal tabs for long-running processes (tunnels, claude).
- Keep `$baseDir` and `$projectName` as the first configuration variables.
- New snippets in `templates/snippets/` should be self-contained `if($param){ ... }` blocks referencing config variables like `$baseDir`, `$baseDirUi`, `$projectName`.
