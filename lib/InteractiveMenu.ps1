function Show-SelectionMenu {
    param(
        [string]$Title,
        [string[]]$Options
    )

    $selectedIndex = 0
    $cursorVisible = [System.Console]::CursorVisible
    [System.Console]::CursorVisible = $false

    try {
        Write-Host ""
        Write-Host " $Title" -ForegroundColor DarkGreen
        Write-Host ""

        # Record the starting line
        $startLine = [System.Console]::CursorTop

        # Initial draw
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $selectedIndex) {
                Write-Host "  > " -ForegroundColor Cyan -NoNewline
                Write-Host $Options[$i] -ForegroundColor Cyan
            } else {
                Write-Host "    $($Options[$i])"
            }
        }

        Write-Host ""
        Write-Host "  [Up/Down] Navigate  [Enter] Select" -ForegroundColor DarkGray

        # Recalculate startLine in case the console scrolled during initial draw
        $startLine = [System.Console]::CursorTop - $Options.Count - 2

        while ($true) {
            $key = [System.Console]::ReadKey($true)

            $previousIndex = $selectedIndex

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) { $selectedIndex-- }
                }
                'DownArrow' {
                    if ($selectedIndex -lt ($Options.Count - 1)) { $selectedIndex++ }
                }
                'Enter' {
                    [System.Console]::CursorVisible = $cursorVisible
                    return $selectedIndex
                }
            }

            if ($previousIndex -ne $selectedIndex) {
                # Redraw only the two changed lines
                [System.Console]::SetCursorPosition(0, $startLine + $previousIndex)
                Write-Host "    $($Options[$previousIndex])                    " -NoNewline
                [System.Console]::SetCursorPosition(0, $startLine + $selectedIndex)
                Write-Host "  > " -ForegroundColor Cyan -NoNewline
                Write-Host "$($Options[$selectedIndex])                    " -ForegroundColor Cyan -NoNewline
                [System.Console]::SetCursorPosition(0, $startLine + $Options.Count + 2)
            }
        }
    }
    finally {
        [System.Console]::CursorVisible = $cursorVisible
    }
}

function Show-ChecklistMenu {
    param(
        [string]$Title,
        [array]$Items  # Array of @{ label = "..."; checked = $true/$false }
    )

    $selectedIndex = 0
    $checked = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $checked += [bool]$Items[$i].checked
    }

    $cursorVisible = [System.Console]::CursorVisible
    [System.Console]::CursorVisible = $false

    try {
        Write-Host ""
        Write-Host " $Title" -ForegroundColor DarkGreen
        Write-Host ""

        $startLine = [System.Console]::CursorTop

        # Initial draw
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($checked[$i]) { "x" } else { " " }
            if ($i -eq $selectedIndex) {
                Write-Host "  > [$mark] " -ForegroundColor Cyan -NoNewline
                Write-Host $Items[$i].label -ForegroundColor Cyan
            } else {
                Write-Host "    [$mark] $($Items[$i].label)"
            }
        }

        Write-Host ""
        Write-Host "  [Up/Down] Navigate  [Space] Toggle  [Enter] Confirm" -ForegroundColor DarkGray

        # Recalculate startLine in case the console scrolled during initial draw
        $startLine = [System.Console]::CursorTop - $Items.Count - 2

        while ($true) {
            $key = [System.Console]::ReadKey($true)

            $previousIndex = $selectedIndex

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) { $selectedIndex-- }
                }
                'DownArrow' {
                    if ($selectedIndex -lt ($Items.Count - 1)) { $selectedIndex++ }
                }
                'Spacebar' {
                    $checked[$selectedIndex] = -not $checked[$selectedIndex]
                    # Redraw current line with toggled state
                    $mark = if ($checked[$selectedIndex]) { "x" } else { " " }
                    [System.Console]::SetCursorPosition(0, $startLine + $selectedIndex)
                    Write-Host "  > [$mark] " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($Items[$selectedIndex].label)                    " -ForegroundColor Cyan -NoNewline
                    [System.Console]::SetCursorPosition(0, $startLine + $Items.Count + 2)
                    continue
                }
                'Enter' {
                    $result = @()
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        if ($checked[$i]) { $result += $i }
                    }
                    [System.Console]::CursorVisible = $cursorVisible
                    return $result
                }
            }

            if ($previousIndex -ne $selectedIndex) {
                # Redraw previous line (deselect)
                $markPrev = if ($checked[$previousIndex]) { "x" } else { " " }
                [System.Console]::SetCursorPosition(0, $startLine + $previousIndex)
                Write-Host "    [$markPrev] $($Items[$previousIndex].label)                    " -NoNewline

                # Redraw current line (select)
                $markCurr = if ($checked[$selectedIndex]) { "x" } else { " " }
                [System.Console]::SetCursorPosition(0, $startLine + $selectedIndex)
                Write-Host "  > [$markCurr] " -ForegroundColor Cyan -NoNewline
                Write-Host "$($Items[$selectedIndex].label)                    " -ForegroundColor Cyan -NoNewline
                [System.Console]::SetCursorPosition(0, $startLine + $Items.Count + 2)
            }
        }
    }
    finally {
        [System.Console]::CursorVisible = $cursorVisible
    }
}
