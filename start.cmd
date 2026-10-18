@echo off
cd /d "%~dp0"
if not exist "build\windows\x64\runner\Release\daymark.exe" (
    echo Build the application first:
    echo flutter pub get
    echo flutter build windows --release
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
if errorlevel 1 pause
