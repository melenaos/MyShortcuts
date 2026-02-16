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
    [Alias('i')]
    [switch]$init = $false
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

function Get-SwitchName {
    param([string]$BaseName, [string]$DirName, [bool]$IsPrimary)
    if ($IsPrimary) { return $BaseName }
    return "$BaseName$DirName"
}

function Get-ExistingProjects {
    param([string[]]$lines)
    $projects = [ordered]@{}
    $inProjects = $false
    foreach ($line in $lines) {
        if ($line -match '\$projects\s*=\s*\[ordered\]@\{') {
            $inProjects = $true
            continue
        }
        if ($inProjects) {
            if ($line.Trim() -eq '# [/projects]' -or $line.Trim() -eq '}') {
                break
            }
            if ($line -match '^\s*"(\w+)"\s*=\s*"(.+)"') {
                $projects[$Matches[1]] = $Matches[2]
            }
        }
    }
    return $projects
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

    # --- Step 2: Define directories ---
    $directories = @()
    $dirIndex = 0
    do {
        $dirName = Read-Host -Prompt "  Directory name (e.g. backend)"
        if ([string]::IsNullOrWhiteSpace($dirName)) {
            if ($directories.Count -eq 0) {
                Write-Host "  At least one directory is required." -ForegroundColor DarkYellow
                continue
            }
            break
        }
        $dirPath = Read-Host -Prompt "  Project folder or full path (BasePath: $($s.devDirectory), default: \$projectName\)"
        if ([string]::IsNullOrWhiteSpace($dirPath)) {
            $dirPath = if ($dirIndex -eq 0) { $projectName } else { "$projectName-$($dirName.Substring(0,1).ToUpper() + $dirName.Substring(1))" }
        }
        $dirPath = $dirPath.TrimStart('\')
        $isAbsolute = [System.IO.Path]::IsPathRooted($dirPath)
        $directories += @{
            name = $dirName
            path = $dirPath
            isAbsolute = $isAbsolute
        }
        $dirIndex++
        $addMore = Read-Host -Prompt "  Add another directory? (y/n)"
    } while ($addMore -eq 'y')

    Write-Host ""

    # --- Step 3: Feature checklist ---
    $checklistItems = @()
    foreach ($f in $features) {
        $checklistItems += @{ label = $f.label; checked = $false }
    }

    $selectedIndices = Show-ChecklistMenu -Title "Select features" -Items $checklistItems
    $selectedFeatures = @()
    foreach ($idx in $selectedIndices) {
        $selectedFeatures += $features[$idx]
    }

    Write-Host ""
    Write-Host "  Features selected: $($selectedFeatures.Count)" -ForegroundColor Green
    Write-Host ""

    # --- Step 4: Per-directory feature assignment ---
    # Map: featureId -> array of directory names
    $featureDirMap = @{}

    $projectFeatures = @($selectedFeatures | Where-Object { $_.scope -eq "project" })
    $globalFeatures = @($selectedFeatures | Where-Object { $_.scope -eq "global" })

    if ($directories.Count -gt 1 -and $projectFeatures.Count -gt 0) {
        foreach ($f in $projectFeatures) {
            $dirItems = @()
            foreach ($dir in $directories) {
                $dirItems += @{ label = $dir.name; checked = $true }
            }
            $dirIndices = Show-ChecklistMenu -Title "Apply '$($f.label)' to which directories?" -Items $dirItems
            $featureDirMap[$f.id] = @()
            foreach ($idx in $dirIndices) {
                $featureDirMap[$f.id] += $directories[$idx].name
            }
        }
    } else {
        foreach ($f in $projectFeatures) {
            $featureDirMap[$f.id] = @($directories[0].name)
        }
    }

    # --- Step 5: Config prompts ---
    $perProjectVars = @{}  # dirName -> @{ varName = value }
    $globalVars = @{}
    $promptedGlobalVars = @{}
    $needsTunnel = $false
    $tunnelUseSettings = $false

    foreach ($f in $selectedFeatures) {
        if (-not $f.prompts) { continue }
        foreach ($pr in $f.prompts) {
            if ($pr.perProject) {
                # Prompt once per directory that has this feature
                $dirNames = $featureDirMap[$f.id]
                if (-not $dirNames) { continue }
                foreach ($dName in $dirNames) {
                    if (-not $perProjectVars[$dName]) { $perProjectVars[$dName] = @{} }
                    $varKey = "$($dName)_$($pr.var)"
                    if ($perProjectVars[$dName].ContainsKey($pr.var)) { continue }
                    $value = Read-Host -Prompt "  $($pr.prompt) for '$dName' (e.g. $projectName.sln)"
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        $value = "$projectName.sln"
                    }
                    $perProjectVars[$dName][$pr.var] = $value
                }
            } else {
                # Global prompt
                if ($promptedGlobalVars.ContainsKey($pr.var)) { continue }
                if ($pr.settingsKey) {
                    $defaultVal = $s."$($pr.settingsKey)"
                    if ($defaultVal) {
                        $value = Read-Host -Prompt "  $($pr.prompt) (default from settings: $defaultVal, or enter custom)"
                        if ([string]::IsNullOrWhiteSpace($value)) {
                            $globalVars[$pr.var] = @{ value = $defaultVal; useSettings = $true; settingsKey = $pr.settingsKey }
                            $needsTunnel = $true
                            $tunnelUseSettings = $true
                        } else {
                            $globalVars[$pr.var] = @{ value = $value; useSettings = $false }
                            $needsTunnel = $true
                        }
                    } else {
                        $value = Read-Host -Prompt "  $($pr.prompt)"
                        $globalVars[$pr.var] = @{ value = $value; useSettings = $false }
                        $needsTunnel = $true
                    }
                } else {
                    $value = Read-Host -Prompt "  $($pr.prompt)"
                    $globalVars[$pr.var] = @{ value = $value; useSettings = $false }
                }
                $promptedGlobalVars[$pr.var] = $true
            }
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

        $cmdDirName = $null
        if ($directories.Count -gt 1) {
            $dirOptions = @()
            foreach ($dir in $directories) { $dirOptions += $dir.name }
            $dirOptions += "(none — global)"
            $cmdDirIdx = Show-SelectionMenu -Title "Which project directory?" -Options $dirOptions
            if ($cmdDirIdx -lt $directories.Count) {
                $cmdDirName = $directories[$cmdDirIdx].name
            }
        } elseif ($directories.Count -eq 1) {
            $cmdDirName = $directories[0].name
        }

        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            $customCommands += @{
                name = $cmdName
                alias = if ([string]::IsNullOrWhiteSpace($cmdAlias)) { $null } else { $cmdAlias }
                description = $cmdDesc
                type = if ([string]::IsNullOrWhiteSpace($cmdType)) { $null } else { $cmdType.Trim().ToLower() }
                dirName = $cmdDirName
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
            $defaultTrigger = $f.id -notin @("compile", "pull")
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

    # Collect all params from selected features (per-directory expansion for project-scoped)
    $addedParams = @{}
    foreach ($f in $selectedFeatures) {
        if ($f.scope -eq "project") {
            $dirNames = $featureDirMap[$f.id]
            if (-not $dirNames) { continue }
            for ($di = 0; $di -lt $dirNames.Count; $di++) {
                $dName = $dirNames[$di]
                $isPrimary = ($dName -eq $directories[0].name)
                foreach ($p in $f.params) {
                    $switchName = Get-SwitchName -BaseName $p.name -DirName $dName -IsPrimary $isPrimary
                    if (-not $addedParams.ContainsKey($switchName)) {
                        $addedParams[$switchName] = $true
                        if ($isPrimary -and $p.alias) {
                            $paramLines += "    [Alias('$($p.alias)')]"
                        }
                        $paramLines += "    [switch]`$$switchName = `$false,"
                    }
                }
            }
        } else {
            # Global feature
            foreach ($p in $f.params) {
                if (-not $addedParams.ContainsKey($p.name)) {
                    $addedParams[$p.name] = $true
                    if ($p.alias) {
                        $paramLines += "    [Alias('$($p.alias)')]"
                    }
                    $paramLines += "    [switch]`$$($p.name) = `$false,"
                }
            }
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

    # Determine if settings are needed
    $anyRelative = $false
    foreach ($dir in $directories) {
        if (-not $dir.isAbsolute) { $anyRelative = $true }
    }
    $needsSettings = $anyRelative -or $tunnelUseSettings
    if ($needsSettings) {
        $script += "`$settings = Get-Content -Path `"`$PSScriptRoot\settings.json`" -Raw | ConvertFrom-Json" + "`r`n"
    }

    # $projects ordered hashtable
    $script += "`$projects = [ordered]@{" + "`r`n"
    foreach ($dir in $directories) {
        if ($dir.isAbsolute) {
            $script += "    `"$($dir.name)`" = `"$($dir.path)`"" + "`r`n"
        } else {
            $script += "    `"$($dir.name)`" = `"`$(`$settings.devDirectory)\$($dir.path)`"" + "`r`n"
        }
    }
    $script += "    # [/projects]" + "`r`n"
    $script += "}" + "`r`n"

    # Per-project config vars
    foreach ($dir in $directories) {
        if ($perProjectVars[$dir.name]) {
            foreach ($varName in $perProjectVars[$dir.name].Keys) {
                $script += "`$$($dir.name)_$varName = `"$($perProjectVars[$dir.name][$varName])`"" + "`r`n"
            }
        }
    }

    # Global config vars
    foreach ($varName in $globalVars.Keys) {
        $entry = $globalVars[$varName]
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
        if ($f.scope -eq "project") {
            $dirNames = $featureDirMap[$f.id]
            if (-not $dirNames) { continue }
            for ($di = 0; $di -lt $dirNames.Count; $di++) {
                $dName = $dirNames[$di]
                $isPrimary = ($dName -eq $directories[0].name)
                foreach ($p in $f.params) {
                    $switchName = Get-SwitchName -BaseName $p.name -DirName $dName -IsPrimary $isPrimary
                    if (-not $addedHelpParams.ContainsKey($switchName)) {
                        $addedHelpParams[$switchName] = $true
                        $aliasPart = if ($isPrimary -and $p.alias) { "-$($p.alias),  " } else { "      " }
                        $desc = (($f.label -split ' \u2014 ')[0]) + " ($dName)"
                        $script += "    Write-Host `"  $aliasPart-$switchName`" -ForegroundColor Cyan -NoNewline" + "`r`n"
                        $script += "    Write-Host `"  $desc`"" + "`r`n"
                    }
                }
            }
        } else {
            foreach ($p in $f.params) {
                if (-not $addedHelpParams.ContainsKey($p.name)) {
                    $addedHelpParams[$p.name] = $true
                    $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
                    $desc = ($f.label -split ' \u2014 ')[0]
                    $script += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline" + "`r`n"
                    $script += "    Write-Host `"  $desc`"" + "`r`n"
                }
            }
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
            if ($tf.scope -eq "project") {
                $dirNames = $featureDirMap[$tf.id]
                if (-not $dirNames) { continue }
                foreach ($dName in $dirNames) {
                    $isPrimary = ($dName -eq $directories[0].name)
                    $switchName = Get-SwitchName -BaseName $tf.params[0].name -DirName $dName -IsPrimary $isPrimary
                    $script += "    `$$switchName = `$true" + "`r`n"
                }
            } else {
                $primaryParam = $tf.params[0].name
                $script += "    `$$primaryParam = `$true" + "`r`n"
            }
        }
        $script += "}" + "`r`n"
        $script += "`r`n"
    }

    # Feature snippet blocks
    foreach ($f in $selectedFeatures) {
        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (-not (Test-Path $snippetPath)) { continue }

        if ($f.scope -eq "project") {
            $dirNames = $featureDirMap[$f.id]
            if (-not $dirNames) { continue }
            foreach ($dName in $dirNames) {
                $isPrimary = ($dName -eq $directories[0].name)
                $dirRef = "`$(`$projects.$dName)"

                $vars = @{
                    dir = $dirRef
                    switch = Get-SwitchName -BaseName $f.params[0].name -DirName $dName -IsPrimary $isPrimary
                    label = $dName
                }

                # Handle per-project vars (like sln)
                if ($f.prompts) {
                    foreach ($pr in $f.prompts) {
                        if ($pr.perProject) {
                            $vars[$pr.var] = "`$$($dName)_$($pr.var)"
                        }
                    }
                }

                # Handle compile special case: switchRelease / switchDebug
                if ($f.id -eq "compile") {
                    $vars["switchRelease"] = Get-SwitchName -BaseName "release" -DirName $dName -IsPrimary $isPrimary
                    $vars["switchDebug"] = Get-SwitchName -BaseName "debug" -DirName $dName -IsPrimary $isPrimary
                }

                $expanded = Expand-Snippet -SnippetPath $snippetPath -Vars $vars
                $script += $expanded + "`r`n"
            }
        } else {
            # Global snippet — no placeholders to expand, just include raw
            $snippetContent = Get-Content -Path $snippetPath -Raw
            $script += $snippetContent + "`r`n"
        }
    }

    # Custom command placeholder blocks
    foreach ($cmd in $customCommands) {
        $desc = if ($cmd.description) { $cmd.description } else { $cmd.name }
        $dirRef = if ($cmd.dirName) { "`$(`$projects.$($cmd.dirName))" } else { "`$(`$projects.$($directories[0].name))" }
        $script += "# $desc" + "`r`n"
        $script += "if(`$$($cmd.name)){" + "`r`n"
        $script += "    pushd" + "`r`n"
        $script += "    cd `"$dirRef`"" + "`r`n"
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
    Write-Host ""

    # Open in editor
    & "$editorPath" "$filepath"
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
        devDirectory = Split-Path $PSScriptRoot -Parent
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

function Exec-Init {
    $hasPathVariable = Check-EnvPath
    if (-not $hasPathVariable){
        [Environment]::SetEnvironmentVariable("Path", $PSScriptRoot + ";" + $Env:Path, "User")
    }

    # Prompt for settings
    $settingsPath = "$PSScriptRoot\settings.json"
    $s = @{}
    if (Test-Path -Path $settingsPath -PathType Leaf) {
        try {
            $existing = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            $existing.PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value }
        } catch {}
    }

    Write-Host ""
    $defaultDevDir = if ($s["devDirectory"]) { $s["devDirectory"] } else { Split-Path $PSScriptRoot -Parent }
    $devDir = Read-Host -Prompt "  Base development folder (default: $defaultDevDir)"
    if ([string]::IsNullOrWhiteSpace($devDir)) {
        $devDir = $defaultDevDir
    }
    $s["devDirectory"] = $devDir

    $currentEditor = $s["editorPath"]
    if ($currentEditor) {
        $editor = Read-Host -Prompt "  Editor path (current: $currentEditor)"
    } else {
        $editor = Read-Host -Prompt "  Editor path (default: notepad.exe)"
    }
    if (-not [string]::IsNullOrWhiteSpace($editor)) {
        $s["editorPath"] = $editor
    } elseif (-not $s["editorPath"]) {
        $s["editorPath"] = "notepad.exe"
    }

    $currentTunnel = $s["tunnelName"]
    if ($currentTunnel) {
        $tunnel = Read-Host -Prompt "  Cloudflared tunnel name (current: $currentTunnel)"
    } else {
        $tunnel = Read-Host -Prompt "  Cloudflared tunnel name (leave empty to skip)"
    }
    if (-not [string]::IsNullOrWhiteSpace($tunnel)) {
        $s["tunnelName"] = $tunnel
    }

    $s | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8
    Write-Host ""
    Write-Host "  Settings saved." -ForegroundColor Green
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
    $markers = @{ params = -1; help = -1; commands = -1; projects = -1 }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '# [/params]') { $markers.params = $i }
        elseif ($trimmed -eq '# [/help]') { $markers.help = $i }
        elseif ($trimmed -eq '# [/commands]') { $markers.commands = $i }
        elseif ($trimmed -eq '# [/projects]') { $markers.projects = $i }
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

function Exec-AddProject {
    param([string]$FilePath)

    . "$PSScriptRoot\lib\InteractiveMenu.ps1"

    $lines = [System.Collections.ArrayList]@(Get-Content -Path $FilePath)
    $markers = Find-MarkerLines -lines $lines
    if ($markers.projects -eq -1) {
        Write-Host ""
        Write-Host "  This script doesn't have the # [/projects] marker." -ForegroundColor DarkYellow
        Write-Host "  Only scripts created with the latest wizard support adding directories." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }
    if ($markers.params -eq -1 -or $markers.help -eq -1 -or $markers.commands -eq -1) {
        Write-Host ""
        Write-Host "  This script doesn't have injection markers." -ForegroundColor DarkYellow
        Write-Host ""
        return
    }

    $existingProjects = Get-ExistingProjects -lines $lines
    $existingParams = Get-ExistingParams -lines $lines

    Write-Host ""
    $dirName = Read-Host -Prompt "  Directory name (e.g. docs)"
    if ([string]::IsNullOrWhiteSpace($dirName)) { return }

    if ($existingProjects.Contains($dirName)) {
        Write-Host "  Directory '$dirName' already exists in this script." -ForegroundColor DarkYellow
        return
    }

    $dirPath = Read-Host -Prompt "  Project folder or full path (BasePath: $($s.devDirectory))"
    if ([string]::IsNullOrWhiteSpace($dirPath)) { return }
    $dirPath = $dirPath.TrimStart('\')
    $isAbsolute = [System.IO.Path]::IsPathRooted($dirPath)

    # Show feature checklist for project-scoped features
    $features = Get-Content -Path "$PSScriptRoot\config\features.json" -Raw | ConvertFrom-Json
    $projectFeatures = @($features | Where-Object { $_.scope -eq "project" })

    $checklistItems = @()
    foreach ($f in $projectFeatures) {
        $checklistItems += @{ label = $f.label; checked = $false }
    }

    $selectedIndices = Show-ChecklistMenu -Title "Select features for '$dirName'" -Items $checklistItems
    $selectedFeatures = @()
    foreach ($idx in $selectedIndices) {
        $selectedFeatures += $projectFeatures[$idx]
    }

    # Prompt for per-project vars
    $perProjectVars = @{}
    foreach ($f in $selectedFeatures) {
        if ($f.prompts) {
            foreach ($pr in $f.prompts) {
                if ($pr.perProject -and -not $perProjectVars.ContainsKey($pr.var)) {
                    $value = Read-Host -Prompt "  $($pr.prompt) for '$dirName'"
                    $perProjectVars[$pr.var] = $value
                }
            }
        }
    }

    # Check if settings line exists
    $hasSettings = $false
    foreach ($line in $lines) {
        if ($line -match '\$settings\s*=.*settings\.json') {
            $hasSettings = $true
            break
        }
    }

    # Build injection content
    # 1. Project entry
    $projectLine = if ($isAbsolute) {
        "    `"$dirName`" = `"$dirPath`""
    } else {
        "    `"$dirName`" = `"`$(`$settings.devDirectory)\$dirPath`""
    }

    # 2. Param lines
    $newParamLines = @()
    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            $switchName = Get-SwitchName -BaseName $p.name -DirName $dirName -IsPrimary $false
            if ($existingParams -contains $switchName) { continue }
            $newParamLines += "    [switch]`$$switchName = `$false,"
        }
    }
    if ($newParamLines.Count -gt 0) {
        $newParamLines[$newParamLines.Count - 1] = $newParamLines[$newParamLines.Count - 1].TrimEnd(',')
    }

    # 3. Help lines
    $newHelpLines = @()
    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            $switchName = Get-SwitchName -BaseName $p.name -DirName $dirName -IsPrimary $false
            $desc = (($f.label -split ' \u2014 ')[0]) + " ($dirName)"
            $newHelpLines += "    Write-Host `"      -$switchName`" -ForegroundColor Cyan -NoNewline"
            $newHelpLines += "    Write-Host `"  $desc`""
        }
    }

    # 4. Config var lines
    $configLines = @()
    foreach ($varName in $perProjectVars.Keys) {
        $configLines += "`$$($dirName)_$varName = `"$($perProjectVars[$varName])`""
    }

    # 5. Snippet blocks
    $newCommandLines = @()
    foreach ($f in $selectedFeatures) {
        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (-not (Test-Path $snippetPath)) { continue }
        $dirRef = "`$(`$projects.$dirName)"
        $vars = @{
            dir = $dirRef
            switch = Get-SwitchName -BaseName $f.params[0].name -DirName $dirName -IsPrimary $false
            label = $dirName
        }
        if ($f.prompts) {
            foreach ($pr in $f.prompts) {
                if ($pr.perProject) {
                    $vars[$pr.var] = "`$$($dirName)_$($pr.var)"
                }
            }
        }
        if ($f.id -eq "compile") {
            $vars["switchRelease"] = Get-SwitchName -BaseName "release" -DirName $dirName -IsPrimary $false
            $vars["switchDebug"] = Get-SwitchName -BaseName "debug" -DirName $dirName -IsPrimary $false
        }
        $expanded = Expand-Snippet -SnippetPath $snippetPath -Vars $vars
        $newCommandLines += $expanded.Split("`r`n", [System.StringSplitOptions]::None)
        $newCommandLines += ""
    }

    # --- Inject in reverse index order (bottom to top) ---
    # Re-read markers after each injection isn't needed if we go bottom-to-top

    # 5. Command snippets before # [/commands]
    if ($newCommandLines.Count -gt 0) {
        Insert-Lines -lines $lines -index $markers.commands -newLines $newCommandLines
    }

    # 4b. Add to group trigger if one exists
    $groupTrigger = Find-GroupTrigger -lines $lines
    if ($groupTrigger) {
        $triggerLines = @()
        foreach ($f in $selectedFeatures) {
            if ($f.id -notin @("compile", "pull")) {
                $switchName = Get-SwitchName -BaseName $f.params[0].name -DirName $dirName -IsPrimary $false
                $triggerLines += "    `$$switchName = `$true"
            }
        }
        if ($triggerLines.Count -gt 0) {
            Insert-Lines -lines $lines -index $groupTrigger.end -newLines $triggerLines
        }
    }

    # 4. Help lines before # [/help]
    if ($newHelpLines.Count -gt 0) {
        Insert-Lines -lines $lines -index $markers.help -newLines $newHelpLines
    }

    # 3. Config vars before "# ===== C O N F I G U R A T I O N ====== #"
    if ($configLines.Count -gt 0) {
        $configMarkerIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '# ===== C O N F I G U R A T I O N ====== #') {
                $configMarkerIdx = $i
                break
            }
        }
        if ($configMarkerIdx -ge 0) {
            Insert-Lines -lines $lines -index $configMarkerIdx -newLines $configLines
        }
    }

    # 2. Project entry before # [/projects]
    # Re-find projects marker since lines may have shifted
    $markers = Find-MarkerLines -lines $lines
    Insert-Lines -lines $lines -index $markers.projects -newLines @($projectLine)

    # 1. Params before # [/params]
    if ($newParamLines.Count -gt 0) {
        $markers = Find-MarkerLines -lines $lines
        $lastParamIdx = $markers.params - 1
        if ($lastParamIdx -ge 0 -and $lines[$lastParamIdx] -match '\[(switch|string|int)\]') {
            $lines[$lastParamIdx] = $lines[$lastParamIdx].TrimEnd() + ","
        }
        Insert-Lines -lines $lines -index $markers.params -newLines $newParamLines
    }

    # Add settings line if needed and not present
    if (-not $isAbsolute -and -not $hasSettings) {
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

    # Write back
    $lines | Set-Content -Path $FilePath -Encoding UTF8

    Write-Host ""
    Write-Host "  Directory '$dirName' added successfully." -ForegroundColor Green
    Write-Host ""
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
    $existingProjects = Get-ExistingProjects -lines $lines
    $projectNames = @($existingProjects.Keys)

    $availableFeatures = @()
    foreach ($f in $features) {
        if ($f.scope -eq "project") {
            # A project-scoped feature is available if there's at least one directory
            # that doesn't have it yet
            $hasAvailableDir = $false
            foreach ($dName in $projectNames) {
                $isPrimary = ($dName -eq $projectNames[0])
                $switchName = Get-SwitchName -BaseName $f.params[0].name -DirName $dName -IsPrimary $isPrimary
                if ($existingParams -notcontains $switchName) {
                    $hasAvailableDir = $true
                    break
                }
            }
            if ($hasAvailableDir) {
                $availableFeatures += $f
            }
        } else {
            # Global feature — check if primary param already exists
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

    # For project-scoped features: pick directories
    $featureDirMap = @{}
    $projectSelectedFeatures = @($selectedFeatures | Where-Object { $_.scope -eq "project" })

    if ($projectSelectedFeatures.Count -gt 0 -and $projectNames.Count -gt 0) {
        foreach ($f in $projectSelectedFeatures) {
            # Filter to directories that don't already have this feature
            $availableDirs = @()
            foreach ($dName in $projectNames) {
                $isPrimary = ($dName -eq $projectNames[0])
                $switchName = Get-SwitchName -BaseName $f.params[0].name -DirName $dName -IsPrimary $isPrimary
                if ($existingParams -notcontains $switchName) {
                    $availableDirs += $dName
                }
            }

            if ($availableDirs.Count -eq 1) {
                $featureDirMap[$f.id] = $availableDirs
            } elseif ($availableDirs.Count -gt 1) {
                $dirItems = @()
                foreach ($dName in $availableDirs) {
                    $dirItems += @{ label = $dName; checked = $true }
                }
                $dirIndices = Show-ChecklistMenu -Title "Apply '$($f.label)' to which directories?" -Items $dirItems
                $featureDirMap[$f.id] = @()
                foreach ($idx in $dirIndices) {
                    $featureDirMap[$f.id] += $availableDirs[$idx]
                }
            }
        }
    }

    # Prompt for needed config variables
    $existingVars = Get-ExistingConfigVars -lines $lines
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
            if ($pr.perProject) {
                # Per-project prompt
                $dirNames = $featureDirMap[$f.id]
                if (-not $dirNames) { continue }
                foreach ($dName in $dirNames) {
                    $varKey = "$($dName)_$($pr.var)"
                    if ($existingVars -contains $varKey -or $promptedVars.ContainsKey($varKey)) { continue }
                    $value = Read-Host -Prompt "  $($pr.prompt) for '$dName'"
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $configLinesToAdd += "`$$varKey = `"$value`""
                    }
                    $promptedVars[$varKey] = $true
                }
            } else {
                # Global prompt
                if ($existingVars -contains $pr.var -or $promptedVars.ContainsKey($pr.var)) { continue }
                $promptText = $pr.prompt
                $value = Read-Host -Prompt "  $promptText"
                if ([string]::IsNullOrWhiteSpace($value)) {
                    if ($pr.settingsKey) {
                        $configLinesToAdd += "`$$($pr.var) = `$settings.$($pr.settingsKey)"
                        $needsSettingsLine = $true
                    }
                } else {
                    $configLinesToAdd += "`$$($pr.var) = `"$value`""
                }
                $promptedVars[$pr.var] = $true
            }
        }
    }

    # Build injection content
    $newParamLines = @()
    $newHelpLines = @()
    $newCommandLines = @()

    foreach ($f in $selectedFeatures) {
        if ($f.scope -eq "project") {
            $dirNames = $featureDirMap[$f.id]
            if (-not $dirNames) { continue }
            foreach ($dName in $dirNames) {
                $isPrimary = ($dName -eq $projectNames[0])
                $dirRef = "`$(`$projects.$dName)"

                # Params
                foreach ($p in $f.params) {
                    $switchName = Get-SwitchName -BaseName $p.name -DirName $dName -IsPrimary $isPrimary
                    if ($existingParams -contains $switchName) { continue }
                    if ($isPrimary -and $p.alias) {
                        $newParamLines += "    [Alias('$($p.alias)')]"
                    }
                    $newParamLines += "    [switch]`$$switchName = `$false,"
                }

                # Help
                foreach ($p in $f.params) {
                    $switchName = Get-SwitchName -BaseName $p.name -DirName $dName -IsPrimary $isPrimary
                    $aliasPart = if ($isPrimary -and $p.alias) { "-$($p.alias),  " } else { "      " }
                    $desc = (($f.label -split ' \u2014 ')[0]) + " ($dName)"
                    $newHelpLines += "    Write-Host `"  $aliasPart-$switchName`" -ForegroundColor Cyan -NoNewline"
                    $newHelpLines += "    Write-Host `"  $desc`""
                }

                # Snippet
                $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
                if (Test-Path $snippetPath) {
                    $vars = @{
                        dir = $dirRef
                        switch = Get-SwitchName -BaseName $f.params[0].name -DirName $dName -IsPrimary $isPrimary
                        label = $dName
                    }
                    if ($f.prompts) {
                        foreach ($pr in $f.prompts) {
                            if ($pr.perProject) {
                                $vars[$pr.var] = "`$$($dName)_$($pr.var)"
                            }
                        }
                    }
                    if ($f.id -eq "compile") {
                        $vars["switchRelease"] = Get-SwitchName -BaseName "release" -DirName $dName -IsPrimary $isPrimary
                        $vars["switchDebug"] = Get-SwitchName -BaseName "debug" -DirName $dName -IsPrimary $isPrimary
                    }
                    $expanded = Expand-Snippet -SnippetPath $snippetPath -Vars $vars
                    $newCommandLines += $expanded.Split("`r`n", [System.StringSplitOptions]::None)
                    $newCommandLines += ""
                }
            }
        } else {
            # Global feature
            foreach ($p in $f.params) {
                if ($p.alias) {
                    $newParamLines += "    [Alias('$($p.alias)')]"
                }
                $newParamLines += "    [switch]`$$($p.name) = `$false,"
            }
            foreach ($p in $f.params) {
                $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
                $desc = ($f.label -split " \u2014 ")[0]
                $newHelpLines += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline"
                $newHelpLines += "    Write-Host `"  $desc`""
            }
            $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
            if (Test-Path $snippetPath) {
                $snippetContent = Get-Content -Path $snippetPath
                $newCommandLines += $snippetContent
                $newCommandLines += ""
            }
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
            if ($f.id -notin @("compile", "pull")) {
                if ($f.scope -eq "project") {
                    $dirNames = $featureDirMap[$f.id]
                    if (-not $dirNames) { continue }
                    foreach ($dName in $dirNames) {
                        $isPrimary = ($dName -eq $projectNames[0])
                        $switchName = Get-SwitchName -BaseName $f.params[0].name -DirName $dName -IsPrimary $isPrimary
                        $triggerLines += "    `$$switchName = `$true"
                    }
                } else {
                    $primaryParam = $f.params[0].name
                    $triggerLines += "    `$$primaryParam = `$true"
                }
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

    # Parse existing projects for directory picker
    $existingProjects = Get-ExistingProjects -lines $lines
    $projectNames = @($existingProjects.Keys)

    Write-Host ""
    $cmdName = Read-Host -Prompt "  Switch name (e.g. deploy)"
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return }
    $cmdAlias = Read-Host -Prompt "  Alias (leave empty to skip)"
    $cmdDesc = Read-Host -Prompt "  Description"
    if ([string]::IsNullOrWhiteSpace($cmdDesc)) { $cmdDesc = $cmdName }
    $cmdType = Read-Host -Prompt "  Accept a value? (leave empty for switch, or enter type: string, int)"
    $cmdType = if ([string]::IsNullOrWhiteSpace($cmdType)) { $null } else { $cmdType.Trim().ToLower() }

    # Directory picker
    $dirRef = $null
    if ($projectNames.Count -gt 1) {
        $dirOptions = @() + $projectNames + @("(none — global)")
        $dirIdx = Show-SelectionMenu -Title "Which project directory?" -Options $dirOptions
        if ($dirIdx -lt $projectNames.Count) {
            $dirRef = "`$(`$projects.$($projectNames[$dirIdx]))"
        }
    } elseif ($projectNames.Count -eq 1) {
        $dirRef = "`$(`$projects.$($projectNames[0]))"
    } else {
        $dirRef = "`$baseDir"
    }

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
    if ($dirRef) {
        $newCommandLines += @(
            "    pushd"
            "    cd `"$dirRef`""
        )
    }
    if ($cmdType) {
        $newCommandLines += "    # Value passed: `$$cmdName"
    }
    $newCommandLines += @(
        "    # TODO: Add your command here"
    )
    if ($dirRef) {
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

    $actions = @("Add project directory", "Add predefined feature", "Add custom command", "Open in editor")
    $actionIndex = Show-SelectionMenu -Title "What do you want to do?" -Options $actions

    switch ($actionIndex) {
        0 { Exec-AddProject -FilePath $file.FullName }
        1 { Exec-AddFeature -FilePath $file.FullName }
        2 { Exec-AddCustomCommand -FilePath $file.FullName }
        3 { & "$editorPath" "$($file.FullName)" }
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

# Display a message when the Env:Path is lacking the script's path
$hasPathVariable = Check-EnvPath
if (-not $hasPathVariable -and -not $init){
    Write-Host "Warning! The MyShortcuts path is missing from the Env:Variables." -ForegroundColor DarkYellow
    Write-Host "Run 'MyShortcuts.ps1 -init' do add the path to the variables list."  -ForegroundColor Green
    Write-Host ""
}

# Get Settings
$s = Get-Settings
$editorPath = if ($s.editorPath) { $s.editorPath } else { 'notepad.exe' }


if ($directory){
   Exec-Directory
}
elseif ($init){
    Exec-Init
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
else{
    Write-Host "Execute 'Get-Help MyShortcut.ps1 -full' to learn more"
}
