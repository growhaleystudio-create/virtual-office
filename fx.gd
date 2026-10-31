class_name Fx
## Efek komik: pecut besar bergaya 3D (digambar prosedural dengan pencahayaan) dan balon "CETAS!".

## Pecut besar: ukuran gambar, ujung (titik klik) dan pegangan (poros ayunan).
const WHIP_SIZE := 128
const WHIP_TIP := Vector2(118, 12)
const WHIP_GRIP := Vector2(22, 104)
const _SS := 3  # supersampling agar tepi halus

static var _whips := {}


## Gambar pecut besar yang halus. Disimpan di user:// supaya hanya dibuat sekali.
static func whip_texture(crack := false) -> Texture2D:
	if _whips.has(crack):
		return _whips[crack]
	var path := "user://whip_%s_v3.png" % ("crack" if crack else "idle")
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		img = _render_whip(crack)
		img.save_png(path)
	var tex := ImageTexture.create_from_image(img)
	_whips[crack] = tex
	return tex


static func _render_whip(crack: bool) -> Image:
	var n := WHIP_SIZE * _SS
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var s := float(_SS)
	# tali: kurva bezier kubik dari pangkal gagang ke ujung
	var a := Vector2(44, 80) * s
	var b := (Vector2(92, 98) if not crack else Vector2(70, 58)) * s
	var c := (Vector2(78, 30) if not crack else Vector2(96, 32)) * s
	var d := WHIP_TIP * s
	var lash: Array = []  # [posisi, jari-jari, arah sumbu]
	var steps := 200
	var prev := a
	for i in steps + 1:
		var t := i / float(steps)
		var p := a.lerp(b, t).lerp(b.lerp(c, t), t).lerp(b.lerp(c, t).lerp(c.lerp(d, t), t), t)
		var dir := (p - prev).normalized() if i > 0 else (b - a).normalized()
		lash.append([p, lerpf(4.6, 1.5, t) * s, dir])
		prev = p
	var h0 := Vector2(10, 116) * s
	var h1 := Vector2(46, 78) * s
	var hdir := (h1 - h0).normalized()
	var handle: Array = []
	for i in 61:
		handle.append([h0.lerp(h1, i / 60.0), 6.4 * s, hdir])

	var shadow := Color(0, 0, 0, 0.28)
	var off := Vector2(4, 5) * s
	var ink := Color(0.10, 0.05, 0.03)
	var gold := Color(0.97, 0.78, 0.28)
	# 1. bayangan jatuh, 2. garis tepi, 3. tabung berbayang
	for seg in [lash, handle]:
		for q in seg:
			_disk(img, q[0] + off, q[1] + 1.5 * s, shadow, true)
	for seg in [lash, handle]:
		for q in seg:
			_disk(img, q[0], q[1] + 1.4 * s, ink)
	for q in lash:
		_tube(img, q[0], q[1], Color(0.66, 0.38, 0.19), q[2], 0.22, 4.0 * s)
	for q in handle:
		_tube(img, q[0], q[1], Color(0.32, 0.16, 0.08), q[2], 0.16, 3.0 * s, true)
	# cincin emas (pita silinder) + bola ujung gagang
	for k in [0.12, 0.55, 0.96]:
		var p: Vector2 = h0.lerp(h1, k)
		_tube(img, p, 7.9 * s, ink, hdir, 0.0, 1.0, false, 3.4 * s, true)
		_tube(img, p, 7.0 * s, gold, hdir, 0.0, 1.0, false, 2.4 * s)
	_disk(img, h0, 8.4 * s, ink)
	_tube(img, h0, 7.2 * s, gold, Vector2.ZERO, 0.0, 1.0)
	# jumbai merah di ujung
	_disk(img, d, 4.4 * s, ink)
	_tube(img, d, 3.3 * s, Color(0.90, 0.18, 0.14), Vector2.ZERO, 0.0, 1.0)
	if crack:
		var spark := Color(1.0, 0.92, 0.35)
		for ang in [0.2, 1.1, 2.0, 2.9, 3.8, 4.7, 5.6]:
			var dir := Vector2(cos(ang), sin(ang))
			for j in 12:
				_disk(img, d + dir * (7.5 + j * 0.6) * s, 1.3 * s, ink)
			for j in 12:
				_disk(img, d + dir * (7.5 + j * 0.6) * s, 0.8 * s, spark)
	img.resize(WHIP_SIZE, WHIP_SIZE, Image.INTERPOLATE_CUBIC)
	return img


