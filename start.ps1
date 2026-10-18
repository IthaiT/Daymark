$ErrorActionPreference = 'Stop'
$taskExecutable = Join-Path $PSScriptRoot 'build/windows/x64/runner/Release/daymark.exe'
if (-not (Test-Path -LiteralPath $taskExecutable)) {
    Write-Error 'Build the application first: flutter pub get; flutter build windows --release'
}

# Daymark is single-instance per data directory. If a window is already open,
# bring it to the front instead of starting a second copy that can only show
# the "data directory is already open" error.
$existing = Get-Process daymark -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Sort-Object StartTime |
    Select-Object -First 1
if ($existing) {
    Add-Type -Name Window -Namespace Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
    [void][Native.Window]::ShowWindow($existing.MainWindowHandle, 9)
    [void][Native.Window]::SetForegroundWindow($existing.MainWindowHandle)
    exit 0
}

$taskArguments = if ($args.Count -eq 0) {
    @('--data-dir', (Join-Path $PSScriptRoot 'data'))
} else {
    $args
}
Start-Process -FilePath $taskExecutable -ArgumentList $taskArguments -WorkingDirectory $PSScriptRoot
