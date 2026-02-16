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
- `-edit` opens an action menu for an existing shortcut: **Add project directory**, **Add predefined feature**, **Add custom command**, or **Open in editor**.
- `-list` lists all available `.ps1`/`.bat` shortcuts.
- `-directory` / `-d` opens the MyShortcuts folder (in Explorer or terminal with `-t`).

### Configuration

`settings.json` stores user-level config:
- `devDirectory` — base development folder used to resolve relative project paths
- `editorPath` — editor to open scripts with (defaults to `notepad.exe`)
- `tunnelName` — default Cloudflared tunnel name (optional)

`config/features.json` defines the predefined feature registry: each feature has an `id`, display `label`, `snippet` filename, `scope` (`"project"` or `"global"`), `params` array (switch name, alias, type), and optional `prompts` array for config variable requirements.

- **project-scoped** features (`directory`, `explorer`, `project`, `code`, `claude`, `compile`) are generated per-directory. Snippets use `{{placeholders}}` that get expanded per directory.
- **global** features (`tunnel`, `azurite`) have no directory association.

Prompts with `"perProject": true` (e.g., `sln` for project/compile) are prompted once per directory and stored as `$<dirName>_<var>` (e.g., `$backend_sln`).

### lib/InteractiveMenu.ps1

Two reusable console UI functions used by the wizard and edit flows:
- `Show-SelectionMenu -Title -Options` — single-select arrow-key menu, returns selected index.
- `Show-ChecklistMenu -Title -Items` — multi-select checklist (space to toggle, enter to confirm), returns array of selected indices. Items are `@{ label = "..."; checked = $true/$false }`.

### Per-Project Shortcut Scripts

Each project script created from MyShortcuts follows a consistent pattern:

**Configuration block** (top of every script):
- `$projects` — ordered hashtable mapping directory names to paths (e.g., `"backend" = "$($settings.devDirectory)\MyProject"`)
- `$<dirName>_sln` — per-directory solution name (e.g., `$backend_sln`)
- `$tunnelName` — Cloudflared tunnel name (global)

**Switch naming convention:**
- Primary directory (first in `$projects`) gets plain switch names: `-directory`, `-claude`, `-code`, etc.
- Additional directories get suffixed names: `-directoryui`, `-claudeui`, `-codedocs`, etc.
- Primary directory keeps aliases (e.g., `-d` for `-directory`). Suffixed variants have no alias.

**Common switches** (present in most scripts):
| Switch | Alias | Action |
|--------|-------|--------|
| `-directory` | `-d` | Open primary project directory |
| `-directoryui` | | Open UI project directory |
| `-explorer` | `-exp` | Open primary directory in Windows Explorer |
| `-project` | `-p` | Open `.sln` in Visual Studio |
| `-all` | `-a` | Run all launch actions together |
| `-release` | | dotnet build in Release config |
| `-debug` | | dotnet build in Debug config |
| `-code` | | Open project in VS Code |
| `-tunnel` | | Start Cloudflared tunnel |
| `-claude` | | Open Claude Code in the primary project directory |
| `-claudeui` | | Open Claude Code in the UI project directory |

Not every script has every switch — check the `param()` block at the top of each file.

### Templates

`templates/snippets/` contains individual feature snippets. Project-scoped snippets use `{{placeholders}}`:
- `{{dir}}` — directory reference (e.g., `$($projects.backend)`)
- `{{switch}}` — switch variable name (e.g., `directory` or `directoryui`)
- `{{label}}` — directory name for comments (e.g., `backend`)
- `{{sln}}` — per-project solution variable (e.g., `$backend_sln`)
- `{{switchRelease}}` / `{{switchDebug}}` — for compile snippet

Global snippets (`tunnel.ps1`, `azurite.ps1`) remain as plain `if($switchName){ ... }` blocks.

### Helper Functions

- `Expand-Snippet` — reads a snippet template and replaces `{{placeholders}}` with provided values.
- `Get-SwitchName` — returns the switch name for a feature+directory combination (primary = plain name, others = suffixed).
- `Get-ExistingProjects` — parses the `$projects = [ordered]@{...}` block from script lines to extract directory names and paths.

### Marker Comments & Feature Injection

Scripts created by the `-new` wizard contain four marker comments that enable programmatic editing via `-edit`:

- `# [/params]` — last line inside `param()`, before closing `)`. New switch declarations are injected here.
- `# [/projects]` — inside the `$projects` hashtable. New directory entries are injected here.
- `# [/help]` — inside the help block, before `Write-Host ""` + `exit`. New help lines are injected here.
- `# [/commands]` — very last line of the script. New command blocks are injected here.

The generated script layout also uses two config section delimiters that the injection code searches for:
- `# =============== Script =============== #` — top of config section (settings line goes after this)
- `# ===== C O N F I G U R A T I O N ====== #` — bottom of config section (new config vars go before this)

**Injection mechanics:** The edit functions read the file as an array of lines, find marker positions, then insert new content in reverse index order (commands → group trigger → help → config → projects → params) to avoid index shifting. The last param line before the marker gets a trailing comma appended before new params are inserted.

**Add project directory** (`Exec-AddProject`) injects a new directory entry into `$projects`, adds suffixed params/help/snippets for selected features, and updates the group trigger.

**Add predefined feature** (`Exec-AddFeature`) shows a directory picker for project-scoped features and generates per-directory switch expansions.

**Add custom command** shows a directory picker when multiple directories exist and references `$($projects.<name>)` instead of a hardcoded variable.

## Conventions

- Follow the existing template structure: `param()` block, configuration variables section with `$projects` hashtable, then conditional blocks per switch.
- Generated scripts must preserve the four marker comments (`# [/params]`, `# [/projects]`, `# [/help]`, `# [/commands]`) for `-edit` injection to work.
- Use `-all` to group the common launch actions (directory, project, tunnel, etc.).
- Use `pushd`/`popd` when temporarily changing directories within a switch block.
- Use `wt --window 0` to spawn new Windows Terminal tabs for long-running processes (tunnels, claude).
- Keep `$projects` as the first configuration variable after the settings line.
- Per-directory config variables use the naming convention `$<dirName>_<var>` (e.g., `$backend_sln`).
- New snippets in `templates/snippets/` should use `{{placeholders}}` for project-scoped features (`{{dir}}`, `{{switch}}`, `{{label}}`).
