// Amplop terenkripsi antara Vercel dan bot Sales Sawit di VPS (lewat Supabase Realtime publik).
// Kunci bersama: env OFFICE_LINK_SECRET (sama persis dengan di .env bot). Skema hanya pakai
// HMAC-SHA256 (tanpa library tambahan, sama di Python): keystream HMAC(kEnc, iv||ctr), tag HMAC(kMac, iv||ct).
const crypto = require("crypto");

function keys() {
	const s = (process.env.OFFICE_LINK_SECRET || "").trim();
	if (s.length < 32) throw new Error("OFFICE_LINK_SECRET belum diset di Vercel");
	const h = (label) => crypto.createHmac("sha256", s).update(label).digest();
	return { enc: h("enc"), mac: h("mac") };
}

function stream(k, iv, n) {
	const out = Buffer.alloc(n);
	for (let i = 0, c = 0; i < n; c++, i += 32) {
		const ctr = Buffer.alloc(4);
		ctr.writeUInt32BE(c);
		crypto.createHmac("sha256", k).update(Buffer.concat([iv, ctr])).digest().copy(out, i, 0, Math.min(32, n - i));
	}
	return out;
}

function seal(obj) {
	const { enc, mac } = keys();
	const iv = crypto.randomBytes(16);
	const pt = Buffer.from(JSON.stringify(obj));
	const ks = stream(enc, iv, pt.length);
	const ct = Buffer.alloc(pt.length);
	for (let i = 0; i < pt.length; i++) ct[i] = pt[i] ^ ks[i];
	const tag = crypto.createHmac("sha256", mac).update(Buffer.concat([iv, ct])).digest().subarray(0, 16);
	return Buffer.concat([iv, tag, ct]).toString("base64");
}

function open(box) {
	const { enc, mac } = keys();
	const b = Buffer.from(String(box || ""), "base64");
	if (b.length < 33) return null;
	const iv = b.subarray(0, 16), tag = b.subarray(16, 32), ct = b.subarray(32);
	const want = crypto.createHmac("sha256", mac).update(Buffer.concat([iv, ct])).digest().subarray(0, 16);
	if (!crypto.timingSafeEqual(tag, want)) return null;
	const ks = stream(enc, iv, ct.length);
	const pt = Buffer.alloc(ct.length);
	for (let i = 0; i < ct.length; i++) pt[i] = ct[i] ^ ks[i];
	try { return JSON.parse(pt.toString()); } catch (e) { return null; }
}

module.exports = { seal, open };
