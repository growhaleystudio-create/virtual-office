class_name Look
## Gaya visual retro PS1: tekstur pixel prosedural, material dengan vertex jitter,
## dan pemetaan tekstur world-space (tekstur tidak melar walau ukuran kotak beda).

const SNAP_RES := Vector2(427, 240)

static var _tex := {}
static var _mats := {}
static var _shader: Shader
## vertex jitter khas PS1 hanya untuk karakter; bangunan berlapis (lantai+karpet,
## dinding+wallpaper) jadi saling tembus/berkedip kalau ikut di-snap.
static var snap := false
static var _info := {}  # material -> [tex, scale, snap, color] (untuk batch)

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.5;
uniform vec2 snap_res = vec2(427.0, 240.0);
uniform bool snap_on = false;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (snap_on && clip.w > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_res * 0.5 + 0.5) / (snap_res * 0.5);
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 n = abs(wnorm);
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = wpos.xz;
	} else if (n.x >= n.z) {
		uv = vec2(wpos.z, -wpos.y);
	} else {
		uv = vec2(wpos.x, -wpos.y);
	}
	vec4 t = texture(tex, uv * uv_scale);
	ALBEDO = t.rgb * tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

const POST_CODE := """
shader_type canvas_item;
// warna 15-bit + dithering Bayer 4x4 seperti PS1
uniform float levels = 40.0;
// renderer web (Compatibility) lebih kontras & terang; kurva ini menyamakan dengan desktop
uniform bool compat_fix = false;
const float B[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (compat_fix) {
		c.rgb = clamp(-0.178 * c.rgb * c.rgb + 1.012 * c.rgb + 0.08, 0.0, 1.0);
	}
	ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	float d = B[(p.y % 4) * 4 + (p.x % 4)] / 16.0 - 0.5;
	c.rgb = floor(c.rgb * levels + d + 0.5) / levels;
	float v = distance(UV, vec2(0.5));
	c.rgb *= 1.0 - smoothstep(0.55, 0.85, v) * 0.35;
	COLOR = c;
}
"""


