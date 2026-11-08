$ErrorActionPreference = 'Stop'
$taskRepository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskArtifacts = Join-Path $taskRepository '.test-artifacts'
$taskDirectory = Join-Path $taskArtifacts ('release-delivery-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
$taskActivation = Join-Path $PSScriptRoot 'activate_release.ps1'
function New-TestBundle([string]$Path, [string]$Content) {
    foreach ($taskRelative in @('daymark.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
        $taskFile = Join-Path $Path $taskRelative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($taskFile)) -Force | Out-Null
        [IO.File]::WriteAllText($taskFile, $Content)
    }
}
function Assert-Delivery([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$taskNoUpdate = Join-Path $taskDirectory 'no-update'
New-TestBundle (Join-Path $taskNoUpdate 'Release') 'old'
& $taskActivation -RunnerDirectory $taskNoUpdate
Assert-Delivery ((Get-Content -Raw (Join-Path $taskNoUpdate 'Release/daymark.exe')) -eq 'old') 'No update must preserve the current build.'

$taskValid = Join-Path $taskDirectory 'valid'
New-TestBundle (Join-Path $taskValid 'Release') 'old'
New-TestBundle (Join-Path $taskValid 'Release.pending') 'new'
& $taskActivation -RunnerDirectory $taskValid
Assert-Delivery ((Get-Content -Raw (Join-Path $taskValid 'Release/data/app.so')) -eq 'new') 'The complete new bundle must become current.'
Assert-Delivery (-not (Test-Path (Join-Path $taskValid 'Release.pending'))) 'Activation must consume the pending bundle.'
$taskBackup = @(Get-ChildItem -LiteralPath $taskValid -Directory -Filter 'Release.previous-*')
Assert-Delivery ($taskBackup.Count -eq 1) 'Activation must retain one rollback build.'
Assert-Delivery ((Get-Content -Raw (Join-Path $taskBackup[0].FullName 'daymark.exe')) -eq 'old') 'The rollback build must contain the previous bytes.'

$taskIncomplete = Join-Path $taskDirectory 'incomplete'
New-TestBundle (Join-Path $taskIncomplete 'Release') 'old'
New-Item -ItemType Directory -Path (Join-Path $taskIncomplete 'Release.pending') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $taskIncomplete 'Release.pending/daymark.exe'), 'incomplete')
$taskRejected = $false
try { & $taskActivation -RunnerDirectory $taskIncomplete } catch { $taskRejected = $true }
Assert-Delivery $taskRejected 'An incomplete pending bundle must be rejected.'
Assert-Delivery ((Get-Content -Raw (Join-Path $taskIncomplete 'Release/daymark.exe')) -eq 'old') 'Rejected updates must preserve the current build.'

$taskBlocked = Join-Path $taskDirectory 'blocked'
New-TestBundle (Join-Path $taskBlocked 'Release') 'old'
New-TestBundle (Join-Path $taskBlocked 'Release.pending') 'new'
$taskHeldFile = [IO.File]::Open((Join-Path $taskBlocked 'Release.pending/daymark.exe'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try {
    $taskRejected = $false
    try { & $taskActivation -RunnerDirectory $taskBlocked } catch { $taskRejected = $true }
    Assert-Delivery $taskRejected 'A blocked directory move must fail.'
    Assert-Delivery ((Get-Content -Raw (Join-Path $taskBlocked 'Release/daymark.exe')) -eq 'old') 'Failed activation must roll back the previous build.'
} finally {
    $taskHeldFile.Dispose()
}
& $taskActivation -RunnerDirectory $taskBlocked
Assert-Delivery ((Get-Content -Raw (Join-Path $taskBlocked 'Release/daymark.exe')) -eq 'new') 'Activation must succeed on retry after the handle is released.'
Write-Output "Release delivery passed: no update, complete activation, rollback copy, incomplete rejection, failed-move rollback and retry. Artifacts: $taskDirectory"
