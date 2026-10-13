param()
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskLocalFlutter = Join-Path $taskRoot '.tools/flutter/bin/flutter.bat'
$taskFlutter = if (Test-Path -LiteralPath $taskLocalFlutter) { $taskLocalFlutter } else { 'flutter' }
if (Test-Path -LiteralPath $taskLocalFlutter) {
    $env:PUB_CACHE = Join-Path $taskRoot '.tools/pub-cache'
}

Push-Location -LiteralPath $taskRoot
try {
    # Flutter's Windows asset stamp can retain an older subset of Material icons.
    $taskCacheRoot = Join-Path $taskRoot '.dart_tool/flutter_build'
    if (Test-Path -LiteralPath $taskCacheRoot) {
        $taskCachePrefix = [IO.Path]::GetFullPath($taskCacheRoot) + [IO.Path]::DirectorySeparatorChar
        Get-ChildItem -LiteralPath $taskCacheRoot -Filter 'release_bundle_windows-x64_assets.stamp' -File -Recurse | ForEach-Object {
            $taskStampPath = [IO.Path]::GetFullPath($_.FullName)
            if (-not $taskStampPath.StartsWith($taskCachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Asset stamp lies outside the project cache: $taskStampPath"
            }
            Remove-Item -LiteralPath $taskStampPath
        }
    }
    & $taskFlutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Windows Release build failed: $LASTEXITCODE" }
}
finally {
    Pop-Location
}
