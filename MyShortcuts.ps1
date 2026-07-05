 <#
.Description
Manages scripts for faster access to daily actions

.PARAMETER new
Launches the interactive wizard to create a new shortcut script.

.PARAMETER directory
Shows the MyShorcut directory in Windows Explorer. If `-terminal` parameter is supplied it uses the terminal.

.PARAMETER terminal
Uses the terminal as output

.PARAMETER list
Displays all the available shortcuts

.PARAMETER update
Checks GitHub for a newer engine version and, if found, downloads and overwrites the engine files (MyShortcuts.ps1, lib/, templates/, config/, VERSION) in place. Your own shortcut scripts and settings.json are never touched.

.EXAMPLE
PS> .\MyShortcuts -d

.EXAMPLE
PS> .\MyShortcuts -new

#>

  param (
    [Alias('n')]
    [switch]$new = $false,
    [Alias('d')]
    [switch]$directory = $false,
    [Alias('t')]
    [switch]$terminal = $false,
    [Alias('l')]
    [switch]$list = $false,
    [Alias('e')]
    [switch]$edit = $false,
    [switch]$update = $false
 )


# ==================== Helpers ==================== #

function Expand-Snippet {
    param([string]$SnippetPath, [hashtable]$Vars)
    $content = Get-Content -Path $SnippetPath -Raw
    foreach ($key in $Vars.Keys) {
        $content = $content.Replace("{{$key}}", $Vars[$key])
    }
    return $content
}

function Get-ProjectDirRef {
    param([string[]]$lines)
    foreach ($line in $lines) {
        if ($line -match '^\$projectDir\s*=') {
            return '$projectDir'
        }
    }
    return $null
}

# ==================== Wizard ==================== #

