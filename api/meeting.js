// POST /api/meeting  (Authorization: Bearer <token founder>)  ->  {key, ice}
// Video meeting = WebRTC langsung antar founder (tanpa layanan berbayar). Sinyal lewat channel
// Supabase yang sudah ada; isi sinyal (SDP) dienkripsi AES-GCM dengan kunci rahasia yang HANYA
// diberikan ke founder yang login, jadi tamu tidak bisa ikut menyadap atau memalsukan.
// Opsional (relay TURN untuk jaringan ketat): env TURN_URLS (pisah koma), TURN_USERNAME, TURN_CREDENTIAL.
const crypto = require("crypto");
const { verify, bearer, send } = require("./_lib.js");

module.exports = async (req, res) => {
	if (req.method !== "POST") return send(res, 405, { error: "Gunakan POST" });
	try {
		const who = verify(bearer(req));
		if (!who) return send(res, 401, { error: "Sesi founder tidak sah, silakan masuk lagi" });
		const secret = (process.env.SESSION_SECRET || "").trim();
		const key = crypto.createHmac("sha256", secret).update("growhaley-rtc-v1").digest("base64");
		const ice = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }];
		const turn = (process.env.TURN_URLS || "").split(",").map((s) => s.trim()).filter(Boolean);
		if (turn.length) {
			ice.push({ urls: turn, username: process.env.TURN_USERNAME || "", credential: process.env.TURN_CREDENTIAL || "" });
		}
		return send(res, 200, { key, ice, turn: turn.length > 0 });
	} catch (e) {
		return send(res, 500, { error: String(e.message || e) });
	}
};
