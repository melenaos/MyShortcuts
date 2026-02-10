# Open Claude Code in frontend
if($claudeui){
    pushd
    cd "$baseDirUi"
    wt --window 0 -p "Powershell" -d . powershell -noExit "claude";
    popd
}



    