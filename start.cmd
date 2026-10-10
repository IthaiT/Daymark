@echo off
cd /d "%~dp0"
if not exist "build\windows\x64\runner\Release\daymark.exe" (
    echo Build the application first:
    echo flutter pub get
    echo flutter build windows --release
    pause
    exit /b 1
)
if "%~1"=="" (
    start "" "build\windows\x64\runner\Release\daymark.exe" --data-dir "%~dp0data"
) else (
    start "" "build\windows\x64\runner\Release\daymark.exe" %*
)
