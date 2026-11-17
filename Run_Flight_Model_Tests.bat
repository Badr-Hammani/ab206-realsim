@echo off
rem Runs the headless flight-model test suite (hover, ground effect, ETL, yaw, autorotation, landing, long run).
cd /d "%~dp0"
if not exist "%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" (
  echo Run Run_AB206.bat once first so the engine is downloaded.
  pause
  exit /b 1
)
"%~dp0engine\Godot_v4.6.3-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/run_tests.gd
echo.
echo Results are also saved in %%APPDATA%%\Godot\app_userdata\AB206 REALSIM\test_results.txt
pause
