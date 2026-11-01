// POST /api/meeting  (Authorization: Bearer <token founder>)  ->  {url}
// Membuat tiket (meeting token) Daily untuk room privat "meeting". Hanya founder yang login.
// Room dibuat otomatis (privat) bila belum ada. Butuh env DAILY_API_KEY & DAILY_DOMAIN.
const { verify, bearer, send } = require("./_lib.js");

const ROOM = "meeting";
const API = "https://api.daily.co/v1";

async function daily(path, method, body) {
	const r = await fetch(API + path, {
		method,
		headers: { Authorization: "Bearer " + process.env.DAILY_API_KEY, "Content-Type": "application/json" },
		body: body ? JSON.stringify(body) : undefined,
	});
	const data = await r.json().catch(() => ({}));
	return { ok: r.ok, status: r.status, data };
}

module.exports = async (req, res) => {
	if (req.method !== "POST") return send(res, 405, { error: "Gunakan POST" });
	try {
		const who = verify(bearer(req));
		if (!who) return send(res, 401, { error: "Sesi founder tidak sah, silakan masuk lagi" });
		if (!process.env.DAILY_API_KEY) return send(res, 500, { error: "DAILY_API_KEY belum diset di Vercel" });
		const domain = process.env.DAILY_DOMAIN || "virtualofficewhaley";

		const room = await daily("/rooms/" + ROOM, "GET");
		if (room.status === 404) {
			const made = await daily("/rooms", "POST", { name: ROOM, privacy: "private" });
			if (!made.ok) return send(res, 502, { error: "Gagal membuat room Daily", detail: made.data });
		} else if (!room.ok) {
			return send(res, 502, { error: "Gagal cek room Daily", detail: room.data });
		}

		const exp = Math.floor(Date.now() / 1000) + 4 * 3600;
		const tok = await daily("/meeting-tokens", "POST", {
			properties: { room_name: ROOM, user_name: who.n, exp, eject_at_token_exp: true },
		});
		if (!tok.ok) return send(res, 502, { error: "Gagal membuat tiket meeting", detail: tok.data });
		return send(res, 200, { url: `https://${domain}.daily.co/${ROOM}?t=${tok.data.token}` });
	} catch (e) {
		return send(res, 500, { error: String(e.message || e) });
	}
};