function Exec-NewWizard {
    # Dot-source the interactive menu library
    . "$PSScriptRoot\lib\InteractiveMenu.ps1"

    # Load config
    $features = Get-Content -Path "$PSScriptRoot\config\features.json" -Raw | ConvertFrom-Json

    # --- Step 1: Project name ---
    Write-Host ""
    $projectName = Read-Host -Prompt "  Project name"
    $filename = $projectName
    Write-Host ""

    # --- Step 2: Define directory ---
    $dirPath = Read-Host -Prompt "  Project folder or full path (BasePath: $($s.devDirectory), default: \$projectName\)"
    if ([string]::IsNullOrWhiteSpace($dirPath)) {
        $dirPath = $projectName
    }
    $dirPath = $dirPath.TrimStart('\')
    $isAbsolute = [System.IO.Path]::IsPathRooted($dirPath)

    Write-Host ""

    # --- Step 3: Project type (pre-selects a set of features; nothing is locked) ---
    $typesPath = "$PSScriptRoot\config\projectTypes.json"
    $projectTypes = @()
    if (Test-Path $typesPath) {
        $projectTypes = @(Get-Content -Path $typesPath -Raw | ConvertFrom-Json)
    }

    $typeFeatureIds = @()
    if ($projectTypes.Count -gt 0) {
        $typeOptions = @()
        foreach ($t in $projectTypes) { $typeOptions += $t.label }
        $typeIndex = Show-SelectionMenu -Title "Select a project type" -Options $typeOptions
        $typeFeatureIds = @($projectTypes[$typeIndex].features)
        Write-Host ""
    }

    # --- Step 4: Feature checklist (pre-checked from the project type, fully editable) ---
    $checklistItems = @()
    foreach ($f in $features) {
        $checklistItems += @{ label = $f.label; checked = ($typeFeatureIds -contains $f.id) }
    }

    $selectedIndices = Show-ChecklistMenu -Title "Select features" -Items $checklistItems
    $selectedFeatures = @()
    foreach ($idx in $selectedIndices) {
        $selectedFeatures += $features[$idx]
    }

    Write-Host ""
    Write-Host "  Features selected: $($selectedFeatures.Count)" -ForegroundColor Green
    Write-Host ""

    # --- Step 5: Config prompts ---
    $promptVars = @{}  # varName -> @{ value; useSettings; settingsKey }
    $promptedVars = @{}
    $needsSettings = -not $isAbsolute

    foreach ($f in $selectedFeatures) {
        if (-not $f.prompts) { continue }
        foreach ($pr in $f.prompts) {
            if ($promptedVars.ContainsKey($pr.var)) { continue }
            if ($pr.settingsKey) {
                $defaultVal = $s."$($pr.settingsKey)"
                if ($defaultVal) {
                    $value = Read-Host -Prompt "  $($pr.prompt) (default from settings: $defaultVal, or enter custom)"
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        $promptVars[$pr.var] = @{ value = $defaultVal; useSettings = $true; settingsKey = $pr.settingsKey }
                    } else {
                        $promptVars[$pr.var] = @{ value = $value; useSettings = $false }
                    }
                } else {
                    $value = Read-Host -Prompt "  $($pr.prompt)"
                    $promptVars[$pr.var] = @{ value = $value; useSettings = $false }
                }
                $needsSettings = $true
            } elseif ($pr.default) {
                $defaultVal = $pr.default.Replace("{{projectName}}", $projectName)
                $value = Read-Host -Prompt "  $($pr.prompt) (Enter = $defaultVal)"
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $value = $defaultVal
                }
                $promptVars[$pr.var] = @{ value = $value; useSettings = $false }
            } else {
                $value = Read-Host -Prompt "  $($pr.prompt)"
                $promptVars[$pr.var] = @{ value = $value; useSettings = $false }
            }
            $promptedVars[$pr.var] = $true
        }
    }

    # --- Step 6: Custom commands ---
    $customCommands = @()
    Write-Host ""
    $addCustom = Read-Host -Prompt "  Add a custom command? (y/n)"
    while ($addCustom -eq 'y') {
        $cmdName = Read-Host -Prompt "    Switch name (e.g. deploy)"
        $cmdAlias = Read-Host -Prompt "    Alias (leave empty to skip)"
        $cmdDesc = Read-Host -Prompt "    Description (e.g. Deploy to production)"
        $cmdType = Read-Host -Prompt "    Accept a value? (leave empty for switch, or enter type: string, int)"

        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            $customCommands += @{
                name = $cmdName
                alias = if ([string]::IsNullOrWhiteSpace($cmdAlias)) { $null } else { $cmdAlias }
                description = $cmdDesc
                type = if ([string]::IsNullOrWhiteSpace($cmdType)) { $null } else { $cmdType.Trim().ToLower() }
            }
        }
        $addCustom = Read-Host -Prompt "  Add another custom command? (y/n)"
    }

    # --- Step 7: Group trigger (optional) ---
    Write-Host ""
    $triggerName = Read-Host -Prompt "  Group trigger switch name (leave empty to skip)"
    $triggerFeatures = @()

    if (-not [string]::IsNullOrWhiteSpace($triggerName)) {
        # Show checklist for which features the group trigger activates
        $triggerItems = @()
        foreach ($f in $selectedFeatures) {
            $defaultTrigger = ($null -eq $f.inGroupByDefault) -or $f.inGroupByDefault
            $triggerItems += @{ label = $f.label; checked = $defaultTrigger }
        }

        $triggerIndices = Show-ChecklistMenu -Title "Which features should '-$triggerName' activate?" -Items $triggerItems
        foreach ($idx in $triggerIndices) {
            $triggerFeatures += $selectedFeatures[$idx]
        }
    }

    Write-Host ""

    # --- Check if file exists ---
    $filepath = "$PSScriptRoot\$filename.ps1"
    if (Test-Path -Path "$filepath" -PathType Leaf) {
        Write-Host "  Shortcut already exists" -ForegroundColor DarkYellow
        $overwrite = Read-Host -Prompt "  Overwrite? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Host "  Cancelled." -ForegroundColor DarkYellow
            return
        }
    }

    # --- Step 8: Assemble the script ---
    $script = ""

    # Build param block
    $paramLines = @()

    # Add group trigger param (if set)
    if (-not [string]::IsNullOrWhiteSpace($triggerName)) {
        $triggerAlias = if ($triggerName -eq "all") { "a" } else { $null }
        if ($triggerAlias) {
            $paramLines += "    [Alias('$triggerAlias')]"
        }
        $paramLines += "    [switch]`$$triggerName = `$false,"
    }

    # Collect all params from selected features
    $addedParams = @{}
    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            if ($addedParams.ContainsKey($p.name)) { continue }
            $addedParams[$p.name] = $true
            if ($p.alias) {
                $paramLines += "    [Alias('$($p.alias)')]"
            }
            $paramLines += "    [switch]`$$($p.name) = `$false,"
        }
    }

    # Add custom command params
    foreach ($cmd in $customCommands) {
        if ($cmd.alias) {
            $paramLines += "    [Alias('$($cmd.alias)')]"
        }
        if ($cmd.type -eq 'string') {
            $paramLines += "    [string]`$$($cmd.name) = `"`","
        } elseif ($cmd.type -eq 'int') {
            $paramLines += "    [int]`$$($cmd.name) = 0,"
        } else {
            $paramLines += "    [switch]`$$($cmd.name) = `$false,"
        }
    }

    # Remove trailing comma from last param line
    if ($paramLines.Count -gt 0) {
        $paramLines[$paramLines.Count - 1] = $paramLines[$paramLines.Count - 1].TrimEnd(',')
    }

    $script += "param (" + "`r`n"
    $script += ($paramLines -join "`r`n") + "`r`n"
    $script += "    # [/params]" + "`r`n"
    $script += " )" + "`r`n"
    $script += "`r`n"
    $script += "`r`n"

    # Config header
    $script += "# =============== Script =============== #" + "`r`n"

    if ($needsSettings) {
        $script += "`$settings = Get-Content -Path `"`$PSScriptRoot\settings.json`" -Raw | ConvertFrom-Json" + "`r`n"
    }

    # Project directory
    if ($isAbsolute) {
        $script += "`$projectDir = `"$dirPath`"" + "`r`n"
    } else {
        $script += "`$projectDir = `"`$(`$settings.devDirectory)\$dirPath`"" + "`r`n"
    }

    # Config vars from prompts
    foreach ($varName in $promptVars.Keys) {
        $entry = $promptVars[$varName]
        if ($entry.useSettings) {
            $script += "`$$varName = `$settings.$($entry.settingsKey)" + "`r`n"
        } else {
            $script += "`$$varName = `"$($entry.value)`"" + "`r`n"
        }
    }

    $script += "# ===== C O N F I G U R A T I O N ====== #" + "`r`n"
    $script += "`r`n"

    # Help block
    $script += "# Show help if no parameters provided" + "`r`n"
    $script += "if (`$PSBoundParameters.Count -eq 0) {" + "`r`n"
    $script += "    Write-Host `"`n--- $projectName ---`" -ForegroundColor Cyan" + "`r`n"
    $script += "    Write-Host `"Usage: .\$filename.ps1 [-switch]`"" + "`r`n"
    $script += "    Write-Host `"Available Switches:`"" + "`r`n"

    # Group trigger line
    if (-not [string]::IsNullOrWhiteSpace($triggerName)) {
        $triggerAliasPart = if ($triggerAlias) { "-$triggerAlias,  " } else { "      " }
        $script += "    Write-Host `"  $triggerAliasPart-$triggerName`" -ForegroundColor Cyan -NoNewline" + "`r`n"
        $script += "    Write-Host `"  Run all launch actions`"" + "`r`n"
    }

    # Feature help lines
    $addedHelpParams = @{}
    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            if ($addedHelpParams.ContainsKey($p.name)) { continue }
            $addedHelpParams[$p.name] = $true
            $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
            $desc = ($f.label -split ' — ')[0]
            $script += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline" + "`r`n"
            $script += "    Write-Host `"  $desc`"" + "`r`n"
        }
    }

    # Custom command help lines
    foreach ($cmd in $customCommands) {
        $aliasPart = if ($cmd.alias) { "-$($cmd.alias),  " } else { "      " }
        $desc = if ($cmd.description) { $cmd.description } else { $cmd.name }
        $valuePart = if ($cmd.type) { " <value>" } else { "" }
        $script += "    Write-Host `"  $aliasPart-$($cmd.name)$valuePart`" -ForegroundColor Cyan -NoNewline" + "`r`n"
        $script += "    Write-Host `"  $desc`"" + "`r`n"
    }

    $script += "    # [/help]" + "`r`n"
    $script += "    Write-Host `"`"" + "`r`n"
    $script += "    exit" + "`r`n"
    $script += "}" + "`r`n"
    $script += "`r`n"

    # Group trigger block
    if ($triggerFeatures.Count -gt 0) {
        $script += "# Group trigger" + "`r`n"
        $script += "if(`$$triggerName){" + "`r`n"
        foreach ($tf in $triggerFeatures) {
            $primaryParam = $tf.params[0].name
            $script += "    `$$primaryParam = `$true" + "`r`n"
        }
        $script += "}" + "`r`n"
        $script += "`r`n"
    }

    # Feature snippet blocks
    foreach ($f in $selectedFeatures) {
        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (-not (Test-Path $snippetPath)) { continue }

        # Every snippet is templated. Project features also get dir/label;
        # global features have no directory context.
        $vars = @{ switch = $f.params[0].name }
        if ($f.scope -eq "project") {
            $vars["dir"] = '$projectDir'
            $vars["label"] = $projectName
        }

        # Vars from prompts (like sln, tunnelName)
        if ($f.prompts) {
            foreach ($pr in $f.prompts) {
                $vars[$pr.var] = "`$$($pr.var)"
            }
        }

        # Extra snippet placeholders declared by the feature (data-driven)
        if ($f.placeholders) {
            foreach ($ph in $f.placeholders.PSObject.Properties) {
                $vars[$ph.Name] = $ph.Value
            }
        }

        $expanded = Expand-Snippet -SnippetPath $snippetPath -Vars $vars
        $script += $expanded + "`r`n"
    }

    # Custom command placeholder blocks
    foreach ($cmd in $customCommands) {
        $desc = if ($cmd.description) { $cmd.description } else { $cmd.name }
        $script += "# $desc" + "`r`n"
        $script += "if(`$$($cmd.name)){" + "`r`n"
        $script += "    pushd" + "`r`n"
        $script += "    cd `"`$projectDir`"" + "`r`n"
        if ($cmd.type) {
            $script += "    # Value passed: `$$($cmd.name)" + "`r`n"
        }
        $script += "    # TODO: Add your command here" + "`r`n"
        $script += "    popd" + "`r`n"
        $script += "}" + "`r`n"
        $script += "`r`n"
    }

    $script += "# [/commands]" + "`r`n"

    # --- Write the file ---
    Set-Content -Path $filepath -Value $script -Encoding UTF8

    Write-Host ""
    Write-Host "  Created: $filepath" -ForegroundColor Green

    # --- Step 9: Optionally save this selection as a reusable project type ---
    if ($selectedFeatures.Count -gt 0) {
        Write-Host ""
        $saveType = Read-Host -Prompt "  Save this selection as a project type? (name, or Enter to skip)"
        if (-not [string]::IsNullOrWhiteSpace($saveType)) {
            $typeId = ($saveType.Trim() -replace '\s+', '-').ToLower()
            $existingTypes = @()
            if (Test-Path $typesPath) {
                $existingTypes = @(Get-Content -Path $typesPath -Raw | ConvertFrom-Json)
            }
            # Replace an existing type with the same id, then append the new one
            $existingTypes = @($existingTypes | Where-Object { $_.id -ne $typeId })
            $existingTypes += [pscustomobject]@{
                id       = $typeId
                label    = $saveType.Trim()
                features = @($selectedFeatures | ForEach-Object { $_.id })
            }
            # ConvertTo-Json collapses a single-element array to an object; force an array wrapper
            ConvertTo-Json @($existingTypes) -Depth 5 | Set-Content -Path $typesPath -Encoding UTF8
            Write-Host "  Saved project type '$typeId'." -ForegroundColor Green
        }
    }

    Write-Host ""

    # Open in editor
    & "$editorPath" "$filepath"
}

# ==================== Update ==================== #

$UpdateRepoOwner = "melenaos"
$UpdateRepoName = "MyShortcuts"
$UpdateBranch = "main"

function Get-LocalVersion {
    $versionPath = "$PSScriptRoot\VERSION"
    if (Test-Path -Path $versionPath -PathType Leaf) {
        return (Get-Content -Path $versionPath -Raw).Trim()
    }
    return "0.0.0"
}

function Get-EngineFileList {
    param([string]$RawBase)

    # Fixed engine-owned files, always synced
    $files = @(
        "VERSION",
        "CHANGELOG.json",
        "MyShortcuts.ps1",
        "lib/InteractiveMenu.ps1",
        "config/features.json",
        "config/projectTypes.json",
        "CLAUDE.md",
        "README.md"
    )

    # Snippet files are discovered dynamically so new snippets get pulled automatically
    try {
        $apiUri = "https://api.github.com/repos/$UpdateRepoOwner/$UpdateRepoName/contents/templates/snippets?ref=$UpdateBranch"
        $snippetEntries = Invoke-RestMethod -Uri $apiUri -UseBasicParsing -Headers @{ "User-Agent" = "MyShortcuts-Update" }
        foreach ($entry in $snippetEntries) {
            if ($entry.type -eq "file") {
                $files += "templates/snippets/$($entry.name)"
            }
        }
    } catch {
        Write-Host "  Warning: could not list templates/snippets from GitHub; skipping snippet sync." -ForegroundColor DarkYellow
    }

    return $files
}

function Exec-Update {
    $rawBase = "https://raw.githubusercontent.com/$UpdateRepoOwner/$UpdateRepoName/$UpdateBranch"

    Write-Host ""
    Write-Host "  Checking for updates..." -ForegroundColor Cyan

    try {
        $remoteVersion = (Invoke-WebRequest -Uri "$rawBase/VERSION" -UseBasicParsing).Content.Trim()
    } catch {
        Write-Host "  Could not reach GitHub. Check your internet connection." -ForegroundColor Red
        Write-Host ""
        return
    }

    $localVersion = Get-LocalVersion

    if ($remoteVersion -eq $localVersion) {
        Write-Host "  Already up to date (v$localVersion)." -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host "  Update available: v$localVersion -> v$remoteVersion" -ForegroundColor Yellow
    Write-Host ""

    # Show release notes for every version between local (exclusive) and remote (inclusive)
    try {
        $changelog = @(Invoke-RestMethod -Uri "$rawBase/CHANGELOG.json" -UseBasicParsing -Headers @{ "User-Agent" = "MyShortcuts-Update" })
        $localV = [version]$localVersion
        $remoteV = [version]$remoteVersion
        $relevant = @($changelog | Where-Object {
            $entryV = [version]$_.version
            $entryV -gt $localV -and $entryV -le $remoteV
        } | Sort-Object { [version]$_.version })

        if ($relevant.Count -gt 0) {
            Write-Host "  What's new:" -ForegroundColor Cyan
            foreach ($entry in $relevant) {
                Write-Host "    v$($entry.version)" -ForegroundColor Cyan
                foreach ($note in $entry.notes) {
                    Write-Host "      - $note"
                }
            }
            Write-Host ""
        }
    } catch {
        Write-Host "  (Could not load release notes.)" -ForegroundColor DarkYellow
        Write-Host ""
    }

    $confirm = Read-Host -Prompt "  Download and overwrite engine files? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "  Cancelled." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    $files = Get-EngineFileList -RawBase $rawBase

    foreach ($relPath in $files) {
        $localPath = Join-Path $PSScriptRoot $relPath
        $localDir = Split-Path $localPath -Parent
        if ($localDir -and -not (Test-Path $localDir)) {
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        }
        try {
            $content = (Invoke-WebRequest -Uri "$rawBase/$relPath" -UseBasicParsing).Content
            # Set-Content -Encoding UTF8 adds a BOM on Windows PowerShell; write raw bytes instead
            [System.IO.File]::WriteAllText($localPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Updated: $relPath" -ForegroundColor DarkGray
        } catch {
            Write-Host "  Failed to update: $relPath" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Updated to v$remoteVersion." -ForegroundColor Green
    Write-Host "  Review changes with 'git diff' before committing." -ForegroundColor DarkGray
    Write-Host ""
}

function Get-Settings {
    $settingsPath = "$PSScriptRoot\settings.json";
    if (Test-Path -Path "$settingsPath" -PathType Leaf)
    {
        try{
            return Get-Content -Path "$settingsPath" -Raw | ConvertFrom-Json
        }
        catch{
            Write-Host "Warning! Settings.json is not well formated. Default settings applied." -ForegroundColor DarkYellow
        }
    }
    # Create default settings file if it doesn't exist
    $defaults = @{
        devDirectory = ""
        editorPath = "notepad.exe"
    }
    $defaults | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
    return Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
}

function Check-EnvPath {
    $pathVars = $Env:Path.Split(';')
    ForEach ($path in $pathVars){
        if($path.TrimEnd('\') -eq $PSScriptRoot){
            return $true;
        }
    }
    return $false
}

function Exec-Directory {
    if($terminal){
        cd $PSScriptRoot
        ls
    }else{
        Invoke-Item $PSScriptRoot
    }
}

function Find-MarkerLines {
    param([string[]]$lines)
    $markers = @{ params = -1; help = -1; commands = -1 }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '# [/params]') { $markers.params = $i }
        elseif ($trimmed -eq '# [/help]') { $markers.help = $i }
        elseif ($trimmed -eq '# [/commands]') { $markers.commands = $i }
    }
    return $markers
}

function Get-ExistingParams {
    param([string[]]$lines)
    $params = @()
    foreach ($line in $lines) {
        if ($line -match '\[(switch|string|int)\]\$(\w+)') {
            $params += $Matches[2]
        }
    }
    return $params
}

function Get-ExistingConfigVars {
    param([string[]]$lines)
    $vars = @()
    foreach ($line in $lines) {
        if ($line -match '^\$(\w+)\s*=') {
            $vars += $Matches[1]
        }
    }
    return $vars
}

function Find-GroupTrigger {
    param([System.Collections.ArrayList]$lines)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '# Group trigger') {
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j].Trim() -eq '}') {
                    return @{ start = $i; ifLine = $i + 1; end = $j }
                }
            }
        }
    }
    return $null
}

