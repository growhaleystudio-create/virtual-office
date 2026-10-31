@echo off
rem Export versi web lalu upload ke Vercel (butuh: npx vercel login sekali)
cd /d %~dp0
"C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Web" build\web\index.html
cd build\web
rem Deploy lewat Vercel: cukup commit & push build/web ke GitHub
