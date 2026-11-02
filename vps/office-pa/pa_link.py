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
import re
import urllib.error
import urllib.parse
import urllib.request

from telethon import TelegramClient, events

HERE = os.path.dirname(os.path.abspath(__file__))
TOPIC = "growhaley-office"
QUIET = 6.0  # detik tanpa pesan/edit baru dari bot = balasan dianggap selesai
FIRST_WAIT = 90.0  # batas menunggu balasan pertama
MAX_WAIT = 180.0  # batas total satu permintaan
LATE_WINDOW = 1800.0  # balasan yang datang setelah batas tunggu tetap diteruskan selama 30 menit (artikel panjang)

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


# ---------- Hasil Kerja: file dari bot disimpan di Supabase Storage (bucket privat) ----------
# Butuh SUPABASE_SECRET (secret / service_role key) di ~/office-pa/.env. Kunci ini HANYA di VPS.
BUCKET = "hasil-kerja"
MAX_FILE = 20 * 1024 * 1024
LONG_TEXT = 1500  # balasan teks sepanjang ini (mis. artikel) juga disimpan sebagai .docx
DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
ROLES = ("Riset", "Copywriter", "Desainer", "Admin")


def _storage_sync(method, path, data=None, ctype="application/json", extra=None):
    key = os.getenv("SUPABASE_SECRET", "")
    url = os.getenv("SUPABASE_URL", "").rstrip("/") + "/storage/v1/" + path
    if isinstance(data, (dict, list)):
        data = json.dumps(data).encode()
    h = {"apikey": key, "Authorization": "Bearer " + key, "Content-Type": ctype}
    h.update(extra or {})
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
    return json.loads(body) if body[:1] in (b"{", b"[") else body


async def storage(*a, **k):
    return await asyncio.to_thread(_storage_sync, *a, **k)


def storage_ready() -> bool:
    return bool(os.getenv("SUPABASE_SECRET"))


async def ensure_bucket():
    if not storage_ready():
        log.info("Hasil Kerja nonaktif (SUPABASE_SECRET belum diisi)")
        return
    try:
        await storage("POST", "bucket", {"id": BUCKET, "name": BUCKET, "public": False, "file_size_limit": MAX_FILE})
        log.info("bucket %s dibuat", BUCKET)
    except urllib.error.HTTPError as e:
        body = e.read()[:200]
        if b"already exists" not in body and b"Duplicate" not in body:
            log.warning("buat bucket gagal: %s %s", e.code, body)


def _safe_name(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._ -]+", "", name).strip().replace(" ", "_")
    return (name or "dokumen")[:80]


def parse_key(key: str) -> dict:
    """<waktu>__<peran>__<nama file> -> info untuk kantor."""
    parts = key.split("__", 2)
    if len(parts) != 3:
        return {"key": key, "name": key, "role": "", "time": ""}
    t = parts[0]
    nice = f"{t[6:8]}/{t[4:6]} {t[9:11]}:{t[11:13]}" if len(t) >= 13 else t
    return {"key": key, "name": parts[2], "role": parts[1], "time": nice}


