# Start Cloudflared tunnel
if(${{switch}}){
    wt --window 0 -p "Powershell" -d . powershell -noExit "cloudflared tunnel run {{tunnelName}}";
}