static func _disk(img: Image, c: Vector2, r: float, col: Color, blend := false) -> void:
	var w := img.get_width()
	for y in range(maxi(0, floori(c.y - r)), mini(w, ceili(c.y + r) + 1)):
		for x in range(maxi(0, floori(c.x - r)), mini(w, ceili(c.x + r) + 1)):
			if (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= r * r:
				if blend:
					if img.get_pixel(x, y).a < col.a:
						img.set_pixel(x, y, col)
				else:
					img.set_pixel(x, y, col)


## Disk berbayang seperti penampang silinder sepanjang `axis` (cahaya dari kiri atas);
## axis = ZERO berarti bola. `braid` = kekuatan pola kepang kulit, `period` = jaraknya.
## `rings` = pola melingkar (lilitan gagang) alih-alih kepang miring.
static func _tube(img: Image, c: Vector2, r: float, base: Color, axis: Vector2, braid: float, period: float, rings := false, half_len := 0.0, flat := false) -> void:
	var w := img.get_width()
	var l := Vector3(-0.45, -0.6, 0.66).normalized()
	var perp := Vector2(-axis.y, axis.x)
	for y in range(maxi(0, floori(c.y - r)), mini(w, ceili(c.y + r) + 1)):
		for x in range(maxi(0, floori(c.x - r)), mini(w, ceili(c.x + r) + 1)):
			var o := Vector2(x - c.x, y - c.y) / r
			if half_len > 0.0:
				# pita: potongan silinder sepanjang 2*half_len
				if absf(o.dot(perp)) > 1.0 or absf(o.dot(axis)) * r > half_len:
					continue
				if flat:
					img.set_pixel(x, y, base)
					continue
			elif o.length_squared() > 1.0:
				continue
			var nrm: Vector3
			var u := 0.0
			if axis == Vector2.ZERO:
				nrm = Vector3(o.x, o.y, sqrt(1.0 - o.length_squared()))
			else:
				u = clampf(o.dot(perp), -1.0, 1.0)
				nrm = Vector3(perp.x * u, perp.y * u, sqrt(1.0 - u * u))
			var diff := maxf(0.0, nrm.dot(l))
			var spec := pow(diff, 30.0) * 0.75
			var along := Vector2(x, y).dot(axis) * TAU / period
			var pat := sin(along) if rings else sin(along + u * 2.6) * sin(along * 0.5 - u * 2.6)
			var col := base * (0.30 + 0.88 * diff) * (1.0 - braid * (0.5 - 0.5 * pat))
			col = col.lerp(Color(1, 0.97, 0.9), spec)
			col.a = 1.0
			img.set_pixel(x, y, col)


## Balon komik bergerigi dengan teks, muncul membesar lalu memudar sambil naik.
static func comic_burst(parent: Control, at: Vector2, text := "CETAS!") -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = at
	parent.add_child(root)
	# bentuk ledakan: titik bergantian jauh-dekat dengan sedikit acak
	var pts := PackedVector2Array()
	var n := 14
	for i in n * 2:
		var a := TAU * i / (n * 2)
		var r := (78.0 if i % 2 == 0 else 52.0) * randf_range(0.88, 1.12)
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.62))
	var shadow := pts.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(5, 6)
	var outline := pts.duplicate()
	outline.append(pts[0])
	root.draw.connect(func() -> void:
		root.draw_colored_polygon(shadow, Color(0.15, 0.08, 0.05, 0.55))
		root.draw_colored_polygon(pts, Color(1.0, 0.96, 0.55))
		root.draw_polyline(outline, Color(0.15, 0.08, 0.05), 3.0)
		# garis aksi di sekeliling
		for i in 10:
			var a := TAU * i / 10.0 + 0.3
			var d := Vector2(cos(a), sin(a) * 0.62)
			root.draw_line(d * 92.0, d * 112.0, Color(0.15, 0.08, 0.05), 3.0))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.18, 0.12))
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(160, 50)
	lbl.position = Vector2(-80, -25)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)

	root.scale = Vector2.ONE * 0.15
	root.rotation = randf_range(-0.22, 0.22)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2.ONE * 1.12, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.08)
	tw.tween_interval(0.45)
	tw.tween_property(root, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(root, "position:y", at.y - 30.0, 0.3)
	tw.tween_callback(root.queue_free)