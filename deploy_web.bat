@echo off
rem Export ulang versi web ke build/web (lalu commit & push, Vercel deploy otomatis)
cd /d %~dp0
"C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Web" build\web\index.html
cd build\web
rem Deploy lewat Vercel: cukup commit & push build/web ke GitHub
