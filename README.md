# MyShortcuts

A PowerShell toolkit for creating launcher scripts that give you quick access to your development projects. Instead of navigating folders, opening IDEs, and starting services manually, run a single command with a switch.

```powershell
MyProject -all        # opens IDE, starts tunnel, launches everything
MyProject -project    # just open the solution in Visual Studio
MyProject -claude     # open Claude Code in the project directory
```

## Getting Started

### 1. Clone and unblock

Clone the repo to a permanent location — this folder becomes your shortcuts hub. The shortcut scripts you create will live here alongside MyShortcuts itself.

```powershell
git clone https://github.com/nicenemo/MyShortcuts.git
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
2. Pick features from a checklist (open directory, open solution, start tunnel, launch Claude Code, etc.)
3. Answer a few config prompts (project folder, solution name)
4. Optionally add custom commands and a group trigger like `-all`

This creates a `.ps1` file in the MyShortcuts folder that you can run by name from any terminal.

> Your generated shortcut scripts are personal to your setup. Consider adding them to a private fork or your own repo, or simply add them to `.gitignore` if you want to keep pulling updates from this repo.

## Usage

| Command | What it does |
|---------|-------------|
| `MyShortcuts -new` | Create a new shortcut script |
| `MyShortcuts -edit` | Add features or custom commands to an existing shortcut |
| `MyShortcuts -list` | List all available shortcuts |
| `MyShortcuts -init` | Set up PATH and configure settings |
| `MyShortcuts -d` | Open the MyShortcuts folder |

## Available Features

When creating or editing a shortcut, you can pick from these built-in features:

| Feature | Switch | What it does |
|---------|--------|-------------|
| Directory | `-d` | Change to project folder |
| Explorer | `-exp` | Open project folder in Windows Explorer |
| Project | `-p` | Open `.sln` in Visual Studio |
| UI | `-ui` | Open frontend project in VS Code |
| Tunnel | `-tunnel` | Start a Cloudflared tunnel |
| Claude | `-claude` | Open Claude Code in the backend |
| Claude UI | `-claudeui` | Open Claude Code in the frontend |
| Compile | `-release` / `-debug` | Build with dotnet |

You can also add **custom commands** for anything project-specific (deploy scripts, database resets, etc.).

## Editing Shortcuts

```powershell
MyShortcuts -edit
```

Select a shortcut, then choose an action:
- **Add predefined feature** — pick from the features above and inject them into the script
- **Add custom command** — add a new switch with a placeholder block, then fill it in
- **Open in editor** — open the script directly

## Requirements

- Windows with PowerShell 5.1+
- [Windows Terminal](https://github.com/microsoft/terminal) (for features that open new tabs)
- [Cloudflared](https://github.com/cloudflare/cloudflared) (only if using the tunnel feature)
