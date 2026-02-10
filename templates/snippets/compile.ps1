# Compile project
if($release){
   dotnet build "$baseDir\$projectName" -c Release
}
if($debug){
   dotnet build "$baseDir\$projectName" -c Debug
}
