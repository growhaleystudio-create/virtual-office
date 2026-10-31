# Virtual Office · Growhaley

Kantor virtual 3D bergaya retro (Godot 4.7.2). Tiap karakter mewakili satu AI agent; untuk sementara versi online menjalankan karyawan sebagai NPC otomatis.

## Main online
Versi web hasil export ada di `build/web` dan langsung disajikan Vercel (lihat `vercel.json`, tanpa build step).

## Update versi web
1. Buka project di Godot 4.7.2 (atau pakai baris perintah):
   `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/web/index.html`
2. Commit & push folder `build/web` — Vercel otomatis deploy ulang.

## Jalan di laptop (dengan relay AI)
Salin `bridge.cfg.example` jadi `bridge.cfg`, isi token, lalu jalankan `start_office.bat`.

## Kontrol
Klik kiri: pilih/jalan · tahan kiri: putar · tahan kanan: geser · scroll: zoom · 1/2/3: lantai · H: panel tim · hover karakter/berlian: info
