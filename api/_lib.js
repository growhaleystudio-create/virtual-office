// Helper bersama untuk fungsi /api (Vercel). File berawalan "_" tidak jadi endpoint.
const crypto = require("crypto");
const ACCOUNTS = require("./_accounts.js");

const SESSION_DAYS = 30;

function secret() {
	const s = (process.env.SESSION_SECRET || "").trim();
	if (!s || s.length < 16) throw new Error("SESSION_SECRET belum diset di Vercel");
	return s;
}

function b64url(buf) {
	return Buffer.from(buf).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function sign(payload) {
	const body = b64url(JSON.stringify(payload));
	const mac = b64url(crypto.createHmac("sha256", secret()).update(body).digest());
	return body + "." + mac;
}

// Kembalikan payload bila token sah & belum kedaluwarsa, selain itu null.
function verify(token) {
	if (typeof token !== "string" || !token.includes(".")) return null;
	const [body, mac] = token.split(".");
	const want = b64url(crypto.createHmac("sha256", secret()).update(body).digest());
	const a = Buffer.from(mac);
	const b = Buffer.from(want);
	if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
	let p;
	try {
		p = JSON.parse(Buffer.from(body.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString());
	} catch (e) {
		return null;
	}
	if (!p.exp || p.exp < Date.now() / 1000) return null;
	return p;
}

function checkPassword(email, password) {
	const acc = ACCOUNTS[String(email || "").trim().toLowerCase()];
	if (!acc || typeof password !== "string") return null;
	const [, salt, hash] = acc.hash.split("$");
	const got = crypto.scryptSync(password, salt, 32, { N: 16384, r: 8, p: 1 });
	const want = Buffer.from(hash, "hex");
	return crypto.timingSafeEqual(got, want) ? acc : null;
}

function newSession(acc) {
	const exp = Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400;
	return { token: sign({ k: acc.key, n: acc.name, exp }), key: acc.key, name: acc.name, exp };
}

function bearer(req) {
	const h = req.headers["authorization"] || "";
	return h.startsWith("Bearer ") ? h.slice(7) : "";
}

async function readJson(req) {
	if (req.body && typeof req.body === "object") return req.body;
	if (typeof req.body === "string") return JSON.parse(req.body || "{}");
	const chunks = [];
	for await (const c of req) chunks.push(c);
	return JSON.parse(Buffer.concat(chunks).toString() || "{}");
}

function send(res, code, obj) {
	res.statusCode = code;
	res.setHeader("Content-Type", "application/json");
	res.setHeader("Cache-Control", "no-store");
	res.end(JSON.stringify(obj));
}

module.exports = { sign, verify, checkPassword, newSession, bearer, readJson, send };
