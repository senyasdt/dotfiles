# WMI reads the real user hive, outside MSIX's per-package registry overlay.
function Read-StartupValue([string]$Key,[string]$Name){
    $base=@{hDefKey=[uint32]2147483651;sSubKeyName=$Key}
    $enum=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName EnumValues -Arguments $base
    if($enum.ReturnValue -ne 0){return $null}
    $index=[Array]::IndexOf([string[]]$enum.sNames,$Name)
    if($index -lt 0){return $null}
    $type=[int]$enum.Types[$index]
    $method=switch($type){1{'GetStringValue'}3{'GetBinaryValue'}4{'GetDWORDValue'}default{throw "Unsupported startup value type: $type ($Name)"}}
    $base.sValueName=$Name
    $result=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $method -Arguments $base
    if($result.ReturnValue -ne 0){throw "Cannot read startup value: $Key/$Name ($($result.ReturnValue))"}
    $data=if($type -eq 1){$result.sValue}else{$result.uValue}
    [pscustomobject]@{Key=$Key;Name=$Name;Type=$type;Value=$data}
}
function Write-StartupValue($Entry){
    $parameters=@{hDefKey=[uint32]2147483651;sSubKeyName=[string]$Entry.Key;sValueName=[string]$Entry.Name}
    switch([int]$Entry.Type){
        1{$method='SetStringValue';$parameters.sValue=[string]$Entry.Value}
        3{$method='SetBinaryValue';$parameters.uValue=[byte[]]$Entry.Value}
        4{$method='SetDWORDValue';$parameters.uValue=[uint32]$Entry.Value}
        default{throw 'Unsupported registry restore type'}
    }
    $result=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName $method -Arguments $parameters
    if($result.ReturnValue -ne 0){throw "Cannot write startup value ($($result.ReturnValue)): $($Entry.Name)"}
}
function Remove-StartupValue($Entry){
    $now=Read-StartupValue $Entry.Key $Entry.Name
    if(-not $now){return}
    if(($now|ConvertTo-Json -Compress -Depth 5) -cne ($Entry|ConvertTo-Json -Compress -Depth 5)){throw "Startup entry changed since planning: $($Entry.Name)"}
    $result=Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName DeleteValue -Arguments @{hDefKey=[uint32]2147483651;sSubKeyName=[string]$Entry.Key;sValueName=[string]$Entry.Name}
    if($result.ReturnValue -ne 0){throw "Cannot remove startup value: $($Entry.Name)"}
}
function Split-StartupCommand([string]$Command){
    # Parse only a direct exe invocation, never cmd /c or shell expressions.
    $match=[regex]::Match($Command,'^\s*(?:"(?<file>[^"]+\.exe)"|(?<file>.+?\.exe))\s*(?<args>.*)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $match.Success){throw 'Startup command is not a direct executable'}
    $file=$match.Groups['file'].Value
    if(-not [IO.Path]::IsPathRooted($file)){throw 'Startup executable path must be absolute'}
    [pscustomobject]@{FilePath=$file;Arguments=$match.Groups['args'].Value;WorkingDirectory=(Split-Path $file)}
}
Export-ModuleMember -Function Read-StartupValue,Write-StartupValue,Remove-StartupValue,Split-StartupCommand
