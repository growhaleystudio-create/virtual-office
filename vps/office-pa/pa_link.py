"""
pa_link.py - Menyambungkan bot Telegram teman (@Onel_PA_Bot) ke Virtual Office Growhaley.

Bot Telegram tidak bisa mengobrol dengan bot lain, dan @Onel_PA_Bot hanya melayani Telegram ID
pemilik. Jadi skrip ini login sebagai AKUN TELEGRAM PEMILIK (userbot, Telethon, sesi di pa.session)
dan menjadi perantara:

  kantor -> /api/sales {bot:"pa"} (Vercel cek login founder) -> amplop terenkripsi "pa_req"
  -> Supabase Realtime -> skrip ini -> pesan ke @Onel_PA_Bot -> kumpulkan balasan
  -> amplop terenkripsi "pa_rep" -> Vercel membukanya hanya untuk founder pengirim.

Status umum (tanpa isi obrolan) disiarkan sebagai "pa_status" untuk animasi karakter di kantor.

Konfigurasi: ~/marketing-bot/.env (OFFICE_LINK_SECRET, SUPABASE_URL, SUPABASE_KEY) lalu
~/office-pa/.env (TG_API_ID, TG_API_HASH, PA_BOT, opsional PA_NAME).
Login sekali: python pa_login.py (interaktif, di terminal sendiri).
"""
import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import time
import urllib.request

from telethon import TelegramClient, events

HERE = os.path.dirname(os.path.abspath(__file__))
TOPIC = "growhaley-office"
QUIET = 6.0  # detik tanpa pesan/edit baru dari bot = balasan dianggap selesai
FIRST_WAIT = 90.0  # batas menunggu balasan pertama
MAX_WAIT = 180.0  # batas total satu permintaan
LATE_WINDOW = 900.0  # balasan yang datang setelah batas tunggu tetap diteruskan selama 15 menit

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logging.getLogger("telethon").setLevel(logging.WARNING)
log = logging.getLogger("pa-link")


