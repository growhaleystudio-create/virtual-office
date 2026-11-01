@echo off
rem Export ulang versi web ke build/web (lalu commit & push, Vercel deploy otomatis)
cd /d %~dp0
"C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Web" build/web/index.html
if not exist build\web\static mkdir build\web\static
copy /y web\static\*.* build\web\static\ >nul
echo Selesai. Sekarang commit dan push folder build/web.
