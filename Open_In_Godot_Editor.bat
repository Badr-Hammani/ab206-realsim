@echo off
rem Opens the project in the Godot editor (for development).
cd /d "%~dp0"
start "" "%~dp0engine\Godot_v4.6.3-stable_win64.exe" -e --path "%~dp0."