def load_env():
    for p in (os.path.expanduser("~/marketing-bot/.env"), os.path.join(HERE, ".env")):
        if not os.path.exists(p):
            continue
        for line in open(p, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


# ---------- amplop terenkripsi (sama persis dengan api/_link.js) ----------
def _keys():
    s = os.getenv("OFFICE_LINK_SECRET", "").strip().encode()
    return hmac.new(s, b"enc", hashlib.sha256).digest(), hmac.new(s, b"mac", hashlib.sha256).digest()


def _stream(k, iv, n):
    out = bytearray()
    c = 0
    while len(out) < n:
        out += hmac.new(k, iv + c.to_bytes(4, "big"), hashlib.sha256).digest()
        c += 1
    return bytes(out[:n])


def seal(obj) -> str:
    enc, mac = _keys()
    iv = secrets.token_bytes(16)
    pt = json.dumps(obj, ensure_ascii=False).encode()
    ct = bytes(a ^ b for a, b in zip(pt, _stream(enc, iv, len(pt))))
    tag = hmac.new(mac, iv + ct, hashlib.sha256).digest()[:16]
    return base64.b64encode(iv + tag + ct).decode()


def unseal(box: str):
    enc, mac = _keys()
    try:
        b = base64.b64decode(box)
    except Exception:  # noqa: BLE001
        return None
    if len(b) < 33:
        return None
    iv, tag, ct = b[:16], b[16:32], b[32:]
    if not hmac.compare_digest(tag, hmac.new(mac, iv + ct, hashlib.sha256).digest()[:16]):
        return None
    try:
        return json.loads(bytes(a ^ b for a, b in zip(ct, _stream(enc, iv, len(ct)))).decode())
    except Exception:  # noqa: BLE001
        return None


# ---------- kirim ke Supabase ----------
def _broadcast_sync(event, payload):
    url = os.getenv("SUPABASE_URL", "").rstrip("/") + "/realtime/v1/api/broadcast"
    body = json.dumps({"messages": [{"topic": TOPIC, "event": event, "payload": payload}]}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "apikey": os.getenv("SUPABASE_KEY", ""), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        r.read()


async def broadcast(event, payload):
    try:
        await asyncio.to_thread(_broadcast_sync, event, payload)
    except Exception:  # noqa: BLE001
        log.exception("broadcast %s gagal", event)


_status = {"text": "", "busy": False}


async def set_status(text: str, busy: bool = False):
    _status.update(text=text, busy=busy)
    await broadcast("pa_status", {"text": text, "busy": busy})


# ---------- Telegram (akun pemilik) ----------
class PA:
    def __init__(self):
        self.client = TelegramClient(os.path.join(HERE, "pa"), int(os.getenv("TG_API_ID", "0")), os.getenv("TG_API_HASH", ""))
        self.bot = None
        self.lock = asyncio.Lock()
        self.collect = None  # {msg_id: teks} saat sedang menunggu balasan
        self.last = 0.0
        self.last_req = None  # (founder, waktu) permintaan terakhir dari kantor
        self.late = {}
        self.late_task = None
        # ID topic tujuan di chat bot (pesan pembuat topic); 0 = chat biasa tanpa topic
        self.topic = int(os.getenv("PA_TOPIC", "0") or 0)

    async def start(self):
        await self.client.connect()
        if not await self.client.is_user_authorized():
            raise SystemExit("Sesi Telegram belum login. Jalankan dulu: python pa_login.py")
        self.bot = await self.client.get_input_entity(os.getenv("PA_BOT", "Onel_PA_Bot"))
        bot_peer = await self.client.get_peer_id(self.bot)

        @self.client.on(events.NewMessage(chats=bot_peer, incoming=True))
        @self.client.on(events.MessageEdited(chats=bot_peer, incoming=True))
        async def _on_bot_msg(ev):
            if self.topic:
                # chat bot dibagi per topic: hanya balasan di topic kantor (mis. "Growhaley")
                rt = ev.message.reply_to
                if not rt or self.topic not in (getattr(rt, "reply_to_top_id", None), getattr(rt, "reply_to_msg_id", None)):
                    return
            if self.collect is not None:
                self.collect[ev.message.id] = _describe(ev.message)
                self.last = time.monotonic()
            elif self.last_req and time.monotonic() - self.last_req[1] < LATE_WINDOW:
                # balasan datang setelah batas tunggu: tetap diteruskan ke peminta terakhir
                self.late[ev.message.id] = _describe(ev.message)
                self.last = time.monotonic()
                if not self.late_task or self.late_task.done():
                    self.late_task = asyncio.create_task(self._flush_late())

        log.info("Telegram siap, perantara ke %s", os.getenv("PA_BOT", "Onel_PA_Bot"))

    async def _flush_late(self):
        while time.monotonic() - self.last < QUIET:
            await asyncio.sleep(0.5)
        got, self.late = self.late, {}
        parts = _clean([got[k] for k in sorted(got)])
        if not parts or not self.last_req:
            return
        rid = "late-" + secrets.token_hex(6)
        log.info("balasan terlambat untuk %s", self.last_req[0])
        await broadcast("pa_rep", {"id": rid, "late": True,
                                   "box": seal({"id": rid, "to": self.last_req[0], "reply": "\n\n".join(parts)[:4000]})})

    async def ask(self, text: str, who: str = "") -> str:
        async with self.lock:
            self.last_req = (who, time.monotonic())
            self.late = {}
            self.collect = {}
            self.last = 0.0
            await self.client.send_message(self.bot, text, reply_to=self.topic or None)
            t0 = time.monotonic()
            while True:
                await asyncio.sleep(0.5)
                now = time.monotonic()
                if self.collect and now - self.last >= QUIET:
                    break
                if not self.collect and now - t0 > FIRST_WAIT:
                    break
                if now - t0 > MAX_WAIT:
                    break
            got, self.collect = self.collect, None
            parts = _clean([got[k] for k in sorted(got)])
            if not parts:
                self.last_req = (who, time.monotonic())  # jendela balasan terlambat mulai dari sini
                return "(bot belum membalas. Kalau nanti membalas dalam 15 menit, balasannya muncul di sini.)"
            return "\n\n".join(parts)


MEDIA_ONLY = "[mengirim file/gambar, lihat di Telegram]"


def _clean(parts):
    """Buang bagian kosong; stiker/animasi 'loading' tanpa teks dibuang kalau ada balasan teks."""
    parts = [p for p in parts if p]
    if any(p != MEDIA_ONLY for p in parts):
        parts = [p for p in parts if p != MEDIA_ONLY]
    return parts


def _describe(m) -> str:
    txt = (m.message or "").strip()
    if m.media and type(m.media).__name__ == "MessageMediaWebPage":
        return txt  # pratinjau link, bukan lampiran
    if m.media and not txt:
        return MEDIA_ONLY
    if m.media:
        txt += "\n[ada lampiran, lihat di Telegram]"
    if getattr(m, "buttons", None):
        labels = [b.text for row in m.buttons for b in row]
        if labels:
            txt += "\n[tombol: " + " · ".join(labels[:8]) + " - pilih di Telegram]"
    return txt


_seen = {}


async def handle_req(pa: PA, payload):
    d = unseal(payload.get("box", ""))
    if not d or not d.get("id") or not d.get("text"):
        log.warning("permintaan kantor ditolak (amplop tidak sah)")
        return
    if d.get("bot") != "pa":
        return
    if abs(time.time() * 1000 - float(d.get("ts", 0))) > 120_000 or d["id"] in _seen:
        return
    now = time.time()
    _seen[d["id"]] = now
    for k in [k for k, t in _seen.items() if now - t > 600]:
        _seen.pop(k, None)
    name = d.get("name") or d.get("from")
    await set_status("sedang mengerjakan", True)
    try:
        reply = await pa.ask(str(d["text"])[:1000], d.get("from") or "")
    except Exception as e:  # noqa: BLE001
        log.exception("tanya PA gagal")
        reply = f"Gagal menghubungi bot: {e}"
    log.info("balasan untuk %s: %d karakter", name, len(reply))
    await broadcast("pa_rep", {"id": d["id"], "box": seal({"id": d["id"], "to": d.get("from"), "reply": reply[:4000]})})
    await set_status("")


# ---------- sambungan websocket ke Supabase Realtime ----------
async def supabase_loop(pa: PA):
    import websockets

    host = os.getenv("SUPABASE_URL").replace("https://", "wss://").rstrip("/")
    url = f"{host}/realtime/v1/websocket?apikey={os.getenv('SUPABASE_KEY')}&vsn=1.0.0"
    topic = "realtime:" + TOPIC
    delay = 2
    while True:
        try:
            async with websockets.connect(url, ping_interval=None, max_size=2**20) as ws:
                ref = 0

                async def push(t, event, payload):
                    nonlocal ref
                    ref += 1
                    await ws.send(json.dumps({"topic": t, "event": event, "payload": payload, "ref": str(ref)}))

                await push(topic, "phx_join", {"config": {"broadcast": {"self": False}, "presence": {"key": "pa-bot"}, "private": False}})
                await push(topic, "presence", {"type": "presence", "event": "track", "payload": {"bot": "pa", "name": os.getenv("PA_NAME", "Onel PA")}})

                async def heartbeat():
                    while True:
                        await asyncio.sleep(25)
                        await push("phoenix", "heartbeat", {})

                hb = asyncio.create_task(heartbeat())
                log.info("tersambung ke Supabase")
                delay = 2
                await set_status(_status["text"], _status["busy"])
                try:
                    async for raw in ws:
                        m = json.loads(raw)
                        if m.get("event") != "broadcast":
                            continue
                        p = m.get("payload") or {}
                        ev = p.get("event")
                        if ev == "pa_req":
                            asyncio.create_task(handle_req(pa, p.get("payload") or {}))
                        elif ev == "hello":
                            asyncio.create_task(set_status(_status["text"], _status["busy"]))
                finally:
                    hb.cancel()
        except asyncio.CancelledError:
            raise
        except Exception as e:  # noqa: BLE001
            log.warning("Supabase putus: %s (sambung ulang %ss)", e, delay)
        await asyncio.sleep(delay)
        delay = min(delay * 2, 60)


async def main():
    load_env()
    for k in ("OFFICE_LINK_SECRET", "SUPABASE_URL", "SUPABASE_KEY", "TG_API_ID", "TG_API_HASH"):
        if not os.getenv(k):
            raise SystemExit(f"env {k} belum diisi")
    pa = PA()
    await pa.start()
    await asyncio.gather(supabase_loop(pa), pa.client.run_until_disconnected())


if __name__ == "__main__":
    asyncio.run(main())
