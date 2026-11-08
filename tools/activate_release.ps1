param(
    [string]$RunnerDirectory = (Join-Path $PSScriptRoot '../build/windows/x64/runner')
)
$ErrorActionPreference = 'Stop'
$taskRunner = [IO.Path]::GetFullPath($RunnerDirectory)
$taskPending = Join-Path $taskRunner 'Release.pending'
if (-not (Test-Path -LiteralPath $taskPending -PathType Container)) { return }

# Serialize concurrent launchers. The handle is always released, even on failure.
$taskUpdateLock = [IO.File]::Open((Join-Path $taskRunner '.release-update.lock'),
    [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    if (-not (Test-Path -LiteralPath $taskPending -PathType Container)) { return }
    foreach ($taskRequired in @('daymark.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $taskPending $taskRequired) -PathType Leaf)) {
            throw "The pending Release bundle is incomplete: $taskRequired"
        }
    }
    $taskCurrent = Join-Path $taskRunner 'Release'
    $taskPrevious = Join-Path $taskRunner ('Release.previous-' + [Guid]::NewGuid().ToString('N'))
    foreach ($taskPath in @($taskPending, $taskCurrent, $taskPrevious)) {
        if (-not ([IO.Path]::GetFullPath($taskPath)).StartsWith($taskRunner + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Release delivery path is outside the runner directory: $taskPath"
        }
    }
    $taskHadPrevious = Test-Path -LiteralPath $taskCurrent
    if ($taskHadPrevious) { [IO.Directory]::Move($taskCurrent, $taskPrevious) }
    try {
        [IO.Directory]::Move($taskPending, $taskCurrent)
    } catch {
        if ($taskHadPrevious) { [IO.Directory]::Move($taskPrevious, $taskCurrent) }
        throw
    }
} finally {
    $taskUpdateLock.Dispose()
}
