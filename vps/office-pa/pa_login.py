"""
Login sekali ke akun Telegram pemilik (dijalankan sendiri di terminal, interaktif).
Menanyakan api_id & api_hash (dari https://my.telegram.org -> API development tools) bila belum ada
di .env, lalu nomor HP, kode OTP dari Telegram, dan password 2FA (kalau dipasang).
Sesi tersimpan di pa.session (izin 600). Hapus file itu untuk mencabut akses.
"""
import asyncio
import os

from telethon import TelegramClient

HERE = os.path.dirname(os.path.abspath(__file__))
ENV = os.path.join(HERE, ".env")


def read_env():
    d = {}
    if os.path.exists(ENV):
        for line in open(ENV, encoding="utf-8"):
            if "=" in line and not line.startswith("#"):
                k, v = line.strip().split("=", 1)
                d[k] = v
    return d


def write_env(d):
    with open(ENV, "w", encoding="utf-8") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")
    os.chmod(ENV, 0o600)


async def main():
    env = read_env()
    if not env.get("TG_API_ID") or not env.get("TG_API_HASH"):
        print("Ambil api_id & api_hash di https://my.telegram.org (API development tools).")
        env["TG_API_ID"] = input("api_id   : ").strip()
        env["TG_API_HASH"] = input("api_hash : ").strip()
    env.setdefault("PA_BOT", "Onel_PA_Bot")
    env.setdefault("PA_NAME", "Onel PA")
    write_env(env)
    client = TelegramClient(os.path.join(HERE, "pa"), int(env["TG_API_ID"]), env["TG_API_HASH"])
    await client.start()  # tanya nomor HP, kode OTP, password 2FA
    me = await client.get_me()
    bot = await client.get_entity(env["PA_BOT"])
    os.chmod(os.path.join(HERE, "pa.session"), 0o600)
    print(f"\nOK, login sebagai {me.first_name} (id {me.id}). Bot tujuan: @{bot.username}.")
    print("Sekarang kembali ke Claude dan bilang 'sudah login'.")
    await client.disconnect()


asyncio.run(main())
