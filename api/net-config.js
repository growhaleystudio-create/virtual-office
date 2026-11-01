// GET /api/net-config -> alamat & kunci publik Supabase untuk multiplayer realtime.
// Kunci "anon/publishable" memang boleh tampil di browser. Diisi di Vercel:
// SUPABASE_URL (https://xxxx.supabase.co) dan SUPABASE_ANON_KEY.
module.exports = (req, res) => {
	const url = (process.env.SUPABASE_URL || "").trim();
	const key = (process.env.SUPABASE_ANON_KEY || "").trim();
	res.setHeader("Content-Type", "application/json");
	res.setHeader("Cache-Control", "no-store");
	res.end(JSON.stringify(url && key ? { url, key } : {}));
};
