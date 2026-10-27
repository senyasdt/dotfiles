$ErrorActionPreference='Stop'
$repoRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source=Join-Path $repoRoot 'dot_config\desktop-customization\appearance'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('appearance-check-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $testRoot 'profile'
[void][IO.Directory]::CreateDirectory($root)
foreach($name in 'Manage-Appearance.ps1','palette.json','vscode.json','windows-terminal.json','wezterm.toml'){Copy-Item -LiteralPath (Join-Path $source $name) -Destination $root}
$manager=Join-Path $root 'Manage-Appearance.ps1'
$fixture=Join-Path $testRoot 'fixture'
$code=Join-Path $fixture 'AppData\Roaming\Code\User\settings.json'
$term=Join-Path $fixture 'AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$theme=Join-Path $fixture '.config\wezterm\theme'
$active=Join-Path $fixture '.config\wezterm\active_scheme.toml'
function Write-FixtureFile($path,$text){[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,$text)}
Write-FixtureFile $code '{"editor.tabSize":3,"custom.flag":"keep","workbench.colorCustomizations":{"[Other Theme]":{"editor.background":"#010203"}}}'
Write-FixtureFile $term '{"defaultProfile":"keep-profile","keybindings":[{"keys":"ctrl+k","id":"Keep"}],"profiles":{"defaults":{"cursorShape":"bar"},"list":[{"name":"PS","commandline":"keep.exe","colorScheme":"Catppuccin Macchiato","backgroundImage":"keep.png"}]},"schemes":[{"name":"Catppuccin Macchiato","background":"#24273a"}]}'
Write-FixtureFile $theme "forest`n"
Write-FixtureFile $active 'theme = "generated"'
$original=@{};foreach($p in $code,$term,$theme,$active){$original[$p]=(Get-FileHash -LiteralPath $p).Hash}
$count=0
function Assert($condition,$label){if(!$condition){throw ('FAIL: '+$label)};$script:count++}
& $manager -Action Apply -TargetHome $fixture -WhatIf
Assert ((Get-FileHash -LiteralPath $code).Hash -eq $original[$code]) 'WhatIf is read-only'
$applied=& $manager -Action Apply -TargetHome $fixture
Assert ($applied.ChangedFiles -eq 5) 'five appearance files'
$c=Get-Content -LiteralPath $code -Raw|ConvertFrom-Json
Assert ($c.'editor.tabSize' -eq 3 -and $c.'custom.flag' -eq 'keep') 'unrelated editor settings preserved'
Assert ($c.'workbench.colorCustomizations'.'[Other Theme]'.'editor.background' -eq '#010203') 'other theme preserved'
Assert ($c.'workbench.colorTheme' -eq 'Default Dark Modern') 'native editor theme'
$t=Get-Content -LiteralPath $term -Raw|ConvertFrom-Json
Assert ($t.defaultProfile -eq 'keep-profile' -and $t.keybindings[0].keys -eq 'ctrl+k') 'terminal launch and keys preserved'
Assert ($t.profiles.list[0].backgroundImage -eq 'keep.png' -and $t.profiles.list[0].commandline -eq 'keep.exe') 'terminal picture and command preserved'
Assert ($t.profiles.defaults.cursorShape -eq 'bar' -and $t.profiles.defaults.colorScheme -eq 'Cold Grey') 'terminal defaults merged'
Assert (@($t.schemes|Where-Object name -EQ 'Catppuccin Macchiato').Count -eq 1) 'previous scheme retained'
$second=& $manager -Action Apply -TargetHome $fixture
Assert ($second -like 'Appearance is already current*') 'second Apply is a no-op'
& $manager -Action Restore -TargetHome $fixture -Backup $applied.Backup -WhatIf
Assert ((Get-Content -LiteralPath $theme -Raw).Trim() -eq 'Cold Grey') 'WhatIf Restore is read-only'
& $manager -Action Restore -TargetHome $fixture -Backup $applied.Backup
foreach($p in $original.Keys){Assert ((Get-FileHash -LiteralPath $p).Hash -eq $original[$p]) 'byte-exact rollback'}
Assert (!(Test-Path -LiteralPath (Join-Path $fixture '.config\wezterm\themes\cold-grey.toml'))) 'new scheme removed on rollback'
$applied=& $manager -Action Apply -TargetHome $fixture
Add-Content -LiteralPath $code -Value ' '
$blocked=$false;try{& $manager -Action Restore -TargetHome $fixture -Backup $applied.Backup}catch{$blocked=$true}
Assert $blocked 'restore protects subsequent edits'
Assert ((Get-Content -LiteralPath $theme -Raw).Trim() -eq 'Cold Grey') 'conflicting restore performs no writes'
Write-FixtureFile $code '{/* comment */ "editor.tabSize": 3}'
$blocked=$false;try{& $manager -Action Apply -TargetHome $fixture}catch{$blocked=$true}
Assert $blocked 'unsupported JSONC fails before writes'
Write-Output ('PASS: '+$count+' appearance merge/WhatIf/idempotency/rollback checks; real profile untouched.')
