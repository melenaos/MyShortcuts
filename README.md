# MyShortcuts

A PowerShell toolkit for creating launcher scripts that give you quick access to your development projects. Instead of navigating folders, opening IDEs, and starting services manually, run a single command with a switch.

```powershell
MyProject -all        # opens IDE, starts tunnel, launches everything
MyProject -project    # just open the solution in Visual Studio
MyProject -claude     # open Claude Code in the project directory
```

## Getting Started

### 1. Fork and clone

[Fork this repo](https://github.com/melenaos/MyShortcuts/fork), then clone your fork to a permanent location. This folder becomes your shortcuts hub — the scripts you create will live here alongside MyShortcuts.

```powershell
git clone https://github.com/<your-username>/MyShortcuts.git
cd MyShortcuts
Get-ChildItem -Path .\ -Recurse -Filter *.ps1 | Unblock-File
```

### 2. Run it once

```powershell
.\MyShortcuts.ps1 -list
```

The first run automatically adds the MyShortcuts folder to your `PATH` (open a new terminal afterward to pick it up) and, the first time you use a command that needs it, prompts you for your **base development folder** — where your projects live (e.g. `C:\_developing\GitHub`). This is saved to `settings.json`.

You can also edit `settings.json` directly to set:
- **Editor path** — editor for opening scripts (defaults to `notepad.exe`)
- **Tunnel name** — default Cloudflared tunnel name (optional)

Once the folder is on your `PATH`, you can call `MyShortcuts` and any shortcut you create from anywhere.

### 3. Create your first shortcut

```powershell
MyShortcuts -new
```

The interactive wizard walks you through:
1. Name your project
2. Define the project directory
3. Pick a **project type** (e.g. Blank, .NET, Node.js, Python) — this pre-selects a sensible set of features, but nothing is locked
4. Pick features from a checklist (open directory, open solution, start tunnel, launch Claude Code, etc.) — the type's features start ticked; add or remove anything you like
5. Answer config prompts (e.g. solution name — press Enter to accept the suggested default)
6. Optionally add custom commands and a group trigger like `-all`
7. Optionally save your feature selection as a **new project type** for next time

This creates a `.ps1` file in the MyShortcuts folder that you can run by name from any terminal. Commit and push your shortcuts to your fork to keep them backed up.

### Project types

Project types are a named bundle of feature ids that pre-checks the wizard's feature list. They're suggestions, never constraints: the full feature list is always available and you can toggle anything. A `blank` type (no features pre-selected) ships by default so the tool never forces a stack on you.

Built-in types live in `config/projectTypes.json`; anything you save (via "save this selection as a project type" at the end of the wizard) goes into `config/projectTypes.local.json` instead. This split exists so `MyShortcuts -update` can safely refresh the built-in list without wiping out your own saved types.

## Usage

| Command | What it does |
|---------|-------------|
| `MyShortcuts -new` | Create a new shortcut script |
| `MyShortcuts -edit` | Add features or custom commands to an existing shortcut |
| `MyShortcuts -list` | List all available shortcuts |
| `MyShortcuts -d` | Open the MyShortcuts folder |
| `MyShortcuts -update` | Pull the latest engine files from GitHub |

## Available Features

When creating or editing a shortcut, you can pick from these built-in features:

| Feature | Switch | Scope | What it does |
|---------|--------|-------|-------------|
| Directory | `-d` | project | Change to project folder |
| Explorer | `-exp` | project | Open project folder in Windows Explorer |
| Project | `-p` | project | Open `.sln` in Visual Studio |
| Code | `-code` | project | Open project in VS Code |
| Claude | `-claude` | project | Open Claude Code in the project directory |
| Compile | `-release` / `-debug` | project | Build with dotnet |
| Tunnel | `-tunnel` | global | Start a Cloudflared tunnel |
| Azurite | `-azurite` | global | Start Azure storage emulator locally |

**Project** features operate on the shortcut's single project directory. **Global** features are added once and have no directory association.

You can also add **custom commands** for anything project-specific (deploy scripts, database resets, etc.).

## Editing Shortcuts

```powershell
MyShortcuts -edit
```

Select a shortcut, then choose an action:
- **Add predefined feature** — pick from the features above to add to the shortcut
- **Add custom command** — add a new switch with a placeholder block, then fill it in
- **Open in editor** — open the script directly

## Staying Up to Date

The easiest way to pull engine improvements is:

```powershell
MyShortcuts -update
```

This checks the `VERSION` file on GitHub against your local one. If it's newer, it prints the release notes for every version in between (from `CHANGELOG.json`) and asks for confirmation before doing anything. Only after you confirm does it re-download the engine files (`MyShortcuts.ps1`, `lib/`, `templates/snippets/`, `config/features.json`, `config/projectTypes.json`, docs) straight from `melenaos/MyShortcuts`. It never touches `settings.json` or any shortcut script you've created, so it works whether your copy is a git fork or a plain copy. Review the changes with `git diff` afterward before committing.

If you did fork the repo, you can instead pull via git:

```powershell
git remote add upstream https://github.com/melenaos/MyShortcuts.git
git pull upstream main
```

This merges cleanly because upstream updates the framework files (`MyShortcuts.ps1`, `lib/`, `templates/`, `config/`) while your fork only adds shortcut scripts. `settings.json` is gitignored so it stays local and won't conflict.

## Requirements

- Windows with PowerShell 5.1+
- [Windows Terminal](https://github.com/microsoft/terminal) (for features that open new tabs)
- [Cloudflared](https://github.com/cloudflare/cloudflared) (only if using the tunnel feature)
