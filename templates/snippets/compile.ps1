# Compile — {{label}}
if(${{switchRelease}} -or ${{switchDebug}}){
    $slnPath = if ("{{sln}}") { Join-Path "{{dir}}" "{{sln}}" } else { $null }
    if (-not $slnPath -or -not (Test-Path $slnPath)) {
        # Auto-detect — prefer the modern .slnx, then .sln; else let dotnet find it in the folder
        $found = @(Get-ChildItem "{{dir}}" -Filter *.slnx -File -ErrorAction SilentlyContinue) +
                 @(Get-ChildItem "{{dir}}" -Filter *.sln  -File -ErrorAction SilentlyContinue)
        $slnPath = ($found | Select-Object -First 1).FullName
        if (-not $slnPath) { $slnPath = "{{dir}}" }
    }
    if(${{switchRelease}}){ dotnet build "$slnPath" -c Release }
    if(${{switchDebug}}){ dotnet build "$slnPath" -c Debug }
}