function Insert-Lines {
    param(
        [System.Collections.ArrayList]$lines,
        [int]$index,
        [string[]]$newLines
    )
    for ($i = $newLines.Count - 1; $i -ge 0; $i--) {
        $lines.Insert($index, $newLines[$i])
    }
}

function Exec-AddFeature {
    param([string]$FilePath)

    . "$PSScriptRoot\lib\InteractiveMenu.ps1"

    $lines = [System.Collections.ArrayList]@(Get-Content -Path $FilePath)
    $markers = Find-MarkerLines -lines $lines
    if ($markers.params -eq -1 -or $markers.help -eq -1 -or $markers.commands -eq -1) {
        Write-Host ""
        Write-Host "  This script doesn't have injection markers." -ForegroundColor DarkYellow
        Write-Host "  Only scripts created with the latest wizard support feature injection." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    # Load features and filter out already-present ones
    $features = Get-Content -Path "$PSScriptRoot\config\features.json" -Raw | ConvertFrom-Json
    $existingParams = Get-ExistingParams -lines $lines
    $existingVars = Get-ExistingConfigVars -lines $lines
    $projectDirRef = Get-ProjectDirRef -lines $lines
    $projectNameGuess = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    $availableFeatures = @()
    foreach ($f in $features) {
        if ($f.scope -eq "project" -and -not $projectDirRef) { continue }
        $alreadyPresent = $false
        foreach ($p in $f.params) {
            if ($existingParams -contains $p.name) {
                $alreadyPresent = $true
                break
            }
        }
        if (-not $alreadyPresent) {
            $availableFeatures += $f
        }
    }

    if ($availableFeatures.Count -eq 0) {
        Write-Host ""
        Write-Host "  All predefined features are already present." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    # Show checklist
    $checklistItems = @()
    foreach ($f in $availableFeatures) {
        $checklistItems += @{ label = $f.label; checked = $false }
    }

    $selectedIndices = Show-ChecklistMenu -Title "Select features to add" -Items $checklistItems
    if ($selectedIndices.Count -eq 0) {
        Write-Host ""
        Write-Host "  No features selected." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    $selectedFeatures = @()
    foreach ($idx in $selectedIndices) {
        $selectedFeatures += $availableFeatures[$idx]
    }

    # Prompt for needed config variables
    $configLinesToAdd = @()
    $promptedVars = @{}
    $needsSettingsLine = $false

    # Check if $settings loading line already exists
    $hasSettings = $false
    foreach ($line in $lines) {
        if ($line -match '\$settings\s*=.*settings\.json') {
            $hasSettings = $true
            break
        }
    }

    Write-Host ""
    foreach ($f in $selectedFeatures) {
        if (-not $f.prompts) { continue }
        foreach ($pr in $f.prompts) {
            if ($existingVars -contains $pr.var -or $promptedVars.ContainsKey($pr.var)) { continue }
            if ($pr.settingsKey) {
                $value = Read-Host -Prompt "  $($pr.prompt)"
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $configLinesToAdd += "`$$($pr.var) = `$settings.$($pr.settingsKey)"
                    $needsSettingsLine = $true
                } else {
                    $configLinesToAdd += "`$$($pr.var) = `"$value`""
                }
            } elseif ($pr.default) {
                $defaultVal = $pr.default.Replace("{{projectName}}", $projectNameGuess)
                $value = Read-Host -Prompt "  $($pr.prompt) (Enter = $defaultVal)"
                if ([string]::IsNullOrWhiteSpace($value)) {
                    $value = $defaultVal
                }
                $configLinesToAdd += "`$$($pr.var) = `"$value`""
            } else {
                $value = Read-Host -Prompt "  $($pr.prompt)"
                $configLinesToAdd += "`$$($pr.var) = `"$value`""
            }
            $promptedVars[$pr.var] = $true
        }
    }

    # Build injection content
    $newParamLines = @()
    $newHelpLines = @()
    $newCommandLines = @()

    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            if ($p.alias) {
                $newParamLines += "    [Alias('$($p.alias)')]"
            }
            $newParamLines += "    [switch]`$$($p.name) = `$false,"
        }
        foreach ($p in $f.params) {
            $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
            $desc = ($f.label -split ' — ')[0]
            $newHelpLines += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline"
            $newHelpLines += "    Write-Host `"  $desc`""
        }

        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (Test-Path $snippetPath) {
            # Every snippet is templated; project features also get dir/label.
            $vars = @{ switch = $f.params[0].name }
            if ($f.scope -eq "project") {
                $vars["dir"] = $projectDirRef
                $vars["label"] = $projectNameGuess
            }
            if ($f.prompts) {
                foreach ($pr in $f.prompts) {
                    $vars[$pr.var] = "`$$($pr.var)"
                }
            }
            if ($f.placeholders) {
                foreach ($ph in $f.placeholders.PSObject.Properties) {
                    $vars[$ph.Name] = $ph.Value
                }
            }
            $expanded = Expand-Snippet -SnippetPath $snippetPath -Vars $vars
            $newCommandLines += $expanded.Split("`r`n", [System.StringSplitOptions]::None)
            $newCommandLines += ""
        }
    }

    # Remove trailing comma from last new param line
    if ($newParamLines.Count -gt 0) {
        $newParamLines[$newParamLines.Count - 1] = $newParamLines[$newParamLines.Count - 1].TrimEnd(',')
    }

    # --- Inject in reverse index order (bottom to top) ---

    # 1. Command snippets before # [/commands]
    if ($newCommandLines.Count -gt 0) {
        Insert-Lines -lines $lines -index $markers.commands -newLines $newCommandLines
    }

    # 2. Add to group trigger if one exists
    $groupTrigger = Find-GroupTrigger -lines $lines
    if ($groupTrigger) {
        $triggerLines = @()
        foreach ($f in $selectedFeatures) {
            if (($null -eq $f.inGroupByDefault) -or $f.inGroupByDefault) {
                $triggerLines += "    `$$($f.params[0].name) = `$true"
            }
        }
        if ($triggerLines.Count -gt 0) {
            Insert-Lines -lines $lines -index $groupTrigger.end -newLines $triggerLines
        }
    }

    # 3. Help lines before # [/help]
    if ($newHelpLines.Count -gt 0) {
        Insert-Lines -lines $lines -index $markers.help -newLines $newHelpLines
    }

    # 4. Config variables before "# ===== C O N F I G U R A T I O N ====== #"
    if ($configLinesToAdd.Count -gt 0 -or ($needsSettingsLine -and -not $hasSettings)) {
        $configMarkerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '# ===== C O N F I G U R A T I O N ====== #') {
                $configMarkerIdx = $i
                break
            }
        }
        if ($configMarkerIdx -ge 0) {
            if ($configLinesToAdd.Count -gt 0) {
                Insert-Lines -lines $lines -index $configMarkerIdx -newLines $configLinesToAdd
            }
            # Add $settings loading line if needed and not present
            if ($needsSettingsLine -and -not $hasSettings) {
                $scriptHeaderIdx = -1
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i].Trim() -eq '# =============== Script =============== #') {
                        $scriptHeaderIdx = $i
                        break
                    }
                }
                if ($scriptHeaderIdx -ge 0) {
                    $settingsLine = '$settings = Get-Content -Path "$PSScriptRoot\settings.json" -Raw | ConvertFrom-Json'
                    $lines.Insert($scriptHeaderIdx + 1, $settingsLine)
                }
            }
        }
    }

    # 5. Params before # [/params] — add comma to existing last param
    if ($newParamLines.Count -gt 0) {
        $markers = Find-MarkerLines -lines $lines
        $lastParamIdx = $markers.params - 1
        if ($lastParamIdx -ge 0 -and $lines[$lastParamIdx] -match '\[(switch|string|int)\]') {
            $lines[$lastParamIdx] = $lines[$lastParamIdx].TrimEnd() + ","
        }
        Insert-Lines -lines $lines -index $markers.params -newLines $newParamLines
    }

    # Write back
    $lines | Set-Content -Path $FilePath -Encoding UTF8

    Write-Host ""
    Write-Host "  Features added successfully." -ForegroundColor Green
    Write-Host ""
}