async def list_files(limit=40) -> list:
    res = await storage("POST", f"object/list/{BUCKET}", {"prefix": "", "limit": limit, "offset": 0,
                                                          "sortBy": {"column": "name", "order": "desc"}})
    objs = [o for o in res if o.get("id")]
    if not objs:
        return []
    signed = await storage("POST", f"object/sign/{BUCKET}", {"expiresIn": 3600, "paths": [o["name"] for o in objs]})
    base = os.getenv("SUPABASE_URL", "").rstrip("/") + "/storage/v1"
    out = []
    for o, sg in zip(objs, signed):
        info = parse_key(o["name"])
        info["size"] = (o.get("metadata") or {}).get("size", 0)
        if sg.get("signedURL"):
            info["url"] = base + sg["signedURL"]
            info["dl"] = info["url"] + "&download=" + urllib.parse.quote(info["name"])
        out.append(info)
    return out


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
        self.role = "Admin"  # staf yang terakhir diberi tugas dari kantor
        self._stored = set()

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
            m = ev.message
            if _is_doc(m) and m.id not in self._stored:
                self._stored.add(m.id)
                asyncio.create_task(self._store_file(m))
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

    async def _store_file(self, m):
        """File dari bot (docx/pdf/xlsx/...) -> Storage, lalu kabari kantor (event pa_file)."""
        if not storage_ready():
            return
        name = _safe_name(m.file.name or ("dokumen" + (m.file.ext or "")))
        if (m.file.size or 0) > MAX_FILE:
            log.warning("file %s terlalu besar (%s byte), dilewati", name, m.file.size)
            return
        try:
            data = await self.client.download_media(m, file=bytes)
            await self._store_bytes(data, name, m.file.mime_type or "application/octet-stream")
        except Exception:  # noqa: BLE001
            log.exception("simpan file %s gagal", name)

    async def _store_bytes(self, data: bytes, name: str, mime: str):
        key = f"{time.strftime('%Y%m%d-%H%M%S')}__{self.role}__{name}"
        await storage("POST", f"object/{BUCKET}/{urllib.parse.quote(key)}", data, ctype=mime, extra={"x-upsert": "true"})
        owner = (self.last_req[0] if self.last_req else "") or os.getenv("PA_OWNER", "angga")
        info = parse_key(key)
        log.info("file tersimpan: %s (%d byte) untuk %s", key, len(data), owner)
        rid = "file-" + secrets.token_hex(6)
        await broadcast("pa_file", {"id": rid, "box": seal({"id": rid, "to": owner, "file": info})})

    async def keep_long(self, text: str) -> str:
        """Balasan teks panjang (artikel dsb.) -> simpan juga sebagai .docx; kembalikan ringkasan untuk chat."""
        if len(text) < LONG_TEXT or not storage_ready():
            return text
        try:
            import md2docx  # python-docx (di venv bot)

            title = md2docx.title_of(text)
            data = await asyncio.to_thread(md2docx.convert, text)
            await self._store_bytes(data, _safe_name(title) + ".docx", DOCX_MIME)
            head = text[:400].rsplit(" ", 1)[0]
            return f"{head}...\n\n[teks lengkap ({len(text.split())} kata) disimpan di Hasil Kerja sebagai {_safe_name(title)}.docx]"
        except Exception:  # noqa: BLE001
            log.exception("simpan teks panjang gagal")
            return text

    async def _flush_late(self):
        while time.monotonic() - self.last < QUIET:
            await asyncio.sleep(0.5)
        got, self.late = self.late, {}
        parts = _clean([got[k] for k in sorted(got)])
        if not parts or not self.last_req:
            return
        rid = "late-" + secrets.token_hex(6)
        log.info("balasan terlambat untuk %s", self.last_req[0])
        reply = await self.keep_long("\n\n".join(parts))
        await broadcast("pa_rep", {"id": rid, "late": True,
                                   "box": seal({"id": rid, "to": self.last_req[0], "reply": reply[:15000]})})

    async def ask(self, text: str, who: str = "") -> str:
        mr = re.search(r"staf (\w+)", text[:120])
        if mr and mr.group(1) in ROLES:
            self.role = mr.group(1)
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
                # stiker "loading" tanpa teks belum dihitung sebagai balasan
                real = any(v and v != MEDIA_ONLY for v in self.collect.values())
                if real and now - self.last >= QUIET:
                    break
                if not real and now - t0 > FIRST_WAIT:
                    break
                if now - t0 > MAX_WAIT:
                    break
            got, self.collect = self.collect, None
            parts = _clean([got[k] for k in sorted(got)])
            if not parts:
                self.last_req = (who, time.monotonic())  # jendela balasan terlambat mulai dari sini
                return "(Onel masih mengerjakan. Balasannya muncul di sini begitu selesai, maksimal 30 menit.)"
        return await self.keep_long("\n\n".join(parts))


MEDIA_ONLY = "[mengirim file/gambar, lihat di Telegram]"


def _clean(parts):
    """Buang bagian kosong; stiker/animasi 'loading' tanpa teks dibuang kalau ada balasan teks."""
    parts = [p for p in parts if p]
    if any(p != MEDIA_ONLY for p in parts):
        parts = [p for p in parts if p != MEDIA_ONLY]
    return parts


def _is_doc(m) -> bool:
    return bool(m.document) and not m.sticker and not m.gif and not m.video_note


def _describe(m) -> str:
    # m.text = teks + format Telegram dalam Markdown (**tebal**, __miring__) -> heading terbaca di .docx
    txt = (m.text or m.message or "").strip()
    if _is_doc(m) and storage_ready():
        fn = m.file.name or "dokumen"
        return (txt + "\n" if txt else "") + f"[file {fn} tersimpan di Hasil Kerja]"
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
    if not d or not d.get("id") or not (d.get("text") or d.get("op")):
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
    if d.get("op") == "files":
        # daftar Hasil Kerja + link bertanda tangan (1 jam), hanya untuk founder peminta
        try:
            files = await list_files() if storage_ready() else []
            note = "" if storage_ready() else "Penyimpanan belum aktif (SUPABASE_SECRET belum diisi di VPS)."
        except Exception as e:  # noqa: BLE001
            log.exception("daftar file gagal")
            files, note = [], f"Gagal membaca daftar file: {e}"
        await broadcast("pa_rep", {"id": d["id"], "box": seal({"id": d["id"], "to": d.get("from"), "files": files, "note": note})})
        return
    name = d.get("name") or d.get("from")
    await set_status("sedang mengerjakan", True)
    try:
        reply = await pa.ask(str(d["text"])[:3000], d.get("from") or "")
    except Exception as e:  # noqa: BLE001
        log.exception("tanya PA gagal")
        reply = f"Gagal menghubungi bot: {e}"
    log.info("balasan untuk %s: %d karakter", name, len(reply))
    await broadcast("pa_rep", {"id": d["id"], "box": seal({"id": d["id"], "to": d.get("from"), "reply": reply[:15000]})})
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
    await ensure_bucket()
    await asyncio.gather(supabase_loop(pa), pa.client.run_until_disconnected())


if __name__ == "__main__":
    asyncio.run(main())
