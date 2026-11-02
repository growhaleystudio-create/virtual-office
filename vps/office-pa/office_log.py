"""Log kunjungan tamu kantor virtual (SQLite di ~/office-pa/visits.db).

Perantara di VPS selalu tersambung ke channel Supabase, jadi ia melihat presence semua pemain.
Tamu = presence dengan key "g:<id>" (nama & gender dari meta). Founder bisa membaca log lewat
/api/sales {bot:"office", op:"visits"} (dicek login founder, balasan terenkripsi).
"""
import os
import sqlite3
import time

DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "visits.db")


def _con():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c


def init():
    with _con() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY, gid TEXT, name TEXT, g TEXT,
            start REAL, last REAL, end REAL)""")
        # program sempat mati: kunjungan yang masih terbuka ditutup di waktu terakhir terlihat
        c.execute("UPDATE visits SET end = last WHERE end IS NULL")


def sync(online: dict):
    """online = {gid: (name, g)} tamu yang sedang ada di kantor. Catat yang baru masuk / keluar."""
    now = time.time()
    with _con() as c:
        open_rows = {r["gid"]: r for r in c.execute("SELECT * FROM visits WHERE end IS NULL")}
        for gid, (name, g) in online.items():
            if gid in open_rows:
                c.execute("UPDATE visits SET last = ?, name = ?, g = ? WHERE id = ?", (now, name, g, open_rows[gid]["id"]))
            else:
                c.execute("INSERT INTO visits (gid, name, g, start, last) VALUES (?, ?, ?, ?, ?)", (gid, name, g, now, now))
        for gid, r in open_rows.items():
            if gid not in online:
                c.execute("UPDATE visits SET end = ?, last = ? WHERE id = ?", (now, now, r["id"]))


def recent(limit=60) -> list:
    with _con() as c:
        rows = c.execute("SELECT * FROM visits ORDER BY start DESC LIMIT ?", (limit,)).fetchall()
        total = c.execute("SELECT COUNT(*) AS n, COUNT(DISTINCT gid) AS u FROM visits WHERE start > ?",
                          (time.time() - 7 * 86400,)).fetchone()
    out = []
    for r in rows:
        out.append({"name": r["name"], "g": r["g"] or "", "start": int(r["start"]),
                    "end": int(r["end"]) if r["end"] else None, "last": int(r["last"]),
                    "returning": False, "gid": r["gid"][-4:]})
    # tamu yang pernah datang sebelumnya (id sama) = pengunjung kembali
    seen = {}
    for v in reversed(out):
        v["returning"] = v["gid"] in seen
        seen[v["gid"]] = True
    return out, {"week": total["n"], "week_unique": total["u"]}
