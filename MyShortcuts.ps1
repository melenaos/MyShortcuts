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

    # --- Step 2: Feature checklist ---
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

    # --- Step 3: Determine which config vars are needed ---
    $needsBaseDirUi = $false
    $needsTunnel = $false
    $needsSolution = $false
    foreach ($f in $selectedFeatures) {
        if ($f.configVars -and $f.configVars -contains "baseDirUi") {
            $needsBaseDirUi = $true
        }
        if ($f.id -eq "tunnel") {
            $needsTunnel = $true
        }
        if ($f.id -eq "project" -or $f.id -eq "compile") {
            $needsSolution = $true
        }
    }

    # Prompt for config values
    $baseDir = Read-Host -Prompt "  Project folder or full path (default: .\$projectName\)"
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $baseDir = $projectName
    }
    $baseDirIsAbsolute = [System.IO.Path]::IsPathRooted($baseDir)

    $solutionName = ""
    if ($needsSolution) {
        $solutionName = Read-Host -Prompt "  Solution name (e.g. $projectName.sln)"
        if ([string]::IsNullOrWhiteSpace($solutionName)) {
            $solutionName = "$projectName.sln"
        }
    }

    $baseDirUi = ""
    $baseDirUiIsAbsolute = $false
    if ($needsBaseDirUi) {
        $baseDirUi = Read-Host -Prompt "  UI project folder or full path (default: .\$projectName-Ui\)"
        if ([string]::IsNullOrWhiteSpace($baseDirUi)) {
            $baseDirUi = "$projectName-Ui"
        }
        $baseDirUiIsAbsolute = [System.IO.Path]::IsPathRooted($baseDirUi)
    }

    $tunnelName = ""
    $tunnelUseSettings = $false
    if ($needsTunnel) {
        $defaultTunnel = $s.tunnelName
        if ($defaultTunnel) {
            $tunnelName = Read-Host -Prompt "  Tunnel name (default from settings: $defaultTunnel, or enter custom)"
            if ([string]::IsNullOrWhiteSpace($tunnelName)) {
                $tunnelName = $defaultTunnel
                $tunnelUseSettings = $true
            }
        } else {
            $tunnelName = Read-Host -Prompt "  Tunnel name (e.g. my-tunnel)"
        }
    }

    # --- Step 4: Custom commands ---
    $customCommands = @()
    Write-Host ""
    $addCustom = Read-Host -Prompt "  Add a custom command? (y/n)"
    while ($addCustom -eq 'y') {
        $cmdName = Read-Host -Prompt "    Switch name (e.g. deploy)"
        $cmdAlias = Read-Host -Prompt "    Alias (leave empty to skip)"
        $cmdDesc = Read-Host -Prompt "    Description (e.g. Deploy to production)"
        if (-not [string]::IsNullOrWhiteSpace($cmdName)) {
            $customCommands += @{
                name = $cmdName
                alias = if ([string]::IsNullOrWhiteSpace($cmdAlias)) { $null } else { $cmdAlias }
                description = $cmdDesc
            }
        }
        $addCustom = Read-Host -Prompt "  Add another custom command? (y/n)"
    }

    # --- Step 5: Group trigger (optional) ---
    Write-Host ""
    $triggerName = Read-Host -Prompt "  Group trigger switch name (leave empty to skip)"
    $triggerFeatures = @()

    if (-not [string]::IsNullOrWhiteSpace($triggerName)) {
        # Show checklist for which features the group trigger activates
        $triggerItems = @()
        foreach ($f in $selectedFeatures) {
            # Exclude compile and pull from group trigger candidates (they're typically run individually)
            $defaultTrigger = $f.id -notin @("compile", "pull")
            $triggerItems += @{ label = $f.label; checked = $defaultTrigger }
        }

        $triggerIndices = Show-ChecklistMenu -Title "Which features should '-$triggerName' activate?" -Items $triggerItems
        foreach ($idx in $triggerIndices) {
            $triggerFeatures += $selectedFeatures[$idx]
        }
    }

    Write-Host ""

    # --- Step 5: Check if file exists ---
    $filepath = "$PSScriptRoot\$filename.ps1"
    if (Test-Path -Path "$filepath" -PathType Leaf) {
        Write-Host "  Shortcut already exists" -ForegroundColor DarkYellow
        $overwrite = Read-Host -Prompt "  Overwrite? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Host "  Cancelled." -ForegroundColor DarkYellow
            return
        }
    }

    # --- Step 6: Assemble the script ---
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

    # Collect all params from selected features (deduplicate)
    $addedParams = @{}
    foreach ($f in $selectedFeatures) {
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

    # Add custom command params
    foreach ($cmd in $customCommands) {
        if ($cmd.alias) {
            $paramLines += "    [Alias('$($cmd.alias)')]"
        }
        $paramLines += "    [switch]`$$($cmd.name) = `$false,"
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
    $needsSettings = (-not $baseDirIsAbsolute) -or ($needsBaseDirUi -and -not $baseDirUiIsAbsolute) -or $tunnelUseSettings
    if ($needsSettings) {
        $script += "`$settings = Get-Content -Path `"`$PSScriptRoot\settings.json`" -Raw | ConvertFrom-Json" + "`r`n"
    }
    if ($baseDirIsAbsolute) {
        $script += "`$baseDir = `"$baseDir`"" + "`r`n"
    } else {
        $script += "`$baseDir = `"`$(`$settings.devDirectory)\$baseDir`"" + "`r`n"
    }
    if ($needsBaseDirUi) {
        if ($baseDirUiIsAbsolute) {
            $script += "`$baseDirUi = `"$baseDirUi`"" + "`r`n"
        } else {
            $script += "`$baseDirUi = `"`$(`$settings.devDirectory)\$baseDirUi`"" + "`r`n"
        }
    }
    if ($needsSolution) {
        $script += "`$projectName = `"$solutionName`"" + "`r`n"
    }
    if ($needsTunnel) {
        if ($tunnelUseSettings) {
            $script += "`$tunnelName = `$settings.tunnelName" + "`r`n"
        } else {
            $script += "`$tunnelName = `"$tunnelName`"" + "`r`n"
        }
    }
    $script += "# ===== C O N F I G U R A T I O N ====== #" + "`r`n"
    $script += "`r`n"

    # Help block — show usage when no switches are passed
    $script += "# Show help if no parameters provided" + "`r`n"
    $script += "if (`$PSBoundParameters.Count -eq 0) {" + "`r`n"
    $script += "    Write-Host `"`n--- $projectName ---`" -ForegroundColor Cyan" + "`r`n"
    $script += "    Write-Host `"Usage: .\$filename.ps1 [-switch]`"" + "`r`n"
    $script += "    Write-Host `"Available Switches:`"" + "`r`n"

    # Group trigger line (if set)
    if (-not [string]::IsNullOrWhiteSpace($triggerName)) {
        $triggerAliasPart = if ($triggerAlias) { "-$triggerAlias,  " } else { "      " }
        $script += "    Write-Host `"  $triggerAliasPart-$triggerName`" -ForegroundColor Cyan -NoNewline" + "`r`n"
        $script += "    Write-Host `"  Run all launch actions`"" + "`r`n"
    }

    # Feature param lines
    $addedHelpParams = @{}
    foreach ($f in $selectedFeatures) {
        foreach ($p in $f.params) {
            if (-not $addedHelpParams.ContainsKey($p.name)) {
                $addedHelpParams[$p.name] = $true
                $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
                # Extract short description from the feature label (part before the dash)
                $desc = ($f.label -split ' \u2014 ')[0]
                $script += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline" + "`r`n"
                $script += "    Write-Host `"  $desc`"" + "`r`n"
            }
        }
    }

    # Custom command help lines
    foreach ($cmd in $customCommands) {
        $aliasPart = if ($cmd.alias) { "-$($cmd.alias),  " } else { "      " }
        $desc = if ($cmd.description) { $cmd.description } else { $cmd.name }
        $script += "    Write-Host `"  $aliasPart-$($cmd.name)`" -ForegroundColor Cyan -NoNewline" + "`r`n"
        $script += "    Write-Host `"  $desc`"" + "`r`n"
    }

    $script += "    # [/help]" + "`r`n"
    $script += "    Write-Host `"`"" + "`r`n"
    $script += "    exit" + "`r`n"
    $script += "}" + "`r`n"
    $script += "`r`n"

    # Group trigger block — sets individual flags
    if ($triggerFeatures.Count -gt 0) {
        $script += "# Group trigger" + "`r`n"
        $script += "if(`$$triggerName){" + "`r`n"
        foreach ($tf in $triggerFeatures) {
            # Get the primary param name (first param of the feature)
            $primaryParam = $tf.params[0].name
            $script += "    `$$primaryParam = `$true" + "`r`n"
        }
        $script += "}" + "`r`n"
        $script += "`r`n"
    }

    # Feature snippet blocks
    foreach ($f in $selectedFeatures) {
        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (Test-Path $snippetPath) {
            $snippetContent = Get-Content -Path $snippetPath -Raw
            $script += $snippetContent + "`r`n"
        }
    }

    # Custom command placeholder blocks
    foreach ($cmd in $customCommands) {
        $desc = if ($cmd.description) { $cmd.description } else { $cmd.name }
        $script += "# $desc" + "`r`n"
        $script += "if(`$$($cmd.name)){" + "`r`n"
        $script += "    pushd" + "`r`n"
        $script += "    cd `"`$baseDir`"" + "`r`n"
        $script += "    # TODO: Add your command here" + "`r`n"
        $script += "    popd" + "`r`n"
        $script += "}" + "`r`n"
        $script += "`r`n"
    }

    $script += "# [/commands]" + "`r`n"

    # --- Step 7: Write the file ---
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
        if ($line -match '\[switch\]\$(\w+)') {
            $params += $Matches[1]
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

    $availableFeatures = @()
    foreach ($f in $features) {
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
        if ($f.prompts) {
            foreach ($pr in $f.prompts) {
                if ($existingVars -contains $pr.var -or $promptedVars.ContainsKey($pr.var)) {
                    continue
                }
                $value = Read-Host -Prompt "  $($pr.prompt)"
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

    # Build injection content for each marker position
    $newParamLines = @()
    $newHelpLines = @()
    $newCommandLines = @()

    foreach ($f in $selectedFeatures) {
        # Params
        foreach ($p in $f.params) {
            if ($p.alias) {
                $newParamLines += "    [Alias('$($p.alias)')]"
            }
            $newParamLines += "    [switch]`$$($p.name) = `$false,"
        }

        # Help
        foreach ($p in $f.params) {
            $aliasPart = if ($p.alias) { "-$($p.alias),  " } else { "      " }
            $desc = ($f.label -split " \u2014 ")[0]
            $newHelpLines += "    Write-Host `"  $aliasPart-$($p.name)`" -ForegroundColor Cyan -NoNewline"
            $newHelpLines += "    Write-Host `"  $desc`""
        }

        # Snippet
        $snippetPath = "$PSScriptRoot\templates\snippets\$($f.snippet)"
        if (Test-Path $snippetPath) {
            $snippetContent = Get-Content -Path $snippetPath
            $newCommandLines += $snippetContent
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
            if ($f.id -notin @("compile", "pull")) {
                $primaryParam = $f.params[0].name
                $triggerLines += "    `$$primaryParam = `$true"
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
        $lastParamIdx = $markers.params - 1
        if ($lastParamIdx -ge 0 -and $lines[$lastParamIdx] -match '\[switch\]') {
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

    Write-Host ""
    $cmdName = Read-Host -Prompt "  Switch name (e.g. deploy)"
    if ([string]::IsNullOrWhiteSpace($cmdName)) { return }
    $cmdAlias = Read-Host -Prompt "  Alias (leave empty to skip)"
    $cmdDesc = Read-Host -Prompt "  Description"
    if ([string]::IsNullOrWhiteSpace($cmdDesc)) { $cmdDesc = $cmdName }

    # Build param lines
    $newParamLines = @()
    if (-not [string]::IsNullOrWhiteSpace($cmdAlias)) {
        $newParamLines += "    [Alias('$cmdAlias')]"
    }
    $newParamLines += "    [switch]`$$cmdName = `$false"

    # Build help lines
    $aliasPart = if (-not [string]::IsNullOrWhiteSpace($cmdAlias)) { "-$cmdAlias,  " } else { "      " }
    $newHelpLines = @(
        "    Write-Host `"  $aliasPart-$cmdName`" -ForegroundColor Cyan -NoNewline"
        "    Write-Host `"  $cmdDesc`""
    )

    # Build command block
    $newCommandLines = @(
        "# $cmdDesc"
        "if(`$$cmdName){"
        "    pushd"
        "    cd `"`$baseDir`""
        "    # TODO: Add your command here"
        "    popd"
        "}"
        ""
    )

    # Inject in reverse index order
    Insert-Lines -lines $lines -index $markers.commands -newLines $newCommandLines
    Insert-Lines -lines $lines -index $markers.help -newLines $newHelpLines

    # Add comma to existing last param line
    $lastParamIdx = $markers.params - 1
    if ($lastParamIdx -ge 0 -and $lines[$lastParamIdx] -match '\[switch\]') {
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