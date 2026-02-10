# Start Cloudflared tunnel
if($tunnel){
    wt --window 0 -p "Powershell" -d . powershell -noExit "cloudflared tunnel run $tunnelName";
}