## Gabungkan semua MeshInstance3D anak langsung `node` (yang terlihat) menjadi beberapa mesh
## per tekstur; warna tiap kotak disimpan sebagai vertex color. Draw call jauh lebih sedikit.
## Node3D anak (mis. sendi lengan) diproses rekursif sendiri-sendiri supaya tetap bisa bergerak.
static func batch(node: Node3D, flatten := false) -> void:
	var groups := {}
	var victims: Array = []
	_collect(node, Transform3D.IDENTITY, flatten, groups, victims)
	if victims.size() < 2:
		return
	for key in groups:
		var g: Dictionary = groups[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		arr[Mesh.ARRAY_COLOR] = g["c"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var out := MeshInstance3D.new()
		out.mesh = am
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		node.add_child(out)
	for v in victims:
		v.get_parent().remove_child(v)
		v.free()


## `flatten` = Node3D anak ikut dilebur ke `node` (untuk benda diam); kalau tidak, tiap
## Node3D anak di-batch sendiri supaya sendi/bagian yang bergerak tetap utuh.
static func _collect(n: Node3D, xf0: Transform3D, flatten: bool, groups: Dictionary, victims: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var mat := mi.material_override
			if mi.mesh == null or mat == null or not mi.visible or mi.get_child_count() > 0:
				continue
			if mat is BaseMaterial3D and mat.albedo_texture != null:
				continue  # gambar bertekstur (logo/poster) butuh UV, jangan digabung
			if mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue  # kaca transparan dibiarkan terpisah agar urutan gambarnya benar
			var col := Color.WHITE
			var key: Array
			if _info.has(mat):
				var inf: Array = _info[mat]
				key = [inf[0], inf[1], inf[2], mi.cast_shadow]
				col = inf[3]
			else:
				key = [mat, mi.cast_shadow]
			if not groups.has(key):
				var gm := mat
				if _info.has(mat):
					var prev := snap
					snap = key[2]
					gm = Look.mat(Color.WHITE, key[0], key[1])
					snap = prev
				groups[key] = {"mat": gm, "shadow": mi.cast_shadow, "v": PackedVector3Array(),
					"n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
			var g: Dictionary = groups[key]
			var xf := xf0 * mi.transform
			var nb := xf.basis.inverse().transposed()
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms = arr[Mesh.ARRAY_NORMAL]
				var base: int = g["v"].size()
				for i in verts.size():
					g["v"].append(xf * verts[i])
					g["n"].append((nb * (norms[i] if norms != null else Vector3.UP)).normalized())
					g["c"].append(col)
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx == null:
					for i in verts.size():
						g["i"].append(base + i)
				else:
					for i in idx:
						g["i"].append(base + i)
			victims.append(mi)
		elif c is Node3D and c.get_class() == "Node3D" and not c.has_meta("no_batch"):
			if flatten:
				_collect(c, xf0 * c.transform, true, groups, victims)
			else:
				batch(c)


static func post_material() -> ShaderMaterial:
	var s := Shader.new()
	s.code = POST_CODE
	var m := ShaderMaterial.new()
	m.shader = s
	return m


static func mat(color: Color, tex_name := "grain", scale := 0.5) -> Material:
	var key := [color, tex_name, scale, snap]
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if color.a < 1.0:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = color
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.roughness = 0.2
		m = sm
	else:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER_CODE
		var shm := ShaderMaterial.new()
		shm.shader = _shader
		shm.set_shader_parameter("tex", tex(tex_name))
		shm.set_shader_parameter("tint", color)
		shm.set_shader_parameter("uv_scale", scale)
		shm.set_shader_parameter("snap_res", SNAP_RES)
		shm.set_shader_parameter("snap_on", snap)
		m = shm
		_info[m] = [tex_name, scale, snap, color]
	_mats[key] = m
	return m


static func tex(tex_name: String) -> Texture2D:
	if not _tex.has(tex_name):
		var img: Image
		match tex_name:
			"planks": img = _gen_planks()
			"tiles": img = _gen_tiles()
			"stone": img = _gen_stone()
			"carpet": img = _gen_carpet()
			"wallpaper": img = _gen_wallpaper()
			"brick": img = _gen_brick()
			"cloth": img = _gen_cloth()
			"metal": img = _gen_metal()
			"grass": img = _gen_grass()
			"dirt": img = _gen_dirt()
			"leaves": img = _gen_leaves()
			_: img = _gen_grain()
		img.generate_mipmaps()
		_tex[tex_name] = ImageTexture.create_from_image(img)
	return _tex[tex_name]


# ---------- generator tekstur (32x32) ----------

static func _new_img() -> Image:
	return Image.create(32, 32, false, Image.FORMAT_RGBA8)


static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


static func _grey(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	return Color(v, v, v)


static func _gen_grain() -> Image:
	var img := _new_img()
	var r := _rng(1)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, _grey(0.9 + r.randf() * 0.1))
	return img


static func _gen_planks() -> Image:
	var img := _new_img()
	var r := _rng(2)
	for row in 4:
		var base := 0.78 + r.randf() * 0.2
		var seam := (row * 13 + 5) % 32
		var ph := r.randf() * 6.0
		for y in range(row * 8, row * 8 + 8):
			for x in 32:
				var v := base * (0.92 + 0.08 * sin(x * 0.55 + ph + (y % 8) * 0.9))
				v *= 0.95 + r.randf() * 0.05
				if y % 8 == 7:
					v = 0.5
				elif x == seam:
					v *= 0.65
				img.set_pixel(x, y, _grey(v))
	return img


static func _gen_tiles() -> Image:
	var img := _new_img()
	var r := _rng(3)
	for y in 32:
		for x in 32:
			var v := 1.0 if ((x / 16) + (y / 16)) % 2 == 0 else 0.86
			v *= 0.95 + r.randf() * 0.05
			if x % 16 == 0 or y % 16 == 0:
				v = 0.68
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_stone() -> Image:
	var img := _new_img()
	var r := _rng(4)
	var shade := []
	for i in 4:
		shade.append(0.82 + r.randf() * 0.18)
	for y in 32:
		for x in 32:
			var ox := 8 if (y / 16) % 2 == 1 else 0
			var idx := (((x + ox) / 16) % 2) + (y / 16) * 2
			var v: float = shade[idx % 4] * (0.9 + r.randf() * 0.1)
			if (x + ox) % 16 == 0 or y % 16 == 0:
				v = 0.6
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_carpet() -> Image:
	var img := _new_img()
	var r := _rng(5)
	for y in 32:
		for x in 32:
			var v := 0.82 + r.randf() * 0.18
			if r.randf() < 0.05:
				v = 0.7
			if (x + y) % 8 == 0:
				v *= 0.95
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_wallpaper() -> Image:
	var img := _new_img()
	var r := _rng(6)
	for y in 32:
		for x in 32:
			var v := 1.0 if x % 8 < 5 else 0.93
			if x % 8 == 2 and y % 8 == 3:
				v = 0.85
			v *= 0.97 + r.randf() * 0.03
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_brick() -> Image:
	var img := _new_img()
	var r := _rng(7)
	for y in 32:
		for x in 32:
			var ox := 8 if (y / 8) % 2 == 1 else 0
			var v := 0.72 + r.randf() * 0.12
			if y % 8 == 0 or (x + ox) % 16 == 0:
				v = 1.0
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_cloth() -> Image:
	var img := _new_img()
	var r := _rng(8)
	for y in 32:
		for x in 32:
			var v := 0.95 if (x + y) % 2 == 0 else 0.88
			v *= 0.96 + r.randf() * 0.04
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_metal() -> Image:
	var img := _new_img()
	var r := _rng(9)
	for y in 32:
		var row := 0.85 + r.randf() * 0.15
		for x in 32:
			var v := row * (0.97 + r.randf() * 0.03)
			if y % 16 == 0:
				v = 0.6
			img.set_pixel(x, y, _grey(v))
	return img


static func _gen_grass() -> Image:
	var img := _new_img()
	var r := _rng(10)
	for y in 32:
		for x in 32:
			var g := 0.55 + r.randf() * 0.12
			img.set_pixel(x, y, Color(0.30 + r.randf() * 0.06, g, 0.20))
	for i in 70:
		var x := r.randi_range(0, 31)
		var y := r.randi_range(0, 29)
		var c := Color(0.22, 0.45, 0.16) if r.randf() < 0.6 else Color(0.48, 0.70, 0.28)
		for k in 3:
			img.set_pixel(x, y + k, c)
	for i in 4:
		img.set_pixel(r.randi_range(0, 31), r.randi_range(0, 31), Color(0.95, 0.9, 0.4))
	return img


static func _gen_dirt() -> Image:
	var img := _new_img()
	var r := _rng(11)
	for y in 32:
		for x in 32:
			var v := 0.85 + r.randf() * 0.15
			img.set_pixel(x, y, Color(0.66 * v, 0.52 * v, 0.36 * v))
	for i in 25:
		img.set_pixel(r.randi_range(0, 31), r.randi_range(0, 31), Color(0.78, 0.72, 0.62))
	return img


static func _gen_leaves() -> Image:
	var img := _new_img()
	var r := _rng(12)
	for y in 32:
		for x in 32:
			var v := 0.75 + r.randf() * 0.25
			if r.randf() < 0.12:
				v = 0.55
			img.set_pixel(x, y, _grey(v))
	return img
