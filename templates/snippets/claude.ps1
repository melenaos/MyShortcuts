# Open Claude Code — {{label}}
if(${{switch}}){
    pushd
    cd "{{dir}}"
    wt --window 0 -p "Powershell" -d . powershell -noExit "claude";
    popd
}