function Exec-AddCustomCommand {
    param([string]$FilePath)

    $lines = [System.Collections.ArrayList]@(Get-Content -Path $FilePath)
    $markers = Find-MarkerLines -lines $lines
    if ($markers.params -eq -1 -or $markers.help -eq -1 -or $markers.commands -eq -1) {
        Write-Host ""
        Write-Host "  This script doesn't have injection markers." -ForegroundColor DarkYellow
        Write-Host "  Only scripts created with the latest wizard support feature injection." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    $projectDirRef = Get-ProjectDirRef -lines $lines

    Write-Host ""
    $cmdName = Read-Host -Prompt "  Switch name (e.g. deploy)"
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return }
    $cmdAlias = Read-Host -Prompt "  Alias (leave empty to skip)"
    $cmdDesc = Read-Host -Prompt "  Description"
    if ([string]::IsNullOrWhiteSpace($cmdDesc)) { $cmdDesc = $cmdName }
    $cmdType = Read-Host -Prompt "  Accept a value? (leave empty for switch, or enter type: string, int)"
    $cmdType = if ([string]::IsNullOrWhiteSpace($cmdType)) { $null } else { $cmdType.Trim().ToLower() }

    # Build param lines
    $newParamLines = @()
    if (-not [string]::IsNullOrWhiteSpace($cmdAlias)) {
        $newParamLines += "    [Alias('$cmdAlias')]"
    }
    if ($cmdType -eq 'string') {
        $newParamLines += "    [string]`$$cmdName = `"`""
    } elseif ($cmdType -eq 'int') {
        $newParamLines += "    [int]`$$cmdName = 0"
    } else {
        $newParamLines += "    [switch]`$$cmdName = `$false"
    }

    # Build help lines
    $aliasPart = if (-not [string]::IsNullOrWhiteSpace($cmdAlias)) { "-$cmdAlias,  " } else { "      " }
    $valuePart = if ($cmdType) { " <value>" } else { "" }
    $newHelpLines = @(
        "    Write-Host `"  $aliasPart-$cmdName$valuePart`" -ForegroundColor Cyan -NoNewline"
        "    Write-Host `"  $cmdDesc`""
    )

    # Build command block
    $newCommandLines = @(
        "# $cmdDesc"
        "if(`$$cmdName){"
    )
    if ($projectDirRef) {
        $newCommandLines += @(
            "    pushd"
            "    cd `"$projectDirRef`""
        )
    }
    if ($cmdType) {
        $newCommandLines += "    # Value passed: `$$cmdName"
    }
    $newCommandLines += @(
        "    # TODO: Add your command here"
    )
    if ($projectDirRef) {
        $newCommandLines += "    popd"
    }
    $newCommandLines += @(
        "}"
        ""
    )

    # Inject in reverse index order
    Insert-Lines -lines $lines -index $markers.commands -newLines $newCommandLines
    Insert-Lines -lines $lines -index $markers.help -newLines $newHelpLines

    # Add comma to existing last param line
    $lastParamIdx = $markers.params - 1
    if ($lastParamIdx -ge 0 -and $lines[$lastParamIdx] -match '\[(switch|string|int)\]') {
        $lines[$lastParamIdx] = $lines[$lastParamIdx].TrimEnd() + ","
    }
    Insert-Lines -lines $lines -index $markers.params -newLines $newParamLines

    # Write back
    $lines | Set-Content -Path $FilePath -Encoding UTF8

    Write-Host ""
    Write-Host "  Custom command '-$cmdName' added." -ForegroundColor Green
    Write-Host ""

    # Open in editor so the user can fill in the TODO block
    & "$editorPath" "$FilePath"
}
function Exec-Edit{
    . "$PSScriptRoot\lib\InteractiveMenu.ps1"

    $list = Get-ChildItem -Path "$PSScriptRoot\" -recurse -depth 0 -Include *.bat,*.ps1 | `
        Where-Object { $_.PSIsContainer -eq $false }

    $options = @()
    foreach ($n in $list) {
        $options += Split-Path $n -leaf
    }

    $selectedIndex = Show-SelectionMenu -Title "Select a shortcut to edit" -Options $options
    $file = $list[$selectedIndex]

    $actions = @("Add predefined feature", "Add custom command", "Open in editor")
    $actionIndex = Show-SelectionMenu -Title "What do you want to do?" -Options $actions

    switch ($actionIndex) {
        0 { Exec-AddFeature -FilePath $file.FullName }
        1 { Exec-AddCustomCommand -FilePath $file.FullName }
        2 { & "$editorPath" "$($file.FullName)" }
    }
}

function Exec-List{
     $list = Get-ChildItem -Path "$PSScriptRoot\" | `
        Where-Object { $_.PSIsContainer -eq $false }

        Write-Host " Available Shortcuts" -ForegroundColor DarkGreen

        ForEach($n in $list){
            $filename = Split-Path $n -leaf
            if( $n.Extension -eq ".bat" -or $n.Extension -eq ".ps1" -and $filename -ne "MyShortcuts.ps1"){
                Write-Host " - $filename" -ForegroundColor Cyan
            }
        }
}


# ------------
# --  Main  --
# ------------

# Auto-register MyShortcuts directory in PATH on first run
if (-not (Check-EnvPath)) {
    [Environment]::SetEnvironmentVariable("Path", $PSScriptRoot + ";" + $Env:Path, "User")
    $Env:Path = $PSScriptRoot + ";" + $Env:Path
}

# Get Settings
$s = Get-Settings
$editorPath = if ($s.editorPath) { $s.editorPath } else { 'notepad.exe' }

# First-run: prompt for devDirectory if not configured
if (-not $s.devDirectory -and -not $directory -and -not $list -and -not $update) {
    Write-Host ""
    Write-Host "  Base development folder is not configured." -ForegroundColor DarkYellow
    $devDir = Read-Host -Prompt "  Enter your base development folder (e.g. C:\GitHub)"
    if (-not [string]::IsNullOrWhiteSpace($devDir)) {
        $settingsPath = "$PSScriptRoot\settings.json"
        $settingsHash = @{}
        $s.PSObject.Properties | ForEach-Object { $settingsHash[$_.Name] = $_.Value }
        $settingsHash["devDirectory"] = $devDir
        $settingsHash | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
        $s = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    }
    Write-Host ""
}


if ($directory){
   Exec-Directory
}
elseif ($edit){
   Exec-Edit
}
elseif ($new){
   Exec-NewWizard
}
elseif ($list){
   Exec-List
}
elseif ($update){
   Exec-Update
}
else{
    Write-Host "Execute 'Get-Help MyShortcut.ps1 -full' to learn more"
}
