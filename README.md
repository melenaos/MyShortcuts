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

### 2. Initialize

```powershell
.\MyShortcuts.ps1 -init
```

This adds the MyShortcuts folder to your `PATH` and prompts you to configure:
- **Base development folder** — where your projects live (e.g. `C:\_developing\GitHub`)
- **Editor path** — editor for opening scripts (defaults to `notepad.exe`)
- **Tunnel name** — default Cloudflared tunnel name (optional)

After init, you can call `MyShortcuts` and any shortcut you create from anywhere.

### 3. Create your first shortcut

```powershell
MyShortcuts -new
```

The interactive wizard walks you through:
1. Name your project
2. Define one or more project directories (e.g. `backend`, `ui`, `docs`)
3. Pick features from a checklist (open directory, open solution, start tunnel, launch Claude Code, etc.)
4. If you have multiple directories, choose which features apply to each
5. Answer config prompts per directory (e.g. solution name for each)
6. Optionally add custom commands and a group trigger like `-all`

This creates a `.ps1` file in the MyShortcuts folder that you can run by name from any terminal. Commit and push your shortcuts to your fork to keep them backed up.

### Multi-directory support

Shortcuts support any number of project directories. The first directory gets plain switch names (`-directory`, `-claude`, `-code`), and additional directories get suffixed names (`-directoryui`, `-claudeui`, `-codeui`):

```powershell
MyProject -claude      # open Claude Code in the backend
MyProject -claudeui    # open Claude Code in the UI project
MyProject -codedocs    # open the docs directory in VS Code
```

## Usage

| Command | What it does |
|---------|-------------|
| `MyShortcuts -new` | Create a new shortcut script |
| `MyShortcuts -edit` | Add directories, features, or custom commands to an existing shortcut |
| `MyShortcuts -list` | List all available shortcuts |
| `MyShortcuts -init` | Set up PATH and configure settings |
| `MyShortcuts -d` | Open the MyShortcuts folder |

## Available Features

When creating or editing a shortcut, you can pick from these built-in features:

| Feature | Switch | Scope | What it does |
|---------|--------|-------|-------------|
| Directory | `-d` | per-directory | Change to project folder |
| Explorer | `-exp` | per-directory | Open project folder in Windows Explorer |
| Project | `-p` | per-directory | Open `.sln` in Visual Studio |
| Code | `-code` | per-directory | Open project in VS Code |
| Claude | `-claude` | per-directory | Open Claude Code in the project directory |
| Compile | `-release` / `-debug` | per-directory | Build with dotnet |
| Tunnel | `-tunnel` | global | Start a Cloudflared tunnel |
| Azurite | `-azurite` | global | Start Azure storage emulator locally |

**Per-directory** features are generated for each project directory you assign them to. **Global** features are added once regardless of directories.

You can also add **custom commands** for anything project-specific (deploy scripts, database resets, etc.).

## Editing Shortcuts

```powershell
MyShortcuts -edit
```

Select a shortcut, then choose an action:
- **Add project directory** — add a new directory to the script with its own set of features
- **Add predefined feature** — pick from the features above and choose which directories to apply them to
- **Add custom command** — add a new switch with a placeholder block, then fill it in
- **Open in editor** — open the script directly

## Staying Up to Date

Pull new features and snippets from the upstream repo into your fork:

```powershell
git remote add upstream https://github.com/melenaos/MyShortcuts.git
git pull upstream main
```

This merges cleanly because upstream updates the framework files (`MyShortcuts.ps1`, `lib/`, `templates/`, `config/`) while your fork only adds shortcut scripts. `settings.json` is gitignored so it stays local and won't conflict.

## Requirements

- Windows with PowerShell 5.1+
- [Windows Terminal](https://github.com/microsoft/terminal) (for features that open new tabs)
- [Cloudflared](https://github.com/cloudflare/cloudflared) (only if using the tunnel feature)
