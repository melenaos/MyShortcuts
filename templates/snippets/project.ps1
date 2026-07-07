# Open the VS solution — {{label}}
if(${{switch}}){
    $slnPath = if ("{{sln}}") { Join-Path "{{dir}}" "{{sln}}" } else { $null }
    if (-not $slnPath -or -not (Test-Path $slnPath)) {
        # Auto-detect — prefer the modern .slnx, then .sln
        $found = @(Get-ChildItem "{{dir}}" -Filter *.slnx -File -ErrorAction SilentlyContinue) +
                 @(Get-ChildItem "{{dir}}" -Filter *.sln  -File -ErrorAction SilentlyContinue)
        $slnPath = ($found | Select-Object -First 1).FullName
    }
    if ($slnPath) { Invoke-Item "$slnPath" }
    else { Write-Host "No .sln/.slnx found in {{dir}}" -ForegroundColor DarkYellow }
}
