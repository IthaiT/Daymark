$ErrorActionPreference = 'Stop'
$taskExecutable = Join-Path $PSScriptRoot 'build/windows/x64/runner/Release/daymark.exe'
if (-not (Test-Path -LiteralPath $taskExecutable)) {
    Write-Error 'Build the application first: flutter pub get; flutter build windows --release'
}
$taskArguments = if ($args.Count -eq 0) { @('--data-dir', (Join-Path $PSScriptRoot 'data')) } else { $args }
Push-Location -LiteralPath $PSScriptRoot
try {
    & $taskExecutable @taskArguments
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
