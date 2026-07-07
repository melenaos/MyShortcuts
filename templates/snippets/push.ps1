# Git add, commit & push — {{label}}
if(${{switch}}){
    pushd
    cd "{{dir}}"
    $msg = Read-Host -Prompt "  Commit message"
    if ([string]::IsNullOrWhiteSpace($msg)) {
        Write-Host "  Aborted: empty commit message." -ForegroundColor DarkYellow
    } else {
        git add -A
        git commit -m "$msg"
        git push
    }
    popd
}
