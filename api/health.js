// GET /api/health -> diagnosa konfigurasi (TANPA membuka nilai rahasia).
module.exports = (req, res) => {
	const env = process.env;
	const info = (k) => (env[k] ? { set: true, length: env[k].trim().length } : { set: false });
	const similar = Object.keys(env).filter((k) => /SESSION|DAILY|SECRET|SUPABASE/i.test(k));
	res.setHeader("Content-Type", "application/json");
	res.setHeader("Cache-Control", "no-store");
	res.end(JSON.stringify({
		SESSION_SECRET: info("SESSION_SECRET"),
		DAILY_API_KEY: info("DAILY_API_KEY"),
		SUPABASE_URL: info("SUPABASE_URL"),
		SUPABASE_ANON_KEY: info("SUPABASE_ANON_KEY"),
		similar_names: similar,
		vercel_env: env.VERCEL_ENV || null,
		commit: (env.VERCEL_GIT_COMMIT_SHA || "").slice(0, 7) || null,
		deployment_url: env.VERCEL_URL || null,
	}, null, 2));
};
