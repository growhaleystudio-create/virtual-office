// Ngobrol dengan karyawan AI "Sales" = bot Sales Sawit di VPS.
// POST {text}        (Bearer token founder) -> {id}   kirim permintaan terenkripsi ke bot
// POST {open: box}   (Bearer token founder) -> {reply, note}   buka balasan terenkripsi milik founder ini
// Hanya founder di env SALES_FOUNDERS (dipisah koma, default "luthfi") yang boleh.
const crypto = require("crypto");
const { verify, bearer, readJson, send } = require("./_lib.js");
const { seal, open } = require("./_link.js");

const TOPIC = "growhaley-office";

function allowedFounders() {
	return (process.env.SALES_FOUNDERS || "luthfi").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
}

async function broadcast(event, payload) {
	const url = (process.env.SUPABASE_URL || "").trim();
	const key = (process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || "").trim();
	if (!url || !key) throw new Error("SUPABASE_URL / key belum diset di Vercel");
	const r = await fetch(url + "/realtime/v1/api/broadcast", {
		method: "POST",
		headers: { apikey: key, "Content-Type": "application/json" },
		body: JSON.stringify({ messages: [{ topic: TOPIC, event, payload }] }),
	});
	if (!r.ok) throw new Error("Supabase broadcast gagal (" + r.status + ")");
}

module.exports = async (req, res) => {
	if (req.method !== "POST") return send(res, 405, { error: "Gunakan POST" });
	try {
		const who = verify(bearer(req));
		if (!who) return send(res, 401, { error: "Sesi founder tidak sah, silakan masuk lagi" });
		if (!allowedFounders().includes(String(who.k).toLowerCase())) {
			return send(res, 403, { error: "Sales Sawit hanya bisa diajak ngobrol oleh pemiliknya" });
		}
		const body = await readJson(req);
		if (body.open) {
			const d = open(body.open);
			if (!d || d.to !== who.k) return send(res, 400, { error: "Balasan tidak sah" });
			return send(res, 200, { id: d.id, reply: d.reply || "", note: d.note || "" });
		}
		const text = String(body.text || "").trim().slice(0, 500);
		if (!text) return send(res, 400, { error: "Pesan kosong" });
		const id = crypto.randomBytes(8).toString("hex");
		await broadcast("sales_req", { id, box: seal({ id, from: who.k, name: who.n, text, ts: Date.now() }) });
		return send(res, 200, { id });
	} catch (e) {
		return send(res, 500, { error: String(e.message || e) });
	}
};
