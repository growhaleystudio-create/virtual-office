// POST /api/login  {email, password}  ->  {token, key, name, exp}
const { checkPassword, newSession, readJson, send } = require("./_lib.js");

module.exports = async (req, res) => {
	if (req.method !== "POST") return send(res, 405, { error: "Gunakan POST" });
	try {
		const { email, password } = await readJson(req);
		const acc = checkPassword(email, password);
		if (!acc) {
			await new Promise((r) => setTimeout(r, 600)); // perlambat tebak-tebakan password
			return send(res, 401, { error: "Email atau password salah" });
		}
		return send(res, 200, newSession(acc));
	} catch (e) {
		return send(res, 500, { error: String(e.message || e) });
	}
};
