// Ngobrol dengan karyawan AI di VPS:
//   bot "sales" (default) = bot Sales Sawit (~/marketing-bot/office_link.py), env SALES_FOUNDERS
//   bot "pa"              = @Onel_PA_Bot lewat userbot (~/office-pa/pa_link.py), env PA_FOUNDERS
// POST {text, bot}       (Bearer token founder) -> {id}   kirim permintaan terenkripsi ke bot
// POST {open: box, bot}  (Bearer token founder) -> {reply, note}   buka balasan terenkripsi milik founder ini
// Hanya founder di allowlist (dipisah koma, default "angga") yang boleh.
const crypto = require("crypto");
const { verify, bearer, readJson, send } = require("./_lib.js");
const { seal, open } = require("./_link.js");

const TOPIC = "growhaley-office";

const BOTS = {
	sales: { env: "SALES_FOUNDERS", event: "sales_req", label: "Sales Sawit" },
	pa: { env: "PA_FOUNDERS", event: "pa_req", label: "Onel PA" },
};

function allowedFounders(bot) {
	return (process.env[BOTS[bot].env] || "angga").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
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
		const body = await readJson(req);
		const bot = BOTS[body.bot] ? body.bot : "sales";
		if (!allowedFounders(bot).includes(String(who.k).toLowerCase())) {
			return send(res, 403, { error: BOTS[bot].label + " hanya bisa diajak ngobrol oleh pemiliknya" });
		}
		if (body.open) {
			const d = open(body.open);
			if (!d || d.to !== who.k) return send(res, 400, { error: "Balasan tidak sah" });
			return send(res, 200, { id: d.id, reply: d.reply || "", note: d.note || "", files: d.files || null, file: d.file || null });
		}
		if (bot === "pa" && body.op === "files") {
			// daftar Hasil Kerja (dijawab perantara di VPS, terenkripsi untuk founder ini)
			const id = crypto.randomBytes(8).toString("hex");
			await broadcast("pa_req", { id, box: seal({ id, bot, op: "files", from: who.k, name: who.n, ts: Date.now() }) });
			return send(res, 200, { id });
		}
		const text = String(body.text || "").trim().slice(0, bot === "pa" ? 3000 : 500);
		if (!text) return send(res, 400, { error: "Pesan kosong" });
		const id = crypto.randomBytes(8).toString("hex");
		await broadcast(BOTS[bot].event, { id, box: seal({ id, bot, from: who.k, name: who.n, text, ts: Date.now() }) });
		return send(res, 200, { id });
	} catch (e) {
		return send(res, 500, { error: String(e.message || e) });
	}
};
