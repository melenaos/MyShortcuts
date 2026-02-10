# Open Claude Code in backend
if($claude){
    pushd
    cd "$baseDir"
    wt --window 0 -p "Powershell" -d . powershell -noExit "claude";
    popd
}
