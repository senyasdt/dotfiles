$ErrorActionPreference='Stop'
$source=$PSScriptRoot
$root=Join-Path ([IO.Path]::GetTempPath()) ('launchpad-task-check-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
foreach($name in 'Set-LaunchpadSync.ps1','Sync-Apps.ps1','Sync-Apps-Hidden.vbs'){Copy-Item -LiteralPath (Join-Path $source $name) -Destination $root}
$taskFile=Join-Path $root 'Set-LaunchpadSync.ps1'
$global:LaunchpadTaskFixture=@{Exists=$true;Running=$true;Stops=0;Removed=0;FailStop=$false;Foreign=$false;Modern=$false}
function Get-ScheduledTask($TaskName,$ErrorAction){
 if(!$global:LaunchpadTaskFixture.Exists){return}
 $target=if($global:LaunchpadTaskFixture.Foreign){'C:\other\Sync-Apps.ps1'}elseif($global:LaunchpadTaskFixture.Modern){Join-Path $root 'Sync-Apps-Hidden.vbs'}else{Join-Path $root 'Sync-Apps.ps1'}
 [pscustomobject]@{State=$(if($global:LaunchpadTaskFixture.Running){'Running'}else{'Ready'});Actions=@([pscustomobject]@{Arguments='"'+$target+'"'})}
}
function Stop-ScheduledTask($TaskName,$ErrorAction){
 if($global:LaunchpadTaskFixture.FailStop){throw 'fixture stop failed'}
 $global:LaunchpadTaskFixture.Stops++;$global:LaunchpadTaskFixture.Running=$false
}
function Unregister-ScheduledTask($TaskName,$Confirm){
 if($global:LaunchpadTaskFixture.Running){throw 'Unregistered a running sync'}
 $global:LaunchpadTaskFixture.Removed++;$global:LaunchpadTaskFixture.Exists=$false
}
try{
 foreach($modern in @($false,$true)){
  $global:LaunchpadTaskFixture.Exists=$true;$global:LaunchpadTaskFixture.Running=$true;$global:LaunchpadTaskFixture.Modern=$modern
  & $taskFile -Action Disable
  if($global:LaunchpadTaskFixture.Exists -or $global:LaunchpadTaskFixture.Running){throw 'Owned task not stopped and removed'}
 }
 & $taskFile -Action Disable
 if($global:LaunchpadTaskFixture.Removed -ne 2){throw 'Repeated disable was not idempotent'}
 $global:LaunchpadTaskFixture.Exists=$true;$global:LaunchpadTaskFixture.Running=$true;$global:LaunchpadTaskFixture.FailStop=$true
 $rejected=$false;try{& $taskFile -Action Disable}catch{$rejected=$_.Exception.Message -eq 'fixture stop failed'}
 if(!$rejected -or !$global:LaunchpadTaskFixture.Exists){throw 'Failed stop was ignored'}
 $global:LaunchpadTaskFixture.FailStop=$false;$global:LaunchpadTaskFixture.Foreign=$true
 $rejected=$false;try{& $taskFile -Action Disable}catch{$rejected=$_.Exception.Message -like 'Task name belongs*'}
 if(!$rejected -or !$global:LaunchpadTaskFixture.Exists){throw 'Foreign task ownership lost'}
 $global:LaunchpadTaskFixture.Foreign=$false
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'Manage.ps1'),[ref]$tokens,[ref]$errors)
 $restore=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Restore-Current'},$false)
 . ([scriptblock]::Create($restore.Extent.Text))
 $predock=$ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$Action -eq ''RestorePreDock'''}
 $body=$predock.Clauses[0].Item2.Extent.Text
 $predockCode=[scriptblock]::Create($body.Substring(1,$body.Length-2))
 [IO.File]::WriteAllText((Join-Path $root 'config-predock.yaml'),'fixture')
 function Snapshot { [pscustomobject]@{} }
 function Stop-Yasb {
  if($global:LaunchpadTaskFixture.Exists -or $global:LaunchpadTaskFixture.Running){throw 'Rollback changed desktop before stopping sync'}
  throw 'fixture reached safe rollback'
 }
 foreach($run in @({Restore-Current},$predockCode)){
  $global:LaunchpadTaskFixture.Exists=$true;$global:LaunchpadTaskFixture.Running=$true
  $safe=$false;try{& $run}catch{$safe=$_.Exception.Message -eq 'fixture reached safe rollback'}
  if(!$safe){throw 'Rollback did not stop sync before touching desktop'}
 }
 Write-Output 'PASS: sync task legacy/GUI ownership, stop failure, foreign ownership, idempotency and both rollback paths. No real task or desktop changes.'
}finally{Remove-Variable -Name LaunchpadTaskFixture -Scope Global}
