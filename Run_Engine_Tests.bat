@echo off
rem Engine start/shutdown tests (systems + flight model) and the checklist lessons flown by a robot pilot.
cd /d "%~dp0"
if not exist "%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" (
  echo Run Run_AB206.bat once first so the engine is downloaded.
  pause
  exit /b 1
)
"%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/engine_tests.gd
"%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/checklist_lesson_tests.gd
pause
