# Compile — {{label}}
if(${{switchRelease}}){
   dotnet build "{{dir}}\{{sln}}" -c Release
}
if(${{switchDebug}}){
   dotnet build "{{dir}}\{{sln}}" -c Debug
}
