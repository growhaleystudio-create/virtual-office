"""Relay antara Virtual Office (Godot) dan bot (Telegram/WA).

Godot (di PC) konek KELUAR ke relay lewat WebSocket, jadi PC tidak perlu IP publik.
Bot di VPS cukup memanggil HTTP lokal:

  POST /command  {"text": "Sales ke pantry"}            -> {"ok": true, "reply": "..."}
  POST /status   {"agent": "Sales", "text": "kirim 3 WA", "ttl": 300}
                 (ttl detik; text kosong = hapus status)  -> {"ok": true, ...}
  GET  /state                                           -> status semua agent terakhir

Semua endpoint & WebSocket butuh token: header "Authorization: Bearer <TOKEN>"
atau query ?token=<TOKEN>. Jalankan:

  OFFICE_TOKEN=rahasia python relay.py --host 0.0.0.0 --port 8765
"""
import argparse
import asyncio
import hmac
import itertools
import json
import logging
import os
import time

from aiohttp import WSMsgType, web

log = logging.getLogger("relay")
TOKEN = os.environ.get("OFFICE_TOKEN", "")
REPLY_TIMEOUT = 5.0


class Hub:
    def __init__(self):
        self.office: web.WebSocketResponse | None = None
        self.pending: dict[int, asyncio.Future] = {}
        self.ids = itertools.count(1)
        self.state: list = []
        self.statuses: dict[str, dict] = {}  # status nyata, dikirim ulang saat Godot konek

    async def send(self, msg: dict) -> bool:
        ws = self.office
        if ws is None or ws.closed:
            return False
        await ws.send_str(json.dumps(msg))
        return True


hub = Hub()


def authorized(req: web.Request) -> bool:
    if not TOKEN:
        return True
    got = req.query.get("token", "")
    auth = req.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        got = auth[7:]
    return hmac.compare_digest(got, TOKEN)


@web.middleware
async def auth_mw(req, handler):
    if not authorized(req):
        return web.json_response({"ok": False, "error": "unauthorized"}, status=401)
    return await handler(req)


async def ws_office(req: web.Request):
    ws = web.WebSocketResponse(heartbeat=20)
    await ws.prepare(req)
    if hub.office is not None and not hub.office.closed:
        await hub.office.close(message=b"replaced")
    hub.office = ws
    log.info("office terhubung dari %s", req.remote)
    now = time.time()
    for key, st in list(hub.statuses.items()):
        left = st["until"] - now
        if left <= 0:
            hub.statuses.pop(key)
            continue
        await ws.send_str(json.dumps({"type": "status", "agent": st["agent"], "text": st["text"], "ttl": left}))
    try:
        async for msg in ws:
            if msg.type != WSMsgType.TEXT:
                continue
            try:
                data = json.loads(msg.data)
            except ValueError:
                continue
            kind = data.get("type")
            if kind == "reply":
                fut = hub.pending.pop(data.get("id"), None)
                if fut and not fut.done():
                    fut.set_result(data.get("text", ""))
            elif kind == "state":
                hub.state = data.get("agents", [])
    finally:
        if hub.office is ws:
            hub.office = None
        log.info("office terputus")
    return ws


async def post_command(req: web.Request):
    body = await req.json()
    text = str(body.get("text", "")).strip()
    if not text:
        return web.json_response({"ok": False, "error": "text kosong"}, status=400)
    cid = next(hub.ids)
    fut = asyncio.get_running_loop().create_future()
    hub.pending[cid] = fut
    if not await hub.send({"type": "command", "id": cid, "text": text}):
        hub.pending.pop(cid, None)
        return web.json_response({"ok": False, "error": "office offline"}, status=503)
    try:
        reply = await asyncio.wait_for(fut, REPLY_TIMEOUT)
    except asyncio.TimeoutError:
        hub.pending.pop(cid, None)
        return web.json_response({"ok": False, "error": "office tidak membalas"}, status=504)
    return web.json_response({"ok": True, "reply": reply})


async def post_status(req: web.Request):
    body = await req.json()
    agent = str(body.get("agent", "")).strip()
    if not agent:
        return web.json_response({"ok": False, "error": "agent kosong"}, status=400)
    st = {"agent": agent, "text": str(body.get("text", "")).strip(), "ttl": float(body.get("ttl", 300))}
    if st["text"]:
        hub.statuses[agent.lower()] = {**st, "until": time.time() + st["ttl"]}
    else:
        hub.statuses.pop(agent.lower(), None)
    delivered = await hub.send({"type": "status", **st})
    return web.json_response({"ok": True, "delivered": delivered})


async def get_state(req: web.Request):
    online = hub.office is not None and not hub.office.closed
    return web.json_response({"ok": True, "online": online, "agents": hub.state})


def make_app() -> web.Application:
    app = web.Application(middlewares=[auth_mw])
    app.router.add_get("/ws", ws_office)
    app.router.add_post("/command", post_command)
    app.router.add_post("/status", post_status)
    app.router.add_get("/state", get_state)
    return app


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    if not TOKEN:
        log.warning("OFFICE_TOKEN kosong: relay TANPA autentikasi")
    web.run_app(make_app(), host=a.host, port=a.port, print=None)
