@echo off
rem Jalankan relay (lokal, 127.0.0.1:8765) lalu Virtual Office.
cd /d %~dp0
for /f "tokens=2 delims==" %%t in ('findstr /b "token=" bridge.cfg') do set OFFICE_TOKEN=%%~t
start "Office Relay" /min bridge\.venv\Scripts\python.exe bridge\relay.py --host 127.0.0.1 --port 8765
start "" C:\Godot\Godot_v4.7.2-stable_win64.exe --path .
