$ErrorActionPreference = 'Stop'
$taskPython = Join-Path $PSScriptRoot '.conda/python.exe'
if (-not (Test-Path -LiteralPath $taskPython)) {
    Write-Error 'Create the environment first: conda env create --prefix ./.conda --file environment.yml'
}
Push-Location -LiteralPath $PSScriptRoot
try {
    & $taskPython -m daymark @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
