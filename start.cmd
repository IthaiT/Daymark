@echo off
cd /d "%~dp0"
if not exist ".conda\pythonw.exe" (
    echo Create the environment first:
    echo conda env create --prefix ./.conda --file environment.yml
    pause
    exit /b 1
)
start "" ".conda\pythonw.exe" -m daymark
