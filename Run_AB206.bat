@echo off
rem AB206 REALSIM launcher. First run downloads the Godot 4.6.3 engine (about 70 MB, free, MIT licence).
setlocal
cd /d "%~dp0"
set "ENGINE=%~dp0engine\Godot_v4.6.3-stable_win64.exe"
if not exist "%ENGINE%" (
  echo Godot engine not found - downloading Godot 4.6.3 from github.com/godotengine ...
  if not exist "%~dp0engine" mkdir "%~dp0engine"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -Uri 'https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_win64.exe.zip' -OutFile 'engine\godot.zip'; Expand-Archive -Force 'engine\godot.zip' 'engine'; Remove-Item 'engine\godot.zip'"
)
if not exist "%ENGINE%" (
  echo.
  echo Download failed. Please download "Godot 4.6.3 - Windows 64-bit" from https://godotengine.org/download/archive/
  echo and put Godot_v4.6.3-stable_win64.exe into the "engine" folder next to this file.
  pause
  exit /b 1
)
if not exist "%~dp0.godot" (
  echo First start: preparing project files ...
  "%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" --headless --path "%~dp0." --import >nul 2>&1
)
start "" "%ENGINE%" --path "%~dp0."
