extends Node3D
## Kantor virtual 2 lantai bergaya retro PS1: bangunan, karakter, kamera, UI, perintah.

const W := 44
const H := 30
const FH := Agent.FLOOR_H
const NONE := Vector2i(-1, -1)
const WALL_T := 0.25

# tangga: 2 lajur (z 4..5), naik dari x=28 (lantai 1) ke x=34 (lantai 2)
const STAIR_X0 := 28
const STAIR_X1 := 34
const STAIR_Z := 4
const STAIR2_Z := 9  # tangga lantai 2 -> 3 (hanya visual, ke lantai founder)
const LANDING := [Vector2i(27, 4), Vector2i(34, 4)]

# urutan penting: frasa yang lebih spesifik dicek dulu
const PLACE_WORDS := [
	["rapat_atas", ["rapat atas", "meeting atas", "rapat lantai 2", "rapat kecil"]],
	["bos", ["ruangku", "ruang saya", "ruang aku", "ruang bos", "ruang kamu", "lapor", "menghadap", "ke aku", "ke saya", "temui aku"]],
	["teras", ["teras", "taman", "kebun", "rooftop", "atap"]],
	["perpus", ["perpus", "buku", "library", "baca"]],
	["pantry", ["pantry", "kopi", "dapur", "makan", "coffee"]],
	["meeting", ["meeting", "rapat", "kumpul"]],
	["lounge", ["lounge", "santai", "istirahat", "sofa"]],
	["lobby", ["lobby", "lobi", "resepsionis", "resepsi"]],
	["server", ["server", "ruang it"]],
	["desk", ["meja", "desk", "kerja", "kembali", "work"]],
]
const PLACE_STATUS := {
	"pantry": "ngopi di pantry",
	"meeting": "rapat",
	"lounge": "istirahat di lounge",
	"lobby": "di lobby",
	"server": "cek server",
	"teras": "santai di teras",
	"perpus": "baca buku",
	"rapat_atas": "rapat (lantai 2)",
	"bos": "lapor ke kamu",
}
const WANDER := ["pantry", "lounge", "meeting", "lobby", "server", "teras", "perpus", "pantry", "teras"]
const WORK_TASKS := ["menulis laporan", "cek email", "follow up lead", "analisa data", "bekerja"]
const AGENTS := [
	["Sales", Color(0.86, 0.32, 0.26), Color(0.25, 0.15, 0.08), "Sales Executive"],
	["Marketing", Color(0.25, 0.52, 0.86), Color(0.55, 0.30, 0.12), "Marketing Specialist"],
	["Admin", Color(0.35, 0.70, 0.38), Color(0.12, 0.10, 0.10), "Staf Administrasi"],
	["Support", Color(0.95, 0.72, 0.22), Color(0.70, 0.45, 0.20), "Customer Support"],
	["Finance", Color(0.62, 0.40, 0.80), Color(0.20, 0.12, 0.08), "Staf Keuangan"],
	["Developer", Color(0.22, 0.66, 0.66), Color(0.40, 0.22, 0.10), "Software Developer"],
]
const SIDE_N := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0), "E": Vector3(1, 0, 0)}
const WOOD := Color(0.78, 0.58, 0.38)
const DARK_WOOD := Color(0.42, 0.28, 0.18)
const CREAM := Color(0.95, 0.955, 0.96)
# palet Growhaley (diambil dari growhaley.com)
const BRAND_BLUE := Color(0.09, 0.49, 0.71)  # #177DB5
const BRAND_LIGHT := Color(0.62, 0.79, 0.88)  # #9DC9E1
const BRAND_PALE := Color(0.88, 0.93, 0.97)  # #E0EEF7
const BRAND_INK := Color(0.14, 0.14, 0.15)  # #232326
const BRAND_PINK := Color(0.85, 0.27, 0.50)  # #DA457F
const NFLOORS := 3
const FOUNDERS := [
	["Alvin", "SEO & Growth Strategist", "alvin", Color(0.09, 0.49, 0.71)],
	["Dianita", "Social & Creative Strategist", "dianita", Color(0.85, 0.27, 0.50)],
	["Intan", "Lead UI/UX Designer", "intan", Color(0.52, 0.42, 0.80)],
	["Ahay", "Brand & Visual Designer", "ahay", Color(0.93, 0.58, 0.22)],
	["Angga", "Web Developer", "angga", Color(0.13, 0.60, 0.60)],
	["Luthfi", "AI Experience Designer", "luthfi", Color(0.20, 0.30, 0.55)],
]

var grids: Array[AStarGrid2D] = []
var floors: Array[Node3D] = []
var ext_walls: Array = []  # per lantai: {side: Node3D}
var agents: Array[Agent] = []
var selected: Agent = null
var desk_spots: Array = []
var places := {}
var rng := RandomNumberGenerator.new()

# konteks pembangunan
var cur: Node3D
var g: AStarGrid2D
var cf := 0

# render & kamera
var svp: SubViewport
var pivot: Node3D
var cam: Camera3D
var yaw := 0.6
var pitch := -0.85
var zoom := 34.0
var t_yaw := 0.6
var t_pitch := -0.85
var t_zoom := 34.0
var t_pivot := Vector3.ZERO
var view_floor := 0
var _ldown := false
var _drag := 0.0

# UI
var ui: Control
var overlay: Control
var cmd_input: LineEdit
var feedback: Label
var bridge_label: Label
var floor_btns: Array[Button] = []
var world_labels: Array = []  # {label, pos, floor}
var roster_buttons := {}
var rooms := []  # {name, x, z, floor} untuk menampilkan posisi karakter
var follow: Agent = null  # karakter yang sedang diikuti kamera
var roster_toggle: Button
var town  # lingkungan kota (town.gd)
var roster_rows: VBoxContainer
var _status_timer := 0.0
var bridge: Bridge


func _ready() -> void:
	rng.seed = 7
	_build_render()
	_build_env()
	_build_world()
	_build_agents()
	_build_ui()
	_build_whip_cursor()
	_build_bridge()
	set_view_floor(0)
	rng.randomize()
	_apply_pixel_mode()
	_setup_web_bridge()
	_maybe_screenshot()


# ---------- koordinat ----------

func _cw(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5 - W / 2.0, 0, c.y + 0.5 - H / 2.0)


func cell_to_world(c: Vector2i, f := 0) -> Vector3:
	return _cw(c) + Vector3(0, f * FH, 0)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(p.x + W / 2.0), 0, W - 1), clampi(floori(p.z + H / 2.0), 0, H - 1))


func nearest_free(c: Vector2i, f: int) -> Vector2i:
	var gr := grids[f]
	if not gr.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var n := Vector2i(c.x + dx, c.y + dz)
				if gr.is_in_boundsv(n) and not gr.is_point_solid(n):
					return n
	return c


func _rect_center(x: float, z: float, w: float, h: float) -> Vector3:
	return Vector3(x + w / 2.0 - W / 2.0, 0, z + h / 2.0 - H / 2.0)


func _solid(x: int, z: int, w := 1, h := 1) -> void:
	for i in range(x, x + w):
		for j in range(z, z + h):
			g.set_point_solid(Vector2i(i, j), true)


func _box(pos: Vector3, size: Vector3, color: Color, tex := "grain", scale := 0.5) -> MeshInstance3D:
	return Agent.make_box(cur, pos, size, color, tex, scale)


func _cyl(pos: Vector3, r: float, h: float, color: Color, tex := "grain", segs := 12) -> MeshInstance3D:
	return Agent.make_cyl(cur, pos, r, h, color, tex, segs)


# ---------- render retro ----------

func _build_render() -> void:
	svp = SubViewport.new()
	svp.size = _svp_size()
	svp.world_3d = get_world_3d()
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)
	pivot = Node3D.new()
	svp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 45
	cam.far = 300.0
	cam.current = true
	pivot.add_child(cam)

	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var screen := TextureRect.new()
	_screen = screen
	screen.texture = svp.get_texture()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.material = Look.post_material()
	screen.material.set_shader_parameter("compat_fix", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	layer.add_child(screen)
	# web: default HD (layar browser besar); desktop: retro sedang
	# HP (web_android / web_ios): Sedang, karena GPU HP lebih lemah
	_pix_i = 2 if OS.has_feature("web") and not (OS.has_feature("web_android") or OS.has_feature("web_ios")) else 1
	get_window().size_changed.connect(_on_window_resized)


## Resolusi gambar 3D (jumlah baris piksel). Makin kecil = makin retro/kotak-kotak.
## 0 = HD: resolusi penuh layar, tepi halus (MSAA), tanpa dithering.
const PIXEL_LINES := [240, 360, 0]
const PIXEL_NAMES := ["Retro", "Sedang", "HD"]
var _pix_i := 1
var _screen: TextureRect


func _svp_size() -> Vector2i:
	var lines: int = PIXEL_LINES[_pix_i]
	if lines == 0:
		# area kanvas 1280x720 dalam piksel jendela sebenarnya (stretch "keep")
		var ws := Vector2(get_window().size)
		var k := minf(ws.x / 1280.0, ws.y / 720.0)
		return Vector2i(maxi(64, roundi(1280.0 * k)), maxi(36, roundi(720.0 * k)))
	return Vector2i(roundi(lines * 16.0 / 9.0), lines)


func _apply_pixel_mode() -> void:
	var hd: bool = PIXEL_LINES[_pix_i] == 0
	svp.size = _svp_size()
	svp.msaa_3d = Viewport.MSAA_2X if hd else Viewport.MSAA_DISABLED
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if hd else CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.material.set_shader_parameter("retro", not hd)
	Look.set_snap_res(Vector2(svp.size) if not hd else Vector2(1280, 720))


func _on_window_resized() -> void:
	if PIXEL_LINES[_pix_i] == 0:
		svp.size = _svp_size()


func cycle_pixel_detail() -> void:
	_pix_i = (_pix_i + 1) % PIXEL_LINES.size()
	_apply_pixel_mode()
	show_feedback("Tampilan: %s" % PIXEL_NAMES[_pix_i])


## Posisi layar (kanvas 1280x720) -> piksel di SubViewport 3D.
func _to_svp(p: Vector2) -> Vector2:
	return p * Vector2(svp.size) / Vector2(1280.0, 720.0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.80, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.95)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.82, 0.95)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	# renderer web (WebGL / Compatibility) menghitung cahaya lebih terang & kontras;
	# turunkan supaya tampilannya sama dengan versi desktop
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var sun_e := 1.15
	if compat:
		sun_e = 0.8
		env.ambient_light_energy = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = sun_e
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.75
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 1.5
	add_child(sun)


func _lamp(cell: Vector2i, color: Color, energy := 1.0, rng_m := 10.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.position = _cw(cell) + Vector3(0, 2.6, 0)
	cur.add_child(l)


func _room_label(text: String, x: float, z: float, small := false, sub := "") -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13 if small else 16)
	l.add_theme_color_override("font_color", Color(1, 0.96, 0.85) if not small else Color(1, 0.9, 0.5))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.15, 0.08))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_labels.append({"label": l, "pos": Vector3(x - W / 2.0, cf * FH + 2.9, z - H / 2.0), "floor": cf,
		"small": small, "sub": sub, "name": text.capitalize() if not small else text.trim_prefix("★ ").capitalize()})
	if not small:
		rooms.append({"name": text.capitalize(), "x": x - W / 2.0, "z": z - H / 2.0, "floor": cf})


# ---------- dinding ----------

func _in_gaps(v: int, gaps: Array) -> bool:
	for gp in gaps:
		if v >= gp[0] and v <= gp[1]:
			return true
	return false


## Dinding dalam dicatat dulu, dibangun di _flush_walls() setelah semua lantai selesai,
## supaya ujung yang menempel ke dinding lain bisa diperpanjang sampai bertemu.
var _wall_segs := []
var _wall_cells := [{}, {}, {}]
var _deco_segs := []  # salinan segmen dinding untuk ornamen
var _windows := {}  # "lantai:sisi" -> [[posisi, lebar]]


func _queue_wall(x: int, z: int, length: int, horiz: bool, glass: bool) -> void:
	_wall_segs.append([cf, x, z, length, horiz, glass])
	for i in length:
		_wall_cells[cf][Vector2i(x + i, z) if horiz else Vector2i(x, z + i)] = true


func _flush_walls() -> void:
	_deco_segs = _wall_segs.duplicate()
	for s in _wall_segs:
		var f: int = s[0]
		var x: int = s[1]
		var z: int = s[2]
		var n: int = s[3]
		var horiz: bool = s[4]
		var before := Vector2i(x - 1, z) if horiz else Vector2i(x, z - 1)
		var after := Vector2i(x + n, z) if horiz else Vector2i(x, z + n)
		var ea := 0.5 if _wall_cells[f].has(before) else 0.0
		var eb := 0.5 if _wall_cells[f].has(after) else 0.0
		cur = floors[f]
		_wall_box(x, z, n, horiz, s[5], ea, eb)
	_wall_segs.clear()


func _wall_box(x: int, z: int, length_i: int, horiz: bool, glass: bool, ext_a := 0.0, ext_b := 0.0) -> void:
	var length := length_i + ext_a + ext_b
	var c := _rect_center(x, z, length_i if horiz else 1, 1 if horiz else length_i)
	var shift := (ext_b - ext_a) / 2.0
	if horiz:
		c.x += shift
	else:
		c.z += shift
	var size := Vector3(length, 1.6, 0.2) if horiz else Vector3(0.2, 1.6, length)
	_box(Vector3(c.x, 0.8, c.z), size, CREAM, "wallpaper", 1.0)
	var base := Vector3(length, 0.14, 0.24) if horiz else Vector3(0.24, 0.14, length)
	_box(Vector3(c.x, 0.07, c.z), base, BRAND_INK, "planks")
	var trim := Vector3(length + 0.04, 0.08, 0.28) if horiz else Vector3(0.28, 0.08, length + 0.04)
	_box(Vector3(c.x, 1.62, c.z), trim, BRAND_BLUE, "metal")
	if glass:
		var gs := Vector3(length, 0.9, 0.06) if horiz else Vector3(0.06, 0.9, length)
		Agent.make_box(cur, Vector3(c.x, 2.12, c.z), gs, Color(0.75, 0.88, 0.95, 0.3))


func _hwall(x0: int, x1: int, z: int, gaps: Array, glass := false) -> void:
	var start := -1
	for x in range(x0, x1 + 2):
		var open := x <= x1 and not _in_gaps(x, gaps)
		if open:
			if start < 0:
				start = x
			g.set_point_solid(Vector2i(x, z), true)
		elif start >= 0:
			_queue_wall(start, z, x - start, true, glass)
			start = -1


func _vwall(x: int, z0: int, z1: int, gaps: Array, glass := false) -> void:
	var start := -1
	for z in range(z0, z1 + 2):
		var open := z <= z1 and not _in_gaps(z, gaps)
		if open:
			if start < 0:
				start = z
			g.set_point_solid(Vector2i(x, z), true)
		elif start >= 0:
			_queue_wall(x, start, z - start, false, glass)
			start = -1


func _side_place(side: String, along: float, y: float, inset := 0.0) -> Vector3:
	match side:
		"N": return Vector3(along - W / 2.0, y, -H / 2.0 - WALL_T / 2.0 + inset)
		"S": return Vector3(along - W / 2.0, y, H / 2.0 + WALL_T / 2.0 - inset)
		"W": return Vector3(-W / 2.0 - WALL_T / 2.0 + inset, y, along - H / 2.0)
		_: return Vector3(W / 2.0 + WALL_T / 2.0 - inset, y, along - H / 2.0)


func _side_size(side: String, length: float, height: float, thick: float) -> Vector3:
	return Vector3(length, height, thick) if side in ["N", "S"] else Vector3(thick, height, length)


## Dinding luar dari a ke b (satuan sel) di sisi bangunan. Masuk grup sisi agar bisa disembunyikan kamera.
func _outer_seg(side: String, a: float, b: float, height: float, base := 0.0) -> void:
	var node: Node3D = ext_walls[cf][side]
	var horiz := side in ["N", "S"]
	var ea := a - (WALL_T if horiz and a <= 0.0 else 0.0)
	var eb := b + (WALL_T if horiz and b >= W else 0.0)
	var mid := (ea + eb) / 2.0
	var length := eb - ea
	var outer: Color = [Color(0.30, 0.31, 0.34), Color(0.93, 0.94, 0.95), BRAND_BLUE][cf]
	var otex: String = ["brick", "planks", "metal"][cf]
	if height < 1.3:
		node = cur  # pagar rendah tidak menghalangi kamera, jadi selalu tampil
		Agent.make_box(node, _side_place(side, mid, base + height / 2.0), _side_size(side, length, height, 0.14), WOOD, "planks")
		Agent.make_box(node, _side_place(side, mid, base + height + 0.04), _side_size(side, length + 0.05, 0.08, 0.26), DARK_WOOD, "planks")
		return
	Agent.make_box(node, _side_place(side, mid, base + height / 2.0), _side_size(side, length, height, WALL_T), outer, otex, 0.5)
	if base == 0.0:
		Agent.make_box(node, _side_place(side, mid, 0.08, WALL_T / 2.0 + 0.01), _side_size(side, length, 0.16, 0.04), BRAND_INK, "planks")
	# pita biru brand di sisi luar bagian atas
	Agent.make_box(node, _side_place(side, mid, base + height - 0.2, -0.02), _side_size(side, length, 0.22, WALL_T + 0.02), BRAND_LIGHT if cf == 2 else BRAND_BLUE, "metal")
	Agent.make_box(node, _side_place(side, mid, base + height / 2.0 + 0.08, WALL_T / 2.0), _side_size(side, length, height - 0.16, 0.02), CREAM, "wallpaper", 1.0)


func _outer_window(side: String, along: float, width := 2.0, sill := 1.0, wh := 1.2) -> void:
	var node: Node3D = ext_walls[cf][side]
	var wk := "%d:%s" % [cf, side]
	if not _windows.has(wk):
		_windows[wk] = []
	_windows[wk].append([along, width])
	var cy := sill + wh / 2.0
	var th := WALL_T + 0.1
	var fr := Color(0.95, 0.93, 0.88)
	var glass := Color(0.62, 0.80, 0.95)
	Agent.make_box(node, _side_place(side, along, cy), _side_size(side, width, wh, WALL_T + 0.04), glass, "grain")
	Agent.make_box(node, _side_place(side, along, sill - 0.05), _side_size(side, width + 0.3, 0.1, th + 0.1), fr, "planks")
	Agent.make_box(node, _side_place(side, along, sill + wh + 0.05), _side_size(side, width + 0.2, 0.1, th), fr, "planks")
	Agent.make_box(node, _side_place(side, along - width / 2.0, cy), _side_size(side, 0.1, wh, th), fr, "planks")
	Agent.make_box(node, _side_place(side, along + width / 2.0, cy), _side_size(side, 0.1, wh, th), fr, "planks")
	Agent.make_box(node, _side_place(side, along, cy), _side_size(side, 0.06, wh, th), fr, "planks")
	Agent.make_box(node, _side_place(side, along, cy), _side_size(side, width, 0.06, th), fr, "planks")


func _start_floor(f: int) -> void:
	cf = f
	cur = floors[f]
	g = grids[f]


# ---------- perabot ----------

func _add_spot(place: String, cell: Vector2i, kind: String, yaw_: float, approach := NONE, shift := 0.2) -> void:
	var s := {"cell": cell, "floor": cf, "kind": kind, "yaw": yaw_, "approach": approach, "shift": shift}
	if place == "desk":
		desk_spots.append(s)
	else:
		if not places.has(place):
			places[place] = []
		places[place].append(s)


func _chair(cell: Vector2i, yaw_: float, color: Color) -> void:
	var n := Node3D.new()
	n.position = _cw(cell) + Vector3(sin(yaw_), 0, cos(yaw_)) * 0.2
	n.rotation.y = yaw_
	cur.add_child(n)
	Agent.make_box(n, Vector3(0, 0.42, 0), Vector3(0.52, 0.1, 0.52), color, "cloth", 2.0)
	Agent.make_box(n, Vector3(0, 0.75, -0.24), Vector3(0.52, 0.55, 0.08), color, "cloth", 2.0)
	for sx in [-0.21, 0.21]:
		for sz in [-0.21, 0.21]:
			Agent.make_box(n, Vector3(sx, 0.19, sz), Vector3(0.06, 0.38, 0.06), DARK_WOOD, "planks")


func _desk(cx: int, cz: int, dir: int, agent_spot := true) -> void:
	_solid(cx, cz)
	var c := _cw(Vector2i(cx, cz))
	var s := float(dir)
	var wood := WOOD.darkened(rng.randf_range(0.0, 0.25))
	_box(Vector3(c.x, 0.72, c.z + 0.1 * s), Vector3(1.5, 0.08, 0.8), wood, "planks", 1.0)
	_box(Vector3(c.x - 0.68, 0.36, c.z + 0.1 * s), Vector3(0.1, 0.72, 0.72), wood.darkened(0.2), "planks", 1.0)
	_box(Vector3(c.x + 0.68, 0.36, c.z + 0.1 * s), Vector3(0.1, 0.72, 0.72), wood.darkened(0.2), "planks", 1.0)
	_box(Vector3(c.x, 0.82, c.z - 0.15 * s), Vector3(0.1, 0.15, 0.1), Color(0.25, 0.25, 0.25))
	_box(Vector3(c.x, 1.02, c.z - 0.15 * s), Vector3(0.62, 0.4, 0.06), Color(0.85, 0.83, 0.78))
	_box(Vector3(c.x, 1.02, c.z - 0.11 * s), Vector3(0.52, 0.31, 0.02), Color(0.25, 0.45, 0.55).lightened(rng.randf() * 0.2))
	_box(Vector3(c.x, 0.77, c.z + 0.12 * s), Vector3(0.44, 0.03, 0.15), Color(0.85, 0.83, 0.78))
	_box(Vector3(c.x + 0.5, 0.81, c.z + 0.2 * s), Vector3(0.1, 0.12, 0.1), Color.from_hsv(rng.randf(), 0.5, 0.9))
	_box(Vector3(c.x - 0.45, 0.78, c.z + 0.15 * s), Vector3(0.26, 0.03, 0.34), Color(0.98, 0.97, 0.93))
	var yaw_ := PI if dir > 0 else 0.0
	var chair := Vector2i(cx, cz + dir)
	_chair(chair, yaw_, Color(0.20, 0.21, 0.24))
	if agent_spot:
		_add_spot("desk", chair, "sit", yaw_)


func _plant(x: int, z: int, big := false) -> void:
	_solid(x, z)
	var p := _cw(Vector2i(x, z))
	_box(Vector3(p.x, 0.25, p.z), Vector3(0.5, 0.5, 0.5), Color(0.75, 0.45, 0.32), "brick", 1.0)
	_box(Vector3(p.x, 0.51, p.z), Vector3(0.44, 0.03, 0.44), Color(0.4, 0.28, 0.2), "dirt")
	var s := 1.3 if big else 1.0
	var g1 := _box(Vector3(p.x, 0.85 * s, p.z), Vector3(0.7, 0.6, 0.7) * s, Color(0.40, 0.70, 0.35), "leaves")
	g1.rotation_degrees.y = rng.randf_range(0, 90)
	var g2 := _box(Vector3(p.x, 1.25 * s, p.z), Vector3(0.5, 0.45, 0.5) * s, Color(0.48, 0.78, 0.40), "leaves")
	g2.rotation_degrees = Vector3(0, rng.randf_range(0, 90), 10)


func _bookshelf(x: int, z: int, w: int) -> void:
	_solid(x, z, w, 1)
	var c := _rect_center(x, z, w, 1)
	_box(Vector3(c.x, 1.0, c.z - 0.05), Vector3(w, 2.0, 0.5), DARK_WOOD, "planks", 1.0)
	for lvl in [0.45, 0.85, 1.25, 1.65]:
		var px := c.x - w / 2.0 + 0.15
		while px < c.x + w / 2.0 - 0.1:
			var bh := rng.randf_range(0.24, 0.34)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.6), rng.randf_range(0.55, 0.85))
			_box(Vector3(px, lvl - 0.15 + bh / 2.0, c.z + 0.1), Vector3(0.12, bh, 0.3), col, "cloth", 2.0)
			px += 0.15 if rng.randf() < 0.9 else 0.3


func _sofa(center: Vector3, length: float, yaw_: float, color: Color) -> void:
	var n := Node3D.new()
	n.position = center
	n.rotation.y = yaw_
	cur.add_child(n)
	Agent.make_box(n, Vector3(0, 0.25, 0), Vector3(length, 0.5, 0.9), color, "cloth", 2.0)
	Agent.make_box(n, Vector3(0, 0.55, 0.05), Vector3(length - 0.5, 0.12, 0.75), color.lightened(0.1), "cloth", 2.0)
	Agent.make_box(n, Vector3(0, 0.8, -0.35), Vector3(length, 0.6, 0.22), color.darkened(0.15), "cloth", 2.0)
	Agent.make_box(n, Vector3(-length / 2.0 + 0.12, 0.62, 0.05), Vector3(0.24, 0.35, 0.8), color.darkened(0.1), "cloth", 2.0)
	Agent.make_box(n, Vector3(length / 2.0 - 0.12, 0.62, 0.05), Vector3(0.24, 0.35, 0.8), color.darkened(0.1), "cloth", 2.0)


func _beanbag(cell: Vector2i, yaw_: float, place: String, color: Color) -> void:
	var p := _cw(cell)
	_cyl(Vector3(p.x, 0.22, p.z), 0.5, 0.44, color, "cloth")
	_cyl(Vector3(p.x, 0.5, p.z), 0.36, 0.2, color.lightened(0.1), "cloth")
	_add_spot(place, cell, "sit", yaw_, NONE, 0.0)


func _round_table(tx: int, tz: int, place: String, chair_col: Color) -> void:
	_solid(tx, tz, 2, 2)
	var c := _rect_center(tx, tz, 2, 2)
	_cyl(Vector3(c.x, 0.72, c.z), 1.05, 0.08, WOOD, "planks")
	_cyl(Vector3(c.x, 0.36, c.z), 0.14, 0.72, DARK_WOOD, "planks")
	_cyl(Vector3(c.x + 0.2, 0.82, c.z - 0.1), 0.08, 0.14, Color(0.95, 0.95, 0.9))
	for e in [
		[Vector2i(tx, tz - 1), 0.0],
		[Vector2i(tx + 1, tz + 2), PI],
		[Vector2i(tx - 1, tz + 1), PI / 2],
		[Vector2i(tx + 2, tz), -PI / 2],
	]:
		_chair(e[0], e[1], chair_col)
		_add_spot(place, e[0], "sit", e[1])


func _rug(x: float, z: float, w: float, h: float, color: Color, round_ := false, lift := 0.0) -> void:
	var c := _rect_center(x, z, w, h)
	if round_:
		_cyl(Vector3(c.x, 0.035 + lift, c.z), minf(w, h) / 2.0, 0.02, color, "carpet", 24)
	else:
		_box(Vector3(c.x, 0.03, c.z), Vector3(w, 0.02, h), color, "carpet", 1.0)
		_box(Vector3(c.x, 0.035, c.z), Vector3(w - 0.4, 0.02, h - 0.4), color.lightened(0.15), "carpet", 1.0)


func _painting(pos: Vector3, along_x: bool, col: Color) -> void:
	var fs := Vector3(1.0, 0.8, 0.06) if along_x else Vector3(0.06, 0.8, 1.0)
	var ps := Vector3(0.84, 0.64, 0.08) if along_x else Vector3(0.08, 0.64, 0.84)
	_box(pos, fs, Color(0.85, 0.65, 0.3), "planks", 2.0)
	_box(pos, ps, col, "carpet", 1.0)


func _floor_finish(x: float, z: float, w: float, h: float, color: Color, tex: String, scale := 0.5) -> void:
	var c := _rect_center(x, z, w, h)
	_box(Vector3(c.x, 0.01, c.z), Vector3(w, 0.02, h), color, tex, scale)


# ---------- dunia ----------

func _build_world() -> void:
	for f in NFLOORS:
		var gr := AStarGrid2D.new()
		gr.region = Rect2i(0, 0, W, H)
		gr.cell_size = Vector2.ONE
		gr.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		gr.update()
		grids.append(gr)
		var root := Node3D.new()
		root.name = "Lantai%d" % (f + 1)
		root.position.y = f * FH
		add_child(root)
		floors.append(root)
		var sides := {}
		for sd in SIDE_N:
			var n := Node3D.new()
			root.add_child(n)
			sides[sd] = n
		ext_walls.append(sides)
	_build_outside()
	town = preload("res://town.gd").new()
	town.name = "Kota"
	add_child(town)
	town.build()
	_build_floor0()
	_build_floor1()
	_build_floor2()
	_build_signs()
	_flush_walls()
	_decorate_walls()
	# gabungkan mesh diam per lantai / per sisi dinding supaya draw call sedikit
	town.set_meta("no_batch", true)
	for f in NFLOORS:
		for sd in ext_walls[f]:
			var n: Node3D = ext_walls[f][sd]
			n.set_meta("no_batch", true)
			Look.batch(n, true)
		Look.batch(floors[f], true)
		floors[f].set_meta("no_batch", true)
	Look.batch(self, true)


func _build_outside() -> void:
	cur = self
	_box(Vector3(0, -0.18, 0), Vector3(320, 0.2, 260), Color(1, 1, 1), "grass", 0.25)
	_box(Vector3(0, -0.1, 0), Vector3(W + 1.0, 0.2, H + 1.0), Color(0.78, 0.74, 0.68), "stone", 0.5)
	# jalan setapak dari pintu lobby
	_box(Vector3(6 - W / 2.0, -0.07, H / 2.0 + 7.0), Vector3(2.4, 0.04, 13.0), Color(1, 1, 1), "dirt", 0.5)
	_box(Vector3(6 - W / 2.0, 0.0, H / 2.0 + 1.1), Vector3(2.2, 0.03, 1.0), Color(0.55, 0.30, 0.25), "carpet", 1.0)
	# bedeng bunga di depan
	var flower_cols := [Color(0.95, 0.4, 0.45), Color(0.98, 0.85, 0.3), Color(0.75, 0.5, 0.95), Color(1, 1, 1)]
	for seg in [[1.0, 4.4], [7.6, 20.0], [24.0, 43.0]]:
		var a: float = seg[0]
		var b: float = seg[1]
		var cx := (a + b) / 2.0 - W / 2.0
		_box(Vector3(cx, 0.12, H / 2.0 + 0.9), Vector3(b - a, 0.25, 0.9), DARK_WOOD, "planks")
		_box(Vector3(cx, 0.25, H / 2.0 + 0.9), Vector3(b - a - 0.1, 0.04, 0.75), Color(1, 1, 1), "dirt")
		var x := a + 0.4
		while x < b - 0.3:
			var fc: Color = flower_cols.pick_random()
			_box(Vector3(x - W / 2.0, 0.38, H / 2.0 + 0.9 + rng.randf_range(-0.2, 0.2)), Vector3(0.2, 0.22, 0.2), Color(0.35, 0.6, 0.3), "leaves")
			_box(Vector3(x - W / 2.0, 0.52, H / 2.0 + 0.9 + rng.randf_range(-0.2, 0.2)), Vector3(0.16, 0.12, 0.16), fc)
			x += 0.55
	# pagar keliling
	var fx := 33.0
	var fz0 := -24.0
	var fz1 := 28.0
	var gate := 6 - W / 2.0
	_fence(Vector3(-fx, 0, fz0), Vector3(fx, 0, fz0))
	_fence(Vector3(-fx, 0, fz0), Vector3(-fx, 0, fz1))
	_fence(Vector3(fx, 0, fz0), Vector3(fx, 0, fz1))
	_fence(Vector3(-fx, 0, fz1), Vector3(gate - 1.6, 0, fz1))
	_fence(Vector3(gate + 1.6, 0, fz1), Vector3(fx, 0, fz1))
	# pohon
	for p in [Vector2(-28, -19), Vector2(-28, -6), Vector2(-29, 7), Vector2(-27, 20), Vector2(28, -19),
			Vector2(-12, 25), Vector2(14, -22), Vector2(27, 21), Vector2(-1.5, 25.5), Vector2(8, 23),
			Vector2(19, 22), Vector2(-3, -20), Vector2(13, -21), Vector2(-15, -20), Vector2(24, -21), Vector2(-22, 24)]:
		_tree(Vector3(p.x + rng.randf_range(-1, 1), 0, p.y + rng.randf_range(-1, 1)), rng.randf_range(0.85, 1.25))
	# kotak surat & bangku
	var mb := Vector3(gate - 2.2, 0, H / 2.0 + 3.0)
	_box(mb + Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12), DARK_WOOD, "planks")
	_box(mb + Vector3(0, 1.1, 0), Vector3(0.35, 0.3, 0.55), Color(0.85, 0.25, 0.2))
	_bench(Vector3(gate + 3.5, 0, H / 2.0 + 5.0), -PI / 2)


func _fence(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var n := int(d.length() / 2.0)
	var col := Color(0.92, 0.88, 0.80)
	for i in n + 1:
		var p := a + d * (float(i) / maxf(n, 1))
		_box(p + Vector3(0, 0.5, 0), Vector3(0.16, 1.0, 0.16), col, "planks")
	var mid := (a + b) / 2.0
	var along_x := absf(d.x) > absf(d.z)
	for y in [0.35, 0.75]:
		var size := Vector3(d.length(), 0.1, 0.06) if along_x else Vector3(0.06, 0.1, d.length())
		_box(mid + Vector3(0, y, 0), size, col, "planks")


func _tree(p: Vector3, s: float) -> void:
	_box(p + Vector3(0, 1.1 * s, 0), Vector3(0.45, 2.2, 0.45) * s, Color(0.55, 0.38, 0.25), "planks", 1.0)
	var leaf := Color(0.42, 0.68, 0.32).lightened(rng.randf_range(-0.1, 0.1))
	var b1 := _box(p + Vector3(0, 2.6 * s, 0), Vector3(2.2, 1.6, 2.2) * s, leaf, "leaves", 0.5)
	b1.rotation_degrees.y = rng.randf_range(0, 90)
	var b2 := _box(p + Vector3(0.3, 3.5 * s, -0.2), Vector3(1.5, 1.1, 1.5) * s, leaf.lightened(0.08), "leaves", 0.5)
	b2.rotation_degrees.y = rng.randf_range(0, 90)
	if rng.randf() < 0.5:
		for i in 3:
			_box(p + Vector3(rng.randf_range(-1, 1) * s, 2.3 * s, rng.randf_range(-1, 1) * s), Vector3(0.18, 0.18, 0.18), Color(0.95, 0.35, 0.3))


func _bench(p: Vector3, yaw_: float) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = yaw_
	cur.add_child(n)
	Agent.make_box(n, Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.5), WOOD, "planks")
	Agent.make_box(n, Vector3(0, 0.75, -0.22), Vector3(1.8, 0.4, 0.06), WOOD, "planks")
	for sx in [-0.75, 0.75]:
		Agent.make_box(n, Vector3(sx, 0.22, 0), Vector3(0.08, 0.45, 0.45), Color(0.25, 0.25, 0.28), "metal")


# ---------- lantai 1 ----------

func _build_floor0() -> void:
	_start_floor(0)
	_floor_finish(0, 0, 26, 14, Color(0.92, 0.72, 0.48), "planks", 0.5)
	_floor_finish(26, 0, 9, 9, Color(0.78, 0.60, 0.42), "planks", 0.5)
	_floor_finish(35, 0, 9, 9, Color(0.62, 0.68, 0.80), "carpet", 0.5)
	_floor_finish(37, 10, 7, 8, Color(0.62, 0.64, 0.68), "metal", 0.5)
	_floor_finish(27, 18, 17, 12, Color(0.96, 0.94, 0.86), "tiles", 0.5)
	_floor_finish(12, 19, 15, 11, Color(0.86, 0.62, 0.45), "planks", 0.5)
	_floor_finish(0, 19, 12, 11, Color(0.92, 0.84, 0.70), "stone", 0.5)

	_outer_seg("N", 0, W, FH)
	_outer_seg("W", 0, H, FH)
	_outer_seg("E", 0, H, FH)
	_outer_seg("S", 0, 5, FH)
	_outer_seg("S", 7, W, FH)
	_outer_seg("S", 5, 7, FH - 2.4, 2.4)
	for x in [3.0, 7.5, 12.0, 17.5, 22.0, 30.5, 39.5]:
		_outer_window("N", x)
	for z in [4.0, 10.0, 16.5, 23.0, 27.5]:
		_outer_window("W", z)
	for z in [4.5, 21.0, 26.0]:
		_outer_window("E", z)
	for x in [2.5, 9.5, 15.5, 22.5, 31.0, 37.0, 41.5]:
		_outer_window("S", x)

	_hwall(26, 43, 9, [[30, 31], [36, 36]], true)
	_vwall(26, 0, 9, [], true)
	_vwall(35, 0, 9, [], true)
	_vwall(37, 10, 17, [[13, 14]])
	_hwall(27, 43, 18, [[33, 34]])
	_vwall(27, 18, 29, [[23, 24]])

	_build_workspace()
	_build_stairs()
	_build_meeting()
	_build_server()
	_build_pantry()
	_build_lounge()
	_build_lobby()

	for c in [Vector2i(0, 15), Vector2i(25, 15), Vector2i(36, 15), Vector2i(12, 17)]:
		_plant(c.x, c.y, true)

	_room_label("WORKSPACE", 13, 7)
	_room_label("TANGGA & ARSIP", 30.5, 2)
	_room_label("MEETING", 39.5, 4.5)
	_room_label("SERVER", 40.5, 13.5)
	_room_label("PANTRY", 35.5, 21)
	_room_label("LOUNGE", 19.5, 24.5)
	_room_label("LOBBY", 6, 23)


func _build_workspace() -> void:
	for x in [3, 7, 11, 16, 20]:
		_desk(x, 2, 1)
	for x in [3, 7, 11, 16, 20]:
		_desk(x, 5, -1)
	for x in [5, 9, 14, 18, 22]:
		_desk(x, 8, 1)
	for x in [5, 9, 14, 18, 22]:
		_desk(x, 11, -1)
	_bookshelf(22, 0, 4)
	_solid(13, 0, 3, 1)
	var wc := _rect_center(13, 0, 3, 1)
	_box(Vector3(wc.x, 1.5, -H / 2.0 + 0.08), Vector3(3, 1.3, 0.08), Color(0.55, 0.40, 0.25), "planks")
	_box(Vector3(wc.x, 1.5, -H / 2.0 + 0.12), Vector3(2.8, 1.1, 0.04), Color(0.97, 0.97, 0.95))
	for c in [Vector2i(1, 7), Vector2i(1, 12), Vector2i(24, 12), Vector2i(14, 6), Vector2i(25, 7)]:
		_plant(c.x, c.y)
	_painting(Vector3(-W / 2.0 + 0.05, 1.7, 7.5 - H / 2.0), false, Color(0.45, 0.65, 0.85))
	_lamp(Vector2i(7, 7), Color(1, 0.92, 0.78), 0.9, 12.0)
	_lamp(Vector2i(19, 7), Color(1, 0.92, 0.78), 0.9, 12.0)


func _build_stairs() -> void:
	_solid(STAIR_X0, STAIR_Z, STAIR_X1 - STAIR_X0, 2)
	var steps := 12
	var depth := float(STAIR_X1 - STAIR_X0) / steps
	var rise := FH / steps
	var zc := STAIR_Z + 1.0 - H / 2.0
	for i in steps:
		var x0 := STAIR_X0 + i * depth - W / 2.0
		var h := (i + 1) * rise
		_box(Vector3(x0 + depth / 2.0, h / 2.0, zc), Vector3(depth, h, 2.0), Color(0.80, 0.60, 0.40), "planks", 1.0)
		_box(Vector3(x0 + depth / 2.0, h - 0.02, zc), Vector3(depth + 0.04, 0.05, 2.04), DARK_WOOD, "planks", 1.0)
	# pegangan tangga sisi selatan
	for i in range(0, steps + 1, 2):
		var x := STAIR_X0 + i * depth - W / 2.0
		_box(Vector3(x, i * rise + 0.5, zc + 1.0), Vector3(0.08, 1.0, 0.08), DARK_WOOD, "planks")
	var run := float(STAIR_X1 - STAIR_X0)
	var rail := _box(Vector3((STAIR_X0 + STAIR_X1) / 2.0 - W / 2.0, FH / 2.0 + 1.0, zc + 1.0), Vector3(Vector2(run, FH).length(), 0.08, 0.1), DARK_WOOD, "planks")
	rail.rotation.z = atan2(FH, run)
	# arsip
	_bookshelf(27, 0, 7)
	for c in [Vector2i(33, 7), Vector2i(34, 7), Vector2i(34, 6)]:
		_solid(c.x, c.y)
		var p := _cw(c)
		_box(p + Vector3(0, 0.3, 0), Vector3(0.7, 0.6, 0.7), Color(0.80, 0.65, 0.45), "cloth", 1.0)
		_box(p + Vector3(0.05, 0.8, 0), Vector3(0.6, 0.4, 0.6), Color(0.85, 0.70, 0.50), "cloth", 1.0)
	_plant(27, 8)
	_lamp(Vector2i(30, 6), Color(1, 0.9, 0.75), 0.8, 8.0)


func _build_meeting() -> void:
	_solid(37, 3, 5, 2)
	var c := _rect_center(37, 3, 5, 2)
	_rug(36, 1.5, 7, 5, Color(0.55, 0.62, 0.78))
	_box(Vector3(c.x, 0.72, c.z), Vector3(5, 0.1, 2), WOOD, "planks", 1.0)
	_box(Vector3(c.x, 0.35, c.z), Vector3(4.4, 0.7, 1.4), DARK_WOOD, "planks", 1.0)
	for x in range(37, 42):
		_chair(Vector2i(x, 2), 0.0, Color(0.30, 0.38, 0.55))
		_add_spot("meeting", Vector2i(x, 2), "sit", 0.0)
		_chair(Vector2i(x, 5), PI, Color(0.30, 0.38, 0.55))
		_add_spot("meeting", Vector2i(x, 5), "sit", PI)
	var tv := _rect_center(38, 0, 3, 1)
	_box(Vector3(tv.x, 1.6, -H / 2.0 + 0.08), Vector3(2.4, 1.3, 0.08), Color(0.12, 0.12, 0.14))
	_box(Vector3(tv.x, 1.6, -H / 2.0 + 0.12), Vector3(2.2, 1.1, 0.04), Color(0.35, 0.55, 0.75))
	_plant(38, 8)
	_plant(42, 8)
	_lamp(Vector2i(39, 4), Color(1, 0.97, 0.9), 0.8, 9.0)


func _build_server() -> void:
	for x in range(38, 44):
		_server_rack(x, 11, 1.0)
		_server_rack(x, 16, -1.0)
	for x in [39, 41, 43]:
		_add_spot("server", Vector2i(x, 12), "stand", PI)
		_add_spot("server", Vector2i(x, 15), "stand", 0.0)
	_lamp(Vector2i(40, 13), Color(0.55, 0.75, 1.0), 1.2, 8.0)


func _server_rack(x: int, z: int, face: float) -> void:
	_solid(x, z)
	var p := _cw(Vector2i(x, z))
	_box(Vector3(p.x, 1.0, p.z), Vector3(0.85, 2.0, 0.9), Color(0.25, 0.26, 0.30), "metal", 1.0)
	for i in range(5):
		var led := Color(0.3, 1.0, 0.5) if rng.randf() < 0.7 else Color(1.0, 0.7, 0.2)
		_box(Vector3(p.x - 0.28 + i * 0.14, 0.6 + i * 0.28, p.z + 0.46 * face), Vector3(0.08, 0.05, 0.03), led)


func _build_pantry() -> void:
	_solid(28, 19, 4, 1)
	var cc := _rect_center(28, 19, 4, 1)
	_box(Vector3(cc.x, 0.45, cc.z), Vector3(4, 0.9, 0.9), Color(0.70, 0.52, 0.35), "planks", 1.0)
	_box(Vector3(cc.x, 0.92, cc.z), Vector3(4.1, 0.06, 1.0), Color(0.92, 0.90, 0.85), "stone")
	_box(Vector3(cc.x - 1.2, 1.12, cc.z), Vector3(0.45, 0.32, 0.35), Color(0.2, 0.2, 0.2), "metal")
	_box(Vector3(cc.x + 0.5, 0.97, cc.z), Vector3(0.7, 0.05, 0.5), Color(0.75, 0.8, 0.85), "metal")
	var cups := [Color(0.9, 0.3, 0.3), Color(1, 1, 1), Color(0.3, 0.6, 0.9)]
	for i in 3:
		_cyl(Vector3(cc.x - 0.4 + i * 0.15, 1.0, cc.z + 0.2), 0.05, 0.1, cups[i])
	_solid(32, 19)
	var fc := _cw(Vector2i(32, 19))
	_box(Vector3(fc.x, 0.9, fc.z), Vector3(0.8, 1.8, 0.8), Color(0.92, 0.94, 0.95), "metal")
	_solid(36, 19)
	var vc := _cw(Vector2i(36, 19))
	_box(Vector3(vc.x, 0.95, vc.z), Vector3(0.9, 1.9, 0.8), Color(0.85, 0.25, 0.22))
	_box(Vector3(vc.x, 1.1, vc.z + 0.41), Vector3(0.6, 0.9, 0.03), Color(0.95, 0.92, 0.75))
	for x in range(28, 32):
		_add_spot("pantry", Vector2i(x, 20), "stand", PI)
	for tx in [30, 35, 40]:
		_round_table(tx, 23, "pantry", Color(0.85, 0.55, 0.30))
	_plant(43, 19)
	_plant(28, 29)
	_plant(43, 29)
	_lamp(Vector2i(31, 24), Color(1, 0.92, 0.8), 0.9, 11.0)
	_lamp(Vector2i(39, 24), Color(1, 0.92, 0.8), 0.9, 11.0)


func _build_lounge() -> void:
	_rug(14.5, 20.5, 10, 9, Color(0.40, 0.60, 0.55), true)
	_rug(16.5, 22.5, 6, 5, Color(0.88, 0.80, 0.62), true, 0.02)
	_solid(17, 22, 4, 1)
	_sofa(_rect_center(17, 22, 4, 1), 4.0, 0.0, Color(0.40, 0.55, 0.75))
	_solid(17, 27, 4, 1)
	_sofa(_rect_center(17, 27, 4, 1), 4.0, PI, Color(0.80, 0.50, 0.38))
	for x in range(17, 21):
		_add_spot("lounge", Vector2i(x, 22), "sit", 0.0, Vector2i(x, 23), 0.0)
		_add_spot("lounge", Vector2i(x, 27), "sit", PI, Vector2i(x, 26), 0.0)
	_solid(18, 24, 2, 2)
	var tc := _rect_center(18, 24, 2, 2)
	_box(Vector3(tc.x, 0.3, tc.z), Vector3(1.8, 0.08, 1.2), WOOD, "planks", 1.0)
	_box(Vector3(tc.x, 0.14, tc.z), Vector3(1.4, 0.28, 0.8), DARK_WOOD, "planks", 1.0)
	_beanbag(Vector2i(15, 24), PI / 2, "lounge", Color(0.95, 0.60, 0.30))
	_beanbag(Vector2i(15, 25), PI / 2, "lounge", Color(0.90, 0.45, 0.55))
	_beanbag(Vector2i(22, 24), -PI / 2, "lounge", Color(0.50, 0.75, 0.45))
	_beanbag(Vector2i(22, 25), -PI / 2, "lounge", Color(0.95, 0.80, 0.35))
	for c in [Vector2i(12, 19), Vector2i(26, 19), Vector2i(12, 29), Vector2i(26, 29)]:
		_plant(c.x, c.y, true)
	_solid(14, 21)
	var lp := _cw(Vector2i(14, 21))
	_cyl(Vector3(lp.x, 0.8, lp.z), 0.04, 1.6, Color(0.25, 0.25, 0.25), "metal")
	_cyl(Vector3(lp.x, 1.7, lp.z), 0.3, 0.35, Color(0.98, 0.9, 0.65), "cloth")
	_lamp(Vector2i(19, 24), Color(1, 0.82, 0.6), 1.1, 11.0)


func _build_lobby() -> void:
	_solid(3, 25, 6, 1)
	var rc := _rect_center(3, 25, 6, 1)
	_box(Vector3(rc.x, 0.5, rc.z), Vector3(6, 1.0, 1.0), BRAND_INK, "planks", 1.0)
	_box(Vector3(rc.x, 0.55, rc.z + 0.51), Vector3(5.6, 0.12, 0.02), BRAND_BLUE, "metal")
	_box(Vector3(rc.x, 1.03, rc.z), Vector3(6.3, 0.06, 1.25), Color(0.97, 0.97, 0.98), "stone")
	_box(Vector3(rc.x + 1.5, 1.3, rc.z + 0.1), Vector3(0.5, 0.35, 0.05), Color(0.2, 0.35, 0.5))
	_box(Vector3(rc.x - 1.5, 1.1, rc.z), Vector3(0.18, 0.1, 0.18), Color(0.95, 0.8, 0.25))
	_chair(Vector2i(5, 26), PI, Color(0.3, 0.3, 0.35))
	_rug(2.5, 20, 7, 4, BRAND_PINK, true)
	for x in range(4, 8):
		_add_spot("lobby", Vector2i(x, 22), "stand", 0.0)
	_solid(0, 20, 1, 4)
	_sofa(_rect_center(0, 20, 1, 4), 4.0, PI / 2, BRAND_BLUE)
	for z in range(20, 24):
		_add_spot("lobby", Vector2i(0, z), "sit", PI / 2, Vector2i(1, z), 0.0)
	_plant(11, 19)
	_plant(11, 29)
	_plant(1, 29)
	_painting(Vector3(-W / 2.0 + 0.05, 1.7, 26 - H / 2.0), false, Color(0.85, 0.6, 0.35))
	_lamp(Vector2i(5, 23), Color(1, 0.9, 0.75), 1.0, 10.0)


# ---------- lantai 2 ----------

func _build_floor1() -> void:
	_start_floor(1)
	var slab := Color(0.88, 0.70, 0.48)
	for r in [[0, 0, STAIR_X0, H], [STAIR_X1, 0, W - STAIR_X1, H], [STAIR_X0, 0, STAIR_X1 - STAIR_X0, STAIR_Z],
			[STAIR_X0, STAIR_Z + 2, STAIR_X1 - STAIR_X0, H - STAIR_Z - 2]]:
		var c := _rect_center(r[0], r[1], r[2], r[3])
		_box(Vector3(c.x, -0.1, c.z), Vector3(r[2], 0.2, r[3]), slab, "planks", 0.5)
	_floor_finish(0, 0, 18, 13, BRAND_BLUE.darkened(0.25), "carpet", 0.5)
	_floor_finish(19, 0, 8, 13, Color(0.66, 0.48, 0.32), "planks", 0.5)
	_floor_finish(38, 0, 6, 13, BRAND_LIGHT, "carpet", 0.5)
	_floor_finish(0, 19, W, 11, Color(0.86, 0.72, 0.52), "planks", 1.0)

	_outer_seg("N", 0, W, 3.0)
	_outer_seg("W", 0, 19, 3.0)
	_outer_seg("E", 0, 19, 3.0)
	_outer_seg("W", 19, H, 1.0)
	_outer_seg("E", 19, H, 1.0)
	_outer_seg("S", 0, W, 1.0)
	for x in [3.0, 9.0, 15.0, 23.0, 32.0, 41.0]:
		_outer_window("N", x)
	for z in [3.5, 9.5, 15.5]:
		_outer_window("W", z)
		_outer_window("E", z)

	_hwall(0, 17, 13, [[8, 9]])
	_vwall(18, 0, 13, [])
	_hwall(19, 26, 13, [[22, 23]])
	_vwall(27, 0, 13, [])
	_vwall(37, 0, 13, [[9, 10]])
	_hwall(38, 43, 13, [])
	_hwall(0, 43, 18, [[9, 11], [31, 33]], true)

	_build_stairwell()
	_build_my_office()
	_build_library()
	_build_small_meeting()
	_build_terrace()

	_room_label("RUANG KAMU", 9, 1.5)
	_room_label("PERPUSTAKAAN", 23, 6.5)
	_room_label("TANGGA", 32, 8)
	_room_label("RAPAT KECIL", 41, 8.5)
	_room_label("TERAS & KEBUN", 22, 24)


func _build_stairwell() -> void:
	_solid(STAIR_X0, STAIR_Z, STAIR_X1 - STAIR_X0, 2)
	_build_stairs_up(STAIR2_Z)
	var z0 := STAIR_Z - H / 2.0
	var z1 := STAIR_Z + 2 - H / 2.0
	var x0 := STAIR_X0 - W / 2.0
	var x1 := STAIR_X1 - W / 2.0
	var segs := [
		[Vector3((x0 + x1) / 2.0, 0, z0), Vector3(x1 - x0, 0, 0.1)],
		[Vector3((x0 + x1) / 2.0, 0, z1), Vector3(x1 - x0, 0, 0.1)],
		[Vector3(x0, 0, (z0 + z1) / 2.0), Vector3(0.1, 0, z1 - z0)],
	]
	for seg in segs:
		var p: Vector3 = seg[0]
		var s: Vector3 = seg[1]
		_box(p + Vector3(0, 0.95, 0), Vector3(maxf(s.x, 0.12), 0.08, maxf(s.z, 0.12)), DARK_WOOD, "planks")
		Agent.make_box(cur, p + Vector3(0, 0.45, 0), Vector3(maxf(s.x, 0.05), 0.9, maxf(s.z, 0.05)), Color(0.75, 0.88, 0.95, 0.25))
	# papan pengumuman
	_box(Vector3(x0 + 3, 1.6, -H / 2.0 + 0.08), Vector3(2.4, 1.4, 0.08), Color(0.65, 0.45, 0.28), "planks")
	for i in 5:
		_box(Vector3(x0 + 2.1 + i * 0.45, 1.6 + rng.randf_range(-0.4, 0.4), -H / 2.0 + 0.13), Vector3(0.32, 0.36, 0.02), Color.from_hsv(rng.randf(), 0.3, 1.0))
	_plant(28, 1)
	_plant(36, 0)
	_plant(36, 12)
	_lamp(Vector2i(32, 8), Color(1, 0.9, 0.75), 0.8, 10.0)


func _build_my_office() -> void:
	_rug(4, 3, 10, 8, Color(0.85, 0.72, 0.50))
	# meja besar kamu
	_solid(7, 4, 4, 2)
	var c := _rect_center(7, 4, 4, 2)
	var mahogany := Color(0.55, 0.34, 0.20)
	_box(Vector3(c.x, 0.76, c.z), Vector3(3.6, 0.1, 1.6), mahogany, "planks", 1.0)
	_box(Vector3(c.x - 1.45, 0.36, c.z), Vector3(0.6, 0.72, 1.4), mahogany.darkened(0.15), "planks", 1.0)
	_box(Vector3(c.x + 1.45, 0.36, c.z), Vector3(0.6, 0.72, 1.4), mahogany.darkened(0.15), "planks", 1.0)
	_box(Vector3(c.x, 0.45, c.z + 0.6), Vector3(2.3, 0.5, 0.06), mahogany.darkened(0.15), "planks", 1.0)
	for i in 3:
		_box(Vector3(c.x - 1.45, 0.2 + i * 0.22, c.z + 0.71), Vector3(0.4, 0.04, 0.02), Color(0.9, 0.75, 0.3))
	for mx in [-0.45, 0.45]:
		_box(Vector3(c.x + mx, 0.9, c.z - 0.45), Vector3(0.1, 0.18, 0.1), Color(0.2, 0.2, 0.2))
		_box(Vector3(c.x + mx, 1.15, c.z - 0.45), Vector3(0.8, 0.48, 0.06), Color(0.15, 0.15, 0.17))
		_box(Vector3(c.x + mx, 1.15, c.z - 0.41), Vector3(0.72, 0.4, 0.02), Color(0.40, 0.65, 0.80))
	_box(Vector3(c.x, 0.82, c.z - 0.05), Vector3(0.6, 0.03, 0.2), Color(0.9, 0.9, 0.88))
	_box(Vector3(c.x + 0.5, 0.82, c.z), Vector3(0.12, 0.03, 0.18), Color(0.9, 0.9, 0.88))
	_box(Vector3(c.x - 1.3, 0.85, c.z + 0.1), Vector3(0.36, 0.08, 0.46), Color(0.98, 0.97, 0.92))
	_box(Vector3(c.x, 0.86, c.z + 0.65), Vector3(0.7, 0.12, 0.08), Color(0.85, 0.7, 0.3))
	_cyl(Vector3(c.x + 1.3, 0.87, c.z - 0.3), 0.07, 0.14, Color(0.95, 0.95, 0.92))
	_cyl(Vector3(c.x - 1.4, 0.95, c.z - 0.45), 0.12, 0.3, Color(0.4, 0.7, 0.35), "leaves")
	_cyl(Vector3(c.x + 1.5, 1.05, c.z + 0.3), 0.04, 0.5, Color(0.2, 0.2, 0.2), "metal")
	_cyl(Vector3(c.x + 1.5, 1.3, c.z + 0.3), 0.15, 0.12, Color(0.95, 0.85, 0.5), "cloth")
	# kursi kamu
	var ch := Node3D.new()
	ch.position = _rect_center(8, 3, 2, 1)
	cur.add_child(ch)
	Agent.make_box(ch, Vector3(0, 0.48, 0), Vector3(0.8, 0.14, 0.75), Color(0.35, 0.18, 0.12), "cloth", 2.0)
	Agent.make_box(ch, Vector3(0, 1.0, -0.35), Vector3(0.8, 0.95, 0.14), Color(0.35, 0.18, 0.12), "cloth", 2.0)
	Agent.make_box(ch, Vector3(0, 0.22, 0), Vector3(0.12, 0.44, 0.12), Color(0.2, 0.2, 0.2), "metal")
	_solid(8, 3, 2, 1)
	# kursi tamu & tempat lapor
	_chair(Vector2i(7, 7), PI, Color(0.55, 0.30, 0.25))
	_chair(Vector2i(10, 7), PI, Color(0.55, 0.30, 0.25))
	_add_spot("bos", Vector2i(7, 7), "sit", PI)
	_add_spot("bos", Vector2i(10, 7), "sit", PI)
	_add_spot("bos", Vector2i(8, 7), "stand", PI)
	_add_spot("bos", Vector2i(9, 7), "stand", PI)
	_room_label("MEJA KAMU", 9, 5, true)
	# rak buku & dekorasi
	_bookshelf(1, 0, 4)
	_bookshelf(13, 0, 4)
	_solid(6, 0)
	var gl := _cw(Vector2i(6, 0))
	_box(gl + Vector3(0, 0.5, -0.1), Vector3(0.8, 1.0, 0.6), DARK_WOOD, "planks")
	_cyl(gl + Vector3(0, 1.25, -0.1), 0.25, 0.5, Color(0.45, 0.65, 0.85), "carpet")
	var clock := _cyl(Vector3(9 - W / 2.0, 2.4, -H / 2.0 + 0.08), 0.32, 0.06, Color(0.98, 0.96, 0.9))
	clock.rotation.x = PI / 2
	_painting(Vector3(-W / 2.0 + 0.05, 1.7, 5 - H / 2.0), false, Color(0.55, 0.75, 0.45))
	# sofa & meja tamu
	_solid(0, 8, 1, 4)
	_sofa(_rect_center(0, 8, 1, 4), 4.0, PI / 2, BRAND_INK.lightened(0.15))
	_solid(2, 9, 2, 2)
	var tc := _rect_center(2, 9, 2, 2)
	_box(Vector3(tc.x, 0.35, tc.z), Vector3(1.4, 0.08, 1.4), mahogany, "planks", 1.0)
	_box(Vector3(tc.x, 0.17, tc.z), Vector3(1.0, 0.3, 1.0), DARK_WOOD, "planks", 1.0)
	_cyl(Vector3(tc.x, 0.45, tc.z), 0.15, 0.12, Color(0.95, 0.85, 0.6))
	# akuarium
	_solid(14, 11, 3, 1)
	var aq := _rect_center(14, 11, 3, 1)
	_box(Vector3(aq.x, 0.4, aq.z), Vector3(2.6, 0.8, 0.7), DARK_WOOD, "planks")
	_box(Vector3(aq.x, 1.15, aq.z), Vector3(2.5, 0.7, 0.6), Color(0.40, 0.70, 0.90))
	var fish := [Color(1, 0.55, 0.2), Color(1, 0.9, 0.3)]
	for i in 4:
		_box(Vector3(aq.x - 0.9 + i * 0.6, 1.1 + rng.randf_range(-0.2, 0.2), aq.z + 0.31), Vector3(0.18, 0.1, 0.02), fish[i % 2])
	_plant(0, 0, true)
	_plant(17, 0, true)
	_plant(0, 12, true)
	_plant(17, 6)
	_lamp(Vector2i(9, 5), Color(1, 0.88, 0.7), 1.1, 12.0)


func _build_library() -> void:
	_bookshelf(19, 0, 8)
	_bookshelf(20, 4, 5)
	_bookshelf(20, 7, 5)
	for x in range(21, 24):
		_add_spot("perpus", Vector2i(x, 5), "stand", PI)
	_solid(22, 10, 2, 1)
	var t := _rect_center(22, 10, 2, 1)
	_box(Vector3(t.x, 0.72, t.z), Vector3(1.9, 0.08, 0.9), Color(0.55, 0.38, 0.24), "planks", 1.0)
	_box(Vector3(t.x, 0.36, t.z), Vector3(1.6, 0.7, 0.1), DARK_WOOD, "planks", 1.0)
	_box(Vector3(t.x - 0.3, 0.8, t.z), Vector3(0.4, 0.06, 0.3), Color(0.8, 0.3, 0.3), "cloth")
	_cyl(Vector3(t.x + 0.5, 0.95, t.z), 0.05, 0.4, Color(0.3, 0.6, 0.3), "metal")
	_chair(Vector2i(21, 10), PI / 2, Color(0.45, 0.55, 0.35))
	_chair(Vector2i(24, 10), -PI / 2, Color(0.45, 0.55, 0.35))
	_add_spot("perpus", Vector2i(21, 10), "sit", PI / 2)
	_add_spot("perpus", Vector2i(24, 10), "sit", -PI / 2)
	_beanbag(Vector2i(19, 11), PI / 2, "perpus", Color(0.85, 0.55, 0.30))
	_plant(26, 12)
	_lamp(Vector2i(22, 8), Color(1, 0.9, 0.7), 0.9, 9.0)


func _build_small_meeting() -> void:
	_rug(38.5, 2.5, 5, 6, Color(0.80, 0.75, 0.62), true)
	_round_table(40, 5, "rapat_atas", Color(0.30, 0.45, 0.60))
	_box(Vector3(41 - W / 2.0, 1.6, -H / 2.0 + 0.08), Vector3(2.4, 1.3, 0.08), Color(0.6, 0.45, 0.3), "planks")
	_box(Vector3(41 - W / 2.0, 1.6, -H / 2.0 + 0.12), Vector3(2.2, 1.1, 0.04), Color(0.97, 0.97, 0.95))
	_plant(43, 12)
	_plant(38, 12)
	_lamp(Vector2i(40, 6), Color(1, 0.95, 0.85), 0.8, 8.0)


func _build_terrace() -> void:
	var crops := [Color(0.55, 0.80, 0.40), Color(0.90, 0.25, 0.20), Color(0.95, 0.55, 0.15), Color(0.98, 0.85, 0.30)]
	for i in 4:
		_garden_bed(2 + (i % 2) * 8, 21 + (i / 2) * 4, 6, 2, crops[i])
	for p in [Vector2i(22, 22), Vector2i(28, 26)]:
		_parasol_table(p.x, p.y)
	for x in [35, 38, 41]:
		_deck_chair(Vector2i(x, 28))
	_bench(_cw(Vector2i(20, 28)), PI)
	_solid(19, 28, 3, 1)
	_add_spot("teras", Vector2i(20, 27), "stand", 0.0)
	for c in [Vector2i(0, 19), Vector2i(43, 19), Vector2i(0, 29), Vector2i(43, 29), Vector2i(17, 19), Vector2i(27, 19), Vector2i(34, 21)]:
		_plant(c.x, c.y, true)
	# kolam kecil
	_solid(36, 21, 4, 3)
	var pc := _rect_center(36, 21, 4, 3)
	_box(Vector3(pc.x, 0.18, pc.z), Vector3(3.8, 0.36, 2.8), Color(0.80, 0.76, 0.70), "stone", 1.0)
	_box(Vector3(pc.x, 0.37, pc.z), Vector3(3.3, 0.04, 2.3), Color(0.35, 0.60, 0.80))
	_cyl(Vector3(pc.x + 0.8, 0.4, pc.z - 0.4), 0.3, 0.03, Color(0.4, 0.75, 0.4), "leaves")
	_box(Vector3(pc.x - 0.5, 0.4, pc.z + 0.3), Vector3(0.22, 0.04, 0.1), Color(1, 0.5, 0.2))
	for x in [37, 38]:
		_add_spot("teras", Vector2i(x, 24), "stand", PI)


func _garden_bed(x: int, z: int, w: int, h: int, crop: Color) -> void:
	_solid(x, z, w, h)
	var c := _rect_center(x, z, w, h)
	_box(Vector3(c.x, 0.15, c.z), Vector3(w, 0.3, h), Color(0.62, 0.45, 0.30), "planks", 1.0)
	_box(Vector3(c.x, 0.31, c.z), Vector3(w - 0.2, 0.04, h - 0.2), Color(1, 1, 1), "dirt")
	for i in w:
		for j in h:
			var p := _cw(Vector2i(x + i, z + j))
			_box(Vector3(p.x, 0.45, p.z), Vector3(0.38, 0.25, 0.38), Color(0.35, 0.62, 0.30), "leaves", 2.0)
			_box(Vector3(p.x + 0.08, 0.6, p.z), Vector3(0.18, 0.16, 0.18), crop)
	for i in w:
		_add_spot("teras", Vector2i(x + i, z + h), "stand", PI)


func _parasol_table(x: int, z: int) -> void:
	_solid(x, z)
	var p := _cw(Vector2i(x, z))
	_cyl(Vector3(p.x, 0.72, p.z), 0.6, 0.06, Color(0.95, 0.95, 0.92))
	_cyl(Vector3(p.x, 1.3, p.z), 0.04, 2.6, Color(0.9, 0.9, 0.9), "metal")
	_cyl(Vector3(p.x, 2.5, p.z), 1.4, 0.1, Color(0.95, 0.45, 0.35), "cloth", 8)
	_cyl(Vector3(p.x, 2.58, p.z), 0.9, 0.1, Color(0.98, 0.95, 0.88), "cloth", 8)
	for e in [[Vector2i(x - 1, z), PI / 2], [Vector2i(x + 1, z), -PI / 2]]:
		_chair(e[0], e[1], Color(0.95, 0.95, 0.92))
		_add_spot("teras", e[0], "sit", e[1])


func _deck_chair(cell: Vector2i) -> void:
	var p := _cw(cell)
	_box(Vector3(p.x, 0.3, p.z), Vector3(0.7, 0.1, 1.4), Color(0.3, 0.6, 0.85), "cloth", 2.0)
	var back := _box(Vector3(p.x, 0.55, p.z - 0.75), Vector3(0.7, 0.6, 0.1), Color(0.3, 0.6, 0.85), "cloth", 2.0)
	back.rotation.x = -0.6
	_box(Vector3(p.x, 0.12, p.z), Vector3(0.6, 0.24, 1.2), Color(0.95, 0.95, 0.92), "metal")
	_add_spot("teras", cell, "sit", 0.0, Vector2i(cell.x, cell.y - 1), 0.0)
	_solid(cell.x, cell.y)


# ---------- aset brand (logo, poster, foto tim dari growhaley.com) ----------

var _btex := {}
var _bmat := {}


func _brand_mat(tex_name: String) -> StandardMaterial3D:
	if not _bmat.has(tex_name):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/brand/%s.png" % tex_name)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # logo & poster selalu terbaca jelas
		_bmat[tex_name] = m
	return _bmat[tex_name]


## Gambar tempel (poster/logo/foto) menghadap +z lokal node `parent`.
func _picture(parent: Node3D, pos: Vector3, size: Vector2, tex_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	m.mesh = q
	m.material_override = _brand_mat(tex_name)
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _facing_node(parent: Node3D, pos: Vector3, normal: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = atan2(normal.x, normal.z)
	parent.add_child(n)
	return n


# ---------- papan nama & logo ----------

func _build_signs() -> void:
	# papan monumen di halaman depan, menghadap jalan
	cur = self
	var mp := Vector3(-8.5, 0.0, 18.6)
	_box(mp + Vector3(0, 0.2, 0), Vector3(5.0, 0.4, 1.4), Color(0.80, 0.80, 0.82), "stone")
	_box(mp + Vector3(0, 1.3, 0), Vector3(4.6, 1.8, 0.5), BRAND_INK, "stone")
	_box(mp + Vector3(0, 2.24, 0), Vector3(4.7, 0.08, 0.6), BRAND_BLUE, "metal")
	for s: float in [1.0, -1.0]:
		var n := _facing_node(self, mp + Vector3(0, 1.3, 0.26 * s), Vector3(0, 0, s))
		_picture(n, Vector3.ZERO, Vector2(4.2, 1.4), "sign_ink")
	# lampu sorot kecil di depan papan
	for sx: float in [-1.4, 1.4]:
		_box(mp + Vector3(sx, 0.5, 1.0), Vector3(0.25, 0.2, 0.25), Color(0.25, 0.25, 0.27), "metal")
	# logo besar di dinding barat lobby (di atas sofa)
	cur = floors[0]
	var wn: Node3D = ext_walls[0]["W"]
	var lp := _facing_node(wn, Vector3(-W / 2.0 + 0.03, 2.25, 21.5 - H / 2.0), Vector3(1, 0, 0))
	_picture(lp, Vector3.ZERO, Vector2(3.3, 1.1), "sign_blue")
	# papan logo di atap lantai 3 menghadap selatan
	cur = floors[2]
	var rp := Vector3(-2.0, 3.0, -H / 2.0 + 0.6)
	for sx: float in [-3.6, 3.6]:
		_box(rp + Vector3(sx, 0.8, -0.2), Vector3(0.18, 1.6, 0.18), Color(0.3, 0.3, 0.32), "metal")
	_box(rp + Vector3(0, 2.2, -0.08), Vector3(8.6, 2.9, 0.15), BRAND_INK, "metal")
	var rn := _facing_node(floors[2], rp + Vector3(0, 2.2, 0.0), Vector3(0, 0, 1))
	_picture(rn, Vector3.ZERO, Vector2(8.3, 2.77), "sign_blue")


# ---------- lantai 3: ruang founder ----------

## Tangga dari lantai 2 ke 3, naik dari timur (x=STAIR_X1) ke barat.
func _build_stairs_up(z: int) -> void:
	_solid(STAIR_X0, z, STAIR_X1 - STAIR_X0, 2)
	var steps := 12
	var depth := float(STAIR_X1 - STAIR_X0) / steps
	var rise := FH / steps
	var zc := z + 1.0 - H / 2.0
	for i in steps:
		var x1 := STAIR_X1 - i * depth - W / 2.0
		var h := (i + 1) * rise
		_box(Vector3(x1 - depth / 2.0, h / 2.0, zc), Vector3(depth, h, 2.0), Color(0.86, 0.87, 0.88), "stone", 1.0)
		_box(Vector3(x1 - depth / 2.0, h - 0.02, zc), Vector3(depth + 0.04, 0.05, 2.04), BRAND_BLUE, "metal", 1.0)
	var run := float(STAIR_X1 - STAIR_X0)
	for sz: float in [-1.0, 1.0]:
		var rail := _box(Vector3((STAIR_X0 + STAIR_X1) / 2.0 - W / 2.0, FH / 2.0 + 1.0, zc + sz), Vector3(Vector2(run, FH).length(), 0.08, 0.1), BRAND_INK, "metal")
		rail.rotation.z = -atan2(FH, run)
		var gl := Agent.make_box(cur, Vector3((STAIR_X0 + STAIR_X1) / 2.0 - W / 2.0, FH / 2.0 + 0.5, zc + sz), Vector3(Vector2(run, FH).length(), 0.9, 0.05), Color(0.75, 0.88, 0.95, 0.25))
		gl.rotation.z = -atan2(FH, run)


func _build_floor2() -> void:
	_start_floor(2)
	var D := 18  # kedalaman lantai 3 (hanya separuh utara; selatan tetap teras terbuka)
	var slab := Color(0.88, 0.89, 0.90)
	for r in [[0, 0, STAIR_X0, D], [STAIR_X1, 0, W - STAIR_X1, D], [STAIR_X0, 0, STAIR_X1 - STAIR_X0, STAIR2_Z],
			[STAIR_X0, STAIR2_Z + 2, STAIR_X1 - STAIR_X0, D - STAIR2_Z - 2]]:
		var c := _rect_center(r[0], r[1], r[2], r[3])
		_box(Vector3(c.x, -0.1, c.z), Vector3(r[2], 0.2, r[3]), slab, "stone", 0.5)
	# area tak terpakai (teras di bawah) ditandai solid supaya tidak bisa dipilih
	_solid(0, D, W, H - D)
	_floor_finish(0, 8, 28, 2, Color(0.90, 0.91, 0.92), "tiles", 0.5)
	_floor_finish(34, 0, 2, D, Color(0.90, 0.91, 0.92), "tiles", 0.5)
	_floor_finish(29, 0, 5, STAIR2_Z, Color(0.90, 0.91, 0.92), "tiles", 0.5)
	_floor_finish(29, STAIR2_Z + 2, 5, D - STAIR2_Z - 2, Color(0.90, 0.91, 0.92), "tiles", 0.5)

	_outer_seg("N", 0, W, 3.0)
	_outer_seg("W", 0, D, 3.0)
	_outer_seg("E", 0, D, 3.0)
	for x in [3.5, 10.5, 18.0, 24.5, 32.5, 40.0]:
		_outer_window("N", x)
	for z in [3.5, 14.0]:
		_outer_window("W", z)
		_outer_window("E", z)
	# fasad kaca menghadap teras (sisi selatan lantai 3)
	var sn: Node3D = ext_walls[2]["S"]
	var fz := D - H / 2.0
	Agent.make_box(sn, Vector3(0, 1.5, fz), Vector3(W + WALL_T * 2.0, 3.0, 0.08), Color(0.70, 0.86, 0.95, 0.3))
	Agent.make_box(sn, Vector3(0, 2.95, fz), Vector3(W + WALL_T * 2.0, 0.12, 0.22), BRAND_INK, "metal")
	Agent.make_box(sn, Vector3(0, 0.06, fz), Vector3(W + WALL_T * 2.0, 0.12, 0.22), BRAND_INK, "metal")
	var px := -W / 2.0
	while px <= W / 2.0 + 0.01:
		Agent.make_box(sn, Vector3(px, 1.5, fz), Vector3(0.1, 3.0, 0.16), BRAND_INK, "metal")
		px += 4.0
	# lis atap
	Agent.make_box(sn, Vector3(0, 3.1, fz + 0.2), Vector3(W + 0.6, 0.2, 0.6), BRAND_BLUE, "metal")

	# dinding ruangan (kaca di atas setengah dinding, khas ruang eksekutif)
	_hwall(0, 27, 7, [[6, 7], [20, 21]], true)
	_hwall(0, 27, 10, [[6, 7], [20, 21]], true)
	_vwall(14, 0, 6, [], true)
	_vwall(14, 11, 17, [], true)
	_vwall(28, 0, 6, [], true)
	_vwall(28, 11, 17, [], true)
	_vwall(36, 0, 17, [[3, 4], [12, 13]], true)
	_hwall(37, 43, 8, [], true)

	# 6 ruang founder
	var rects := [Rect2i(0, 0, 14, 7), Rect2i(15, 0, 13, 7), Rect2i(0, 11, 14, 7),
		Rect2i(15, 11, 13, 7), Rect2i(37, 0, 7, 8), Rect2i(37, 9, 7, 9)]
	var doors := [Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 0)]
	for i in FOUNDERS.size():
		_founder_room(FOUNDERS[i], rects[i], doors[i])

	# hall tengah: sofa tunggu, tanaman, logo
	_solid(30, 14, 1, 3)
	_sofa(_rect_center(30, 14, 1, 3), 3.0, PI / 2, BRAND_PINK)
	_solid(32, 15, 2, 1)
	var tc := _rect_center(32, 15, 2, 1)
	_box(Vector3(tc.x, 0.35, tc.z), Vector3(1.6, 0.08, 0.8), Color(0.95, 0.95, 0.96), "stone")
	_box(Vector3(tc.x, 0.17, tc.z), Vector3(1.2, 0.3, 0.5), BRAND_INK, "metal")
	for c in [Vector2i(29, 0), Vector2i(35, 0), Vector2i(35, 17), Vector2i(29, 7)]:
		_plant(c.x, c.y, true)
	var hn := _facing_node(ext_walls[2]["N"], Vector3(32.0 - W / 2.0, 1.7, -H / 2.0 + 0.03), Vector3(0, 0, 1))
	_picture(hn, Vector3.ZERO, Vector2(1.6, 1.6), "logo_square")
	_lamp(Vector2i(32, 12), Color(1, 0.95, 0.85), 0.8, 9.0)
	_room_label("HALL FOUNDER", 32.5, 15.0, false, "Ruang tunggu tamu founder")


## Ruang kerja satu founder: latar dinding warna aksen + kartu foto, meja eksekutif
## menghadap pintu, dua kursi tamu, karpet, tanaman, lampu, berlian penanda.
func _founder_room(info: Array, r: Rect2i, door: Vector2i) -> void:
	var fname: String = info[0]
	var role: String = info[1]
	var key: String = info[2]
	var acc: Color = info[3]
	_floor_finish(r.position.x, r.position.y, r.size.x, r.size.y, acc.lerp(Color(0.92, 0.92, 0.93), 0.72), "carpet", 0.5)
	# sumbu: u = dari dinding belakang menuju pintu, v = menyamping
	var back := -door
	var side := Vector2i(-door.y, door.x)
	var cx := r.position.x + r.size.x / 2
	var cz := r.position.y + r.size.y / 2
	var base := Vector2i(cx, cz)
	if back.x != 0:
		base.x = r.position.x if back.x < 0 else r.end.x - 1
	else:
		base.y = r.position.y if back.y < 0 else r.end.y - 1
	var cell := func(u: int, v: int) -> Vector2i: return base - back * u + side * v
	var face := Vector3(door.x, 0, door.y)  # arah hadap ke pintu
	var yaw_ := atan2(face.x, face.z)
	# karpet
	var rc0: Vector2i = cell.call(1, -2)
	var rc1: Vector2i = cell.call(4, 2)
	var rx := mini(rc0.x, rc1.x)
	var rz := mini(rc0.y, rc1.y)
	_rug(rx, rz, absi(rc1.x - rc0.x) + 1, absi(rc1.y - rc0.y) + 1, acc.lightened(0.15))
	# dinding latar + kartu foto
	var bc: Vector2i = cell.call(0, 0)
	for v in range(-1, 2):
		var sc: Vector2i = cell.call(0, v)
		_solid(sc.x, sc.y)
	var bp := _cw(bc) - face * 0.25
	var bn := _facing_node(cur, bp, face)
	Agent.make_box(bn, Vector3(0, 1.25, -0.05), Vector3(3.0, 2.5, 0.12), acc, "wallpaper", 1.0)
	Agent.make_box(bn, Vector3(0, 2.55, -0.05), Vector3(3.1, 0.1, 0.18), BRAND_INK, "metal")
	_picture(bn, Vector3(0, 1.45, 0.02), Vector2(1.05, 1.4), "team_" + key)
	var nm := Label3D.new()
	nm.text = fname.to_upper()
	nm.font_size = 64
	nm.pixel_size = 0.008
	nm.outline_size = 10
	nm.outline_modulate = BRAND_INK
	nm.position = Vector3(-1.05, 2.25, 0.03)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.modulate = Color(1, 1, 1)
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bn.add_child(nm)
	# kursi founder
	_chair(cell.call(1, 0), yaw_, BRAND_INK)
	# meja eksekutif
	var dc: Vector2i = cell.call(2, 0)
	for v in range(-1, 2):
		var sc: Vector2i = cell.call(2, v)
		_solid(sc.x, sc.y)
	var dn := _facing_node(cur, _cw(dc), face)
	Agent.make_box(dn, Vector3(0, 0.76, 0), Vector3(2.6, 0.08, 1.0), Color(0.96, 0.96, 0.97), "stone")
	Agent.make_box(dn, Vector3(0, 0.38, 0.38), Vector3(2.4, 0.72, 0.08), BRAND_INK, "planks")
	Agent.make_box(dn, Vector3(0, 0.45, 0.43), Vector3(2.2, 0.08, 0.02), acc, "metal")
	for sx: float in [-1.15, 1.15]:
		Agent.make_box(dn, Vector3(sx, 0.38, 0), Vector3(0.1, 0.72, 0.9), BRAND_INK, "planks")
	# monitor (layar menghadap kursi founder)
	Agent.make_box(dn, Vector3(0, 0.9, -0.25), Vector3(0.1, 0.2, 0.1), Color(0.2, 0.2, 0.2), "metal")
	Agent.make_box(dn, Vector3(0, 1.15, -0.25), Vector3(0.95, 0.52, 0.05), Color(0.12, 0.12, 0.13), "metal")
	Agent.make_box(dn, Vector3(0, 1.15, -0.28), Vector3(0.87, 0.44, 0.02), acc.lightened(0.35), "grain")
	Agent.make_box(dn, Vector3(-0.85, 0.82, 0.05), Vector3(0.36, 0.03, 0.26), Color(0.75, 0.76, 0.78), "metal")
	Agent.make_cyl(dn, Vector3(0.9, 0.86, -0.1), 0.06, 0.13, Color(0.97, 0.97, 0.97))
	Agent.make_cyl(dn, Vector3(1.05, 0.95, 0.25), 0.12, 0.3, Color(0.4, 0.7, 0.35), "leaves")
	# papan nama di meja (menghadap pintu)
	Agent.make_box(dn, Vector3(0.5, 0.86, 0.38), Vector3(0.6, 0.14, 0.05), BRAND_INK, "metal")
	var pl := Label3D.new()
	pl.text = fname
	pl.font_size = 40
	pl.pixel_size = 0.003
	pl.position = Vector3(0.5, 0.86, 0.41)
	pl.modulate = Color(1, 0.9, 0.55)
	pl.outline_size = 0
	dn.add_child(pl)
	# kursi tamu
	for v: int in [-1, 1]:
		_chair(cell.call(3, v), yaw_ + PI, acc.darkened(0.15))
	# tanaman & lemari di sudut belakang
	var half := (r.size.y if door.x != 0 else r.size.x) / 2
	var pa: Vector2i = cell.call(0, -half + 1)
	var pb: Vector2i = cell.call(0, half - 1)
	if r.has_point(pa):
		_plant(pa.x, pa.y, true)
	if r.has_point(pb):
		_solid(pb.x, pb.y)
		var cn := _facing_node(cur, _cw(pb), face)
		Agent.make_box(cn, Vector3(0, 0.6, 0), Vector3(0.8, 1.2, 0.5), BRAND_INK.lightened(0.1), "planks")
		for i in 3:
			Agent.make_box(cn, Vector3(-0.2 + i * 0.2, 1.32, 0), Vector3(0.12, 0.24, 0.3), [acc, BRAND_LIGHT, Color(0.95, 0.95, 0.95)][i], "cloth", 2.0)
	_lamp(cell.call(3, 0), Color(1, 0.95, 0.85), 0.7, 8.0)
	var lc := _cw(cell.call(5, 0)) + Vector3(W / 2.0, 0, H / 2.0)
	_room_label("RUANG " + fname.to_upper(), lc.x, lc.z, false, "%s · Founder\n%s" % [fname, role])


# ---------- ornamen dinding ----------

const ORN_POSTERS := ["p_project", "p_bisnis", "p_industri", "p_tahun", "p_design", "p_aset"]
const ORN_QUOTES := ["q_ditemukan", "q_percaya", "q_hasil", "q_kolab"]


func _cell_free(f: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return false
	return not grids[f].is_point_solid(c) and not _wall_cells[f].has(c)


## Hiasan kantor di dinding: poster angka & kutipan Growhaley, jam, rak tanaman, papan tulis.
func _decorate_walls() -> void:
	var k := 0
	# dinding dalam (setengah tinggi): hiasan kecil di kedua sisi bila depannya kosong
	for sg in _deco_segs:
		var f: int = sg[0]
		var n: int = sg[3]
		var horiz: bool = sg[4]
		if n < 3:
			continue
		cur = floors[f]
		var i := 1
		while i < n - 1:
			var wc := Vector2i(sg[1] + i, sg[2]) if horiz else Vector2i(sg[1], sg[2] + i)
			for s: int in [-1, 1]:
				var nrm := Vector2i(0, s) if horiz else Vector2i(s, 0)
				if not _cell_free(f, wc + nrm) or not _cell_free(f, wc + nrm * 2):
					continue
				var p := _cw(wc) + Vector3(nrm.x, 0, nrm.y) * 0.12
				_ornament(cur, p, Vector3(nrm.x, 0, nrm.y), k, true)
				k += 1
			i += 4
	# dinding luar (tinggi penuh): di sela-sela jendela
	var full := {0: [["N", W], ["S", W], ["W", H], ["E", H]], 1: [["N", W], ["W", 18], ["E", 18]], 2: [["N", W], ["W", 18], ["E", 18]]}
	for f in full:
		cur = floors[f]
		for sd in full[f]:
			var side: String = sd[0]
			var lim: int = sd[1]
			var wins: Array = _windows.get("%d:%s" % [f, side], [])
			var a := 2
			while a < lim - 2:
				var along := a + 0.5
				var ok := true
				for wv in wins:
					if absf(along - wv[0]) < wv[1] / 2.0 + 1.2:
						ok = false
				if f == 0 and side == "S" and along > 3.0 and along < 9.0:
					ok = false  # pintu masuk lobby
				var inner := Vector2i(a, 0)
				var nrm := Vector3(0, 0, 1)
				match side:
					"S":
						inner = Vector2i(a, H - 1)
						nrm = Vector3(0, 0, -1)
					"W":
						inner = Vector2i(0, a)
						nrm = Vector3(1, 0, 0)
					"E":
						inner = Vector2i(W - 1, a)
						nrm = Vector3(-1, 0, 0)
				if ok and _cell_free(f, inner):
					var pos := _side_place(side, along, 0.0, WALL_T / 2.0 + 0.02)
					_ornament(ext_walls[f][side], pos, nrm, k, false)
					k += 1
					a += 4
				else:
					a += 1


func _ornament(parent: Node3D, pos: Vector3, nrm: Vector3, k: int, low: bool) -> void:
	var n := _facing_node(parent, pos, nrm)
	var y := 1.0 if low else 1.75
	match k % 5:
		0, 3:
			# poster angka (potret)
			var t: String = ORN_POSTERS[(k / 5 + k) % ORN_POSTERS.size()]
			var sz := Vector2(0.5, 0.66) if low else Vector2(0.75, 1.0)
			Agent.make_box(n, Vector3(0, y, 0.01), Vector3(sz.x + 0.08, sz.y + 0.08, 0.03), BRAND_INK, "metal")
			_picture(n, Vector3(0, y, 0.03), sz, t)
		1:
			# kutipan (lanskap)
			var t: String = ORN_QUOTES[(k / 5) % ORN_QUOTES.size()]
			var sz := Vector2(0.8, 0.5) if low else Vector2(1.3, 0.81)
			Agent.make_box(n, Vector3(0, y, 0.01), Vector3(sz.x + 0.08, sz.y + 0.08, 0.03), Color(0.95, 0.95, 0.96), "metal")
			_picture(n, Vector3(0, y, 0.03), sz, t)
		2:
			# jam dinding
			var c := Agent.make_cyl(n, Vector3(0, y + 0.15, 0.03), 0.24, 0.05, Color(0.97, 0.97, 0.97))
			c.rotation.x = PI / 2.0
			var r := Agent.make_cyl(n, Vector3(0, y + 0.15, 0.02), 0.27, 0.04, BRAND_INK, "metal")
			r.rotation.x = PI / 2.0
			Agent.make_box(n, Vector3(0, y + 0.22, 0.065), Vector3(0.025, 0.15, 0.01), BRAND_INK)
			var hand := Agent.make_box(n, Vector3(0.05, y + 0.15, 0.065), Vector3(0.12, 0.025, 0.01), BRAND_PINK)
			hand.rotation.z = 0.5
		4:
			if low:
				# rak kecil + pot tanaman
				Agent.make_box(n, Vector3(0, y - 0.15, 0.1), Vector3(0.7, 0.04, 0.2), Color(0.95, 0.95, 0.96), "planks")
				Agent.make_box(n, Vector3(-0.15, y - 0.03, 0.1), Vector3(0.16, 0.2, 0.16), BRAND_BLUE, "metal")
				Agent.make_box(n, Vector3(-0.15, y + 0.13, 0.1), Vector3(0.24, 0.18, 0.2), Color(0.4, 0.7, 0.35), "leaves")
				Agent.make_box(n, Vector3(0.18, y - 0.05, 0.1), Vector3(0.12, 0.16, 0.12), BRAND_PINK, "metal")
			else:
				# papan tulis kecil dengan catatan tempel
				Agent.make_box(n, Vector3(0, y, 0.02), Vector3(1.4, 0.9, 0.04), BRAND_INK, "metal")
				Agent.make_box(n, Vector3(0, y, 0.045), Vector3(1.3, 0.8, 0.02), Color(0.97, 0.97, 0.98))
				for i in 4:
					var col: Color = [BRAND_LIGHT, BRAND_PINK.lightened(0.4), Color(1, 0.9, 0.5), BRAND_PALE][i]
					Agent.make_box(n, Vector3(-0.45 + i * 0.3, y + 0.15 - (i % 2) * 0.3, 0.06), Vector3(0.2, 0.2, 0.01), col)


# ---------- karakter ----------

func _build_agents() -> void:
	for i in range(AGENTS.size()):
		var a := Agent.new()
		a.setup(AGENTS[i][0], AGENTS[i][1], AGENTS[i][2])
		a.title = AGENTS[i][3]
		a.add_plumbob()
		var c := Vector2i(3 + i, 21)
		a.position = cell_to_world(c)
		a.dest_cell = c
		a.think = 1.0 + i * 0.7
		a.need_task.connect(_on_need_task)
		add_child(a)
		agents.append(a)
	select(agents[0])
	# berlian hijau melayang di atas tiap ruangan (nama muncul saat di-hover)
	for wl in world_labels:
		var small: bool = wl["small"]
		var bob := Agent.make_plumbob(self, 0.5 if small else 0.75,
			Color(1.0, 0.82, 0.25) if small else Color(0.25, 0.95, 0.35))
		bob.position = wl["pos"] + Vector3(0, -0.4, 0)
		wl["bob"] = bob


# ---------- gerak & perintah ----------

func _stair_end(f: int) -> Vector3:
	var zc := STAIR_Z + 0.5 - H / 2.0
	if f == 0:
		return Vector3(STAIR_X0 - W / 2.0, 0, zc)
	return Vector3(STAIR_X1 - W / 2.0, FH, zc)


func _grid_path(f: int, from: Vector2i, to: Vector2i) -> Array:
	var pts := []
	for c in grids[f].get_id_path(from, to):
		pts.append(cell_to_world(c, f))
	return pts


func send(a: Agent, spot: Dictionary, arrive_status: String) -> bool:
	var tf: int = spot["floor"]
	var approach: Vector2i = spot["approach"]
	var target: Vector2i = approach if approach != NONE else spot["cell"]
	var sf := a.floor_index()
	var pts := []
	var start: Vector2i
	if a.position.y > 0.05 and a.position.y < FH - 0.05:
		# sedang di tangga: selesaikan dulu ke ujung terdekat
		pts.append(_stair_end(sf))
		start = LANDING[sf]
	else:
		start = nearest_free(world_to_cell(a.position), sf)
	if sf == tf:
		var p := _grid_path(sf, start, target)
		if p.is_empty():
			return false
		pts.append_array(p)
	else:
		var p1 := _grid_path(sf, start, LANDING[sf])
		var p2 := _grid_path(tf, LANDING[tf], target)
		if p1.is_empty() or p2.is_empty():
			return false
		pts.append_array(p1)
		pts.append(_stair_end(sf))
		pts.append(_stair_end(tf))
		pts.append_array(p2)
	var yaw_: float = spot["yaw"]
	if spot["kind"] == "sit":
		var p := cell_to_world(spot["cell"], tf) + Vector3(sin(yaw_), 0, cos(yaw_)) * float(spot["shift"])
		if approach != NONE:
			pts.append(p)
		else:
			pts[pts.size() - 1] = p
	a.dest_cell = spot["cell"]
	a.dest_floor = tf
	a.begin_move(pts, spot["kind"], yaw_, arrive_status)
	return true


func pick_spot(place: String, a: Agent) -> Dictionary:
	var taken := []
	for o in agents:
		if o != a:
			taken.append(Vector3i(o.dest_cell.x, o.dest_cell.y, o.dest_floor))
	var spots: Array = places[place]
	var free := spots.filter(func(s): return not taken.has(Vector3i(s["cell"].x, s["cell"].y, s["floor"])))
	if free.is_empty():
		free = spots
	return free[rng.randi() % free.size()]


func desk_of(a: Agent) -> Dictionary:
	return desk_spots[agents.find(a) % desk_spots.size()]


func at_desk(a: Agent) -> bool:
	var d := desk_of(a)
	return a.sitting and a.dest_floor == d["floor"] and a.dest_cell == d["cell"]


func go_place(a: Agent, place: String) -> bool:
	if place == "desk":
		return send(a, desk_of(a), a.ext_status if a.has_ext() else "bekerja")
	return send(a, pick_spot(place, a), PLACE_STATUS[place])


func _on_need_task(a: Agent) -> void:
	if not a.ext_status.is_empty() and not a.has_ext():
		a.ext_status = ""
		a.set_status("bekerja")
	if a.has_ext():
		if at_desk(a):
			if a.status != a.ext_status:
				a.set_status(a.ext_status)
			a.think = 5.0
		elif not go_place(a, "desk"):
			a.think = 3.0
		return
	if a.status in WORK_TASKS:
		if rng.randf() < 0.3:
			var p: String = WANDER.pick_random()
			if go_place(a, p):
				return
		a.set_status(WORK_TASKS.pick_random())
		a.think = rng.randf_range(6.0, 12.0)
	else:
		if not go_place(a, "desk"):
			a.think = 3.0


func find_agent(agent_name: String) -> Agent:
	for a in agents:
		if a.agent_name.to_lower() == agent_name.to_lower():
			return a
	return null


## Status nyata dari bot (lewat bridge). text kosong = hapus.
func set_real_status(agent_name: String, text: String, ttl: float) -> void:
	var a := find_agent(agent_name)
	if a == null:
		return
	if text.is_empty():
		a.ext_status = ""
		a.set_status("bekerja" if a.sitting else "idle")
		a.think = 0.5
		return
	a.ext_status = text
	a.ext_until = Agent.now() + ttl
	if at_desk(a) and not a.is_moving():
		a.set_status(text)
	else:
		go_place(a, "desk")


func show_feedback(text: String) -> void:
	feedback.text = text


func _build_bridge() -> void:
	if OS.has_feature("web"):
		# versi web (online): karakter jalan sebagai NPC otomatis, tanpa relay AI di laptop
		bridge_label.text = "Mode online · karyawan NPC"
		return
	bridge = Bridge.new()
	bridge.main = self
	bridge.state_changed.connect(func(t): bridge_label.text = t)
	add_child(bridge)


## Titik masuk perintah teks (UI, bridge Telegram/WA). Mengembalikan balasan.
func run_command(text: String) -> String:
	var t := text.to_lower().strip_edges()
	if t.is_empty():
		return ""
	var targets := []
	if t.contains("semua") or t.contains("all"):
		targets = agents.duplicate()
	else:
		for a in agents:
			if t.contains(a.agent_name.to_lower()):
				targets.append(a)
	if targets.is_empty() and selected:
		targets.append(selected)
	if targets.is_empty():
		return "Pilih karakter dulu atau sebut namanya."

	if t.contains("stop") or t.contains("diam"):
		for a in targets:
			a.stop()
		return "OK, berhenti."

	var place := ""
	for entry in PLACE_WORDS:
		for w in entry[1]:
			if t.contains(w):
				place = entry[0]
				break
		if not place.is_empty():
			break
	if place.is_empty():
		return "Tujuan tidak dikenal. Coba: pantry, meeting, lounge, lobby, server, meja, teras, perpus, rapat atas, lapor ke aku."
	var names := []
	for a in targets:
		if go_place(a, place):
			a.think = 20.0
			names.append(a.agent_name)
	if names.is_empty():
		return "Tidak ada jalan ke sana."
	return "%s -> %s" % [", ".join(names), place]


# ---------- kamera & input ----------

func set_view_floor(f: int) -> void:
	view_floor = clampi(f, 0, NFLOORS - 1)
	floors[1].visible = view_floor >= 1
	floors[2].visible = view_floor >= 2
	t_pivot.y = view_floor * FH
	for i in floor_btns.size():
		floor_btns[i].set_pressed_no_signal(i == view_floor)


func select(a: Agent) -> void:
	if selected:
		selected.set_selected(false)
	selected = a
	if a:
		a.set_selected(true)


func _ground_point(screen_pos: Vector2) -> Variant:
	var sp := _to_svp(screen_pos)
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.001:
		return null
	var t := (view_floor * FH - o.y) / d.y
	if t < 0.0:
		return null
	return o + d * t


## Sentuhan (HP/tablet). 1 jari = mouse kiri (diemulasi Godot): ketuk = klik, geser = putar.
## 2 jari: cubit = zoom ke titik tengah jari, geser bersama = geser kamera.
var _touches := {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO


func _touch_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
	elif e is InputEventScreenDrag:
		if not _touches.has(e.index):
			return
		_touches[e.index] = e.position
	else:
		return
	if _touches.size() < 2:
		_pinch_dist = 0.0
		return
	# dua jari: batalkan klik/putar dari jari pertama
	_ldown = false
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var dist := maxf(a.distance_to(b), 1.0)
	var mid := (a + b) / 2.0
	if _pinch_dist > 0.0 and e is InputEventScreenDrag:
		var old := t_zoom
		t_zoom = clampf(t_zoom * _pinch_dist / dist, 6.0, 75.0)
		var gp = _ground_point(mid)
		if gp != null and follow == null:
			var k := 1.0 - t_zoom / old
			t_pivot.x += (gp.x - t_pivot.x) * k
			t_pivot.z += (gp.z - t_pivot.z) * k
		var rel := mid - _pinch_mid
		if rel.length() > 0.5:
			follow = null
			t_pivot += Vector3(-rel.x, 0, -rel.y).rotated(Vector3.UP, t_yaw) * t_zoom * 0.0022
	_pinch_dist = dist
	_pinch_mid = mid


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_touch_input(e)
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_ldown = true
				_drag = 0.0
			elif _ldown:
				_ldown = false
				if _drag < 6.0:
					_click(e.position)
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var old := t_zoom
			t_zoom = clampf(t_zoom * (0.88 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), 6.0, 75.0)
			var gp = _ground_point(e.position)
			if gp != null and follow == null:
				var k := 1.0 - t_zoom / old
				t_pivot.x += (gp.x - t_pivot.x) * k
				t_pivot.z += (gp.z - t_pivot.z) * k
	elif e is InputEventMouseMotion:
		if (e.button_mask & MOUSE_BUTTON_MASK_LEFT) and _ldown and _touches.size() < 2:
			_drag += e.relative.length()
			if _drag >= 6.0:
				t_yaw -= e.relative.x * 0.008
				t_pitch = clampf(t_pitch - e.relative.y * 0.006, -1.45, -0.25)
		elif e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			follow = null
			t_pivot += Vector3(-e.relative.x, 0, -e.relative.y).rotated(Vector3.UP, t_yaw) * t_zoom * 0.0022
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ENTER, KEY_SLASH:
				cmd_input.grab_focus()
				get_viewport().set_input_as_handled()
			KEY_H:
				toggle_roster()
			KEY_P:
				cycle_pixel_detail()
			KEY_F:
				if selected:
					focus_agent(selected)
			KEY_1:
				set_view_floor(0)
			KEY_2:
				set_view_floor(1)
			KEY_3:
				set_view_floor(2)
			KEY_PAGEUP:
				set_view_floor(view_floor + 1)
			KEY_PAGEDOWN:
				set_view_floor(view_floor - 1)


## Karakter di bawah kursor (atau null).
func _pick_agent(pos: Vector2) -> Agent:
	var sp := _to_svp(pos)
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var best: Agent = null
	var best_d := 0.9
	for a in agents:
		if not a.visible:
			continue
		var p := a.global_position + Vector3(0, 0.8, 0)
		var t := (p - o).dot(d)
		if t < 0.0:
			continue
		var dist := (o + d * t).distance_to(p)
		if dist < best_d:
			best_d = dist
			best = a
	return best


## Kursor pecut saat di atas karakter; versi "terlecut" sebentar setelah klik.
var _hover_agent: Agent = null
var _crack_t := 0.0
var _cursor_state := ""


const CRACK_TIME := 0.42
var _tip: PanelContainer
var _tip_title: Label
var _tip_sub: Label
var _hover_room = null  # entri world_labels yang sedang di-hover
var _whip_sprite: TextureRect
var _fx_root: Control
var _whip_t := 0.0


func _build_whip_cursor() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	# balon komik di atas panel UI, di bawah pecut
	_fx_root = Control.new()
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_fx_root)
	_tip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.13, 0.93)
	sb.border_color = Color(0.35, 0.95, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 7
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	_tip.add_child(vb)
	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 17)
	_tip_title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	vb.add_child(_tip_title)
	_tip_sub = Label.new()
	_tip_sub.add_theme_font_size_override("font_size", 13)
	_tip_sub.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	vb.add_child(_tip_sub)
	cl.add_child(_tip)
	_whip_sprite = TextureRect.new()
	_whip_sprite.texture = Fx.whip_texture(false)
	_whip_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_whip_sprite.size = Vector2.ONE * Fx.WHIP_SIZE
	_whip_sprite.pivot_offset = Fx.WHIP_GRIP
	_whip_sprite.visible = false
	cl.add_child(_whip_sprite)
	Fx.whip_texture(true)  # siapkan juga versi terlecut


## Ayunan saat melecut: tarik ke belakang, hentak ke depan, kembali tenang.
func _whip_swing(t: float) -> float:
	if t < 0.12:
		return lerpf(0.0, -0.55, t / 0.12)
	if t < 0.19:
		return lerpf(-0.55, 0.32, (t - 0.12) / 0.07)
	return lerpf(0.32, 0.0, minf(1.0, (t - 0.19) / 0.23)) * cos((t - 0.19) * 30.0)


func _update_cursor(d: float) -> void:
	if _crack_t > 0.0:
		_crack_t = maxf(0.0, _crack_t - d)
	_whip_t += d
	var mouse := get_viewport().get_mouse_position()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	_hover_agent = null if over_ui else _pick_agent(mouse)
	var show := _crack_t > 0.0 or _hover_agent != null
	var want := "whip" if show else ""
	if want != _cursor_state:
		_cursor_state = want
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if show else Input.MOUSE_MODE_VISIBLE
		_whip_sprite.visible = show
	if not show:
		return
	var ct := CRACK_TIME - _crack_t
	var cracking := _crack_t > 0.0
	_whip_sprite.texture = Fx.whip_texture(cracking and ct > 0.12 and ct < 0.3)
	_whip_sprite.rotation = _whip_swing(ct) if cracking else sin(_whip_t * 3.0) * 0.05
	# ujung pecut tepat di posisi mouse (saat tidak berayun)
	_whip_sprite.position = mouse - Fx.WHIP_TIP


## Ruangan yang berliannya ada di dekat kursor (atau null).
func _pick_room(mouse: Vector2):
	var best = null
	var best_d := 30.0
	for wl in world_labels:
		var bob: Node3D = wl["bob"]
		if not bob.visible or cam.is_position_behind(bob.global_position):
			continue
		var p := cam.unproject_position(bob.global_position) * Vector2(1280.0 / svp.size.x, 720.0 / svp.size.y)
		var dd := p.distance_to(mouse)
		if dd < best_d:
			best_d = dd
			best = wl
	return best


## Kotak info di samping kursor: nama + jabatan karakter, atau nama ruangan.
func _update_tooltip() -> void:
	var mouse := get_viewport().get_mouse_position()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	for a in agents:
		a.hovered = a == _hover_agent
	_hover_room = null
	if _hover_agent == null and not over_ui:
		_hover_room = _pick_room(mouse)
	if _hover_agent:
		var a := _hover_agent
		_tip_title.text = a.agent_name
		_tip_sub.text = "Jabatan: %s
%s  ·  %s" % [a.title, room_of(a), a.status]
	elif _hover_room != null:
		_tip_title.text = _hover_room["name"]
		var rs: String = _hover_room["sub"]
		_tip_sub.text = ("%s\n" % rs if rs != "" else "") + "Lantai %d" % (_hover_room["floor"] + 1)
	else:
		_tip.visible = false
		return
	_tip.visible = true
	_tip.reset_size()
	var pos := mouse + Vector2(22, -14)
	if pos.x + _tip.size.x > 1270.0:
		pos.x = mouse.x - _tip.size.x - 22.0
	_tip.position = pos


## Cetas! pecut melecut, balon komik muncul di atas kepala karakter.
func whip(a: Agent) -> void:
	_crack_t = CRACK_TIME
	await get_tree().create_timer(0.14).timeout  # tepat saat pecut menghentak
	a.poke()
	var head := a.global_position + Vector3(0, 2.1, 0)
	if not cam.is_position_behind(head):
		var p := cam.unproject_position(head) * Vector2(1280.0 / svp.size.x, 720.0 / svp.size.y)
		Fx.comic_burst(_fx_root, p + Vector2(randf_range(40, 70), -50), "CETAS!")


func _click(pos: Vector2) -> void:
	var best := _pick_agent(pos)
	if best:
		select(best)
		whip(best)
		return
	if view_floor == 2:
		show_feedback("Lantai 3 khusus ruang founder (hanya untuk dilihat)")
		return
	var gp = _ground_point(pos)
	if gp == null or selected == null:
		return
	var c := nearest_free(world_to_cell(gp), view_floor)
	_ripple(cell_to_world(c, view_floor))
	var spot := {"cell": c, "floor": view_floor, "kind": "stand", "yaw": selected.rotation.y, "approach": NONE, "shift": 0.0}
	if send(selected, spot, "sesuai perintah"):
		selected.think = 15.0


func _update_camera(d: float) -> void:
	var k := 1.0 - exp(-10.0 * d)
	t_pivot.x = clampf(t_pivot.x, -W / 2.0 - 30, W / 2.0 + 30)
	t_pivot.z = clampf(t_pivot.z, -H / 2.0 - 15, H / 2.0 + 28)
	pivot.position = pivot.position.lerp(t_pivot, k)
	yaw = lerp_angle(yaw, t_yaw, k)
	pitch = lerpf(pitch, t_pitch, k)
	zoom = lerpf(zoom, t_zoom, k)
	pivot.rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, zoom)
	cam.near = clampf(zoom * 0.015, 0.1, 1.0)
	town.update_occlusion(cam.global_position, pivot.global_position)
	# sembunyikan dinding luar yang menghalangi kamera
	var cd := Vector3(sin(yaw), 0, cos(yaw))
	for f in NFLOORS:
		for sd in SIDE_N:
			var n: Node3D = ext_walls[f][sd]
			var nv: Vector3 = SIDE_N[sd]
			n.visible = nv.dot(cd) < 0.3


# ---------- UI ----------

func _make_theme() -> Theme:
	var th := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.13, 0.9)
	sb.border_color = BRAND_LIGHT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	th.set_stylebox("panel", "PanelContainer", sb)
	th.set_stylebox("normal", "LineEdit", sb)
	var sbf := sb.duplicate() as StyleBoxFlat
	sbf.border_color = Color(1, 0.95, 0.6)
	th.set_stylebox("focus", "LineEdit", sbf)
	var bn := sb.duplicate() as StyleBoxFlat
	bn.set_content_margin_all(5)
	th.set_stylebox("normal", "Button", bn)
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = Color(0.16, 0.34, 0.48, 0.95)
	th.set_stylebox("hover", "Button", bh)
	var bp := bn.duplicate() as StyleBoxFlat
	bp.bg_color = Color(BRAND_BLUE, 0.95)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("hover_pressed", "Button", bp)
	th.set_color("font_color", "Label", Color(1, 0.96, 0.86))
	th.set_color("font_outline_color", "Label", Color(0.2, 0.12, 0.06))
	th.set_constant("outline_size", "Label", 4)
	th.set_font_size("font_size", "Label", 14)
	th.set_font_size("font_size", "Button", 14)
	th.set_font_size("font_size", "LineEdit", 15)
	return th


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(overlay)
	for wl in world_labels:
		overlay.add_child(wl["label"])

	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	cl.add_child(ui)

	var help := Label.new()
	help.text = "Klik kiri: pilih/jalan  ·  Tahan kiri + geser: putar  ·  Tahan kanan + geser: geser  ·  Scroll: zoom  ·  1/2/3 atau PgUp/PgDn: lantai  ·  Q/E: putar  ·  F: ikuti  ·  H: panel tim  ·  P: tampilan Retro/HD  ·  Enter: perintah"
	help.add_theme_font_size_override("font_size", 12)
	help.position = Vector2(12, 6)
	ui.add_child(help)

	# panel tim: satu baris per karakter, klik = kamera fokus & sorot karakter
	var sp := PanelContainer.new()
	sp.position = Vector2(10, 28)
	ui.add_child(sp)
	var roster := VBoxContainer.new()
	roster.add_theme_constant_override("separation", 2)
	sp.add_child(roster)
	roster_toggle = Button.new()
	roster_toggle.flat = true
	roster_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	roster_toggle.focus_mode = Control.FOCUS_NONE
	roster_toggle.add_theme_font_size_override("font_size", 11)
	roster_toggle.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	roster_toggle.pressed.connect(toggle_roster)
	roster.add_child(roster_toggle)
	roster_rows = VBoxContainer.new()
	roster_rows.add_theme_constant_override("separation", 2)
	roster.add_child(roster_rows)
	_update_roster_title()
	for a in agents:
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(300, 22)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(focus_agent.bind(a))
		var dot := ColorRect.new()
		dot.color = a.shirt_color
		dot.position = Vector2(4, 6)
		dot.size = Vector2(10, 10)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
		roster_rows.add_child(b)
		roster_buttons[a] = b

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_right = -10
	right.offset_top = 28
	ui.add_child(right)
	var fb := HBoxContainer.new()
	right.add_child(fb)
	for i in NFLOORS:
		var b := Button.new()
		b.text = "Lantai %d" % (i + 1) if i < 2 else "Lantai 3 · Founder"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_view_floor.bind(i))
		fb.add_child(b)
		floor_btns.append(b)
	bridge_label = Label.new()
	bridge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bridge_label.add_theme_font_size_override("font_size", 12)
	right.add_child(bridge_label)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.offset_left = 10
	vb.offset_right = -10
	vb.offset_bottom = -10
	ui.add_child(vb)
	feedback = Label.new()
	vb.add_child(feedback)
	cmd_input = LineEdit.new()
	cmd_input.placeholder_text = "Ketik perintah lalu Enter...  (contoh: 'Sales lapor ke aku', 'semua ke teras', 'Admin ke perpus')"
	cmd_input.text_submitted.connect(_on_submit)
	vb.add_child(cmd_input)
	if OS.has_feature("web"):
		# versi web: panel tim, lantai, perintah & bantuan pindah ke halaman HTML di luar bingkai
		help.visible = false
		sp.visible = false
		right.visible = false
		vb.visible = false


# ---------- jembatan ke halaman web (panel HTML di kiri-kanan bingkai) ----------

var _js_cb: JavaScriptObject


func _setup_web_bridge() -> void:
	if not OS.has_feature("web"):
		return
	_js_cb = JavaScriptBridge.create_callback(_on_js_command)
	var win := JavaScriptBridge.get_interface("window")
	win.ovCommand = _js_cb
	_push_web_state()


func _on_js_command(args: Array) -> void:
	var cmd := str(args[0]) if args.size() > 0 else ""
	var arg := str(args[1]) if args.size() > 1 else ""
	match cmd:
		"focus":
			var a := find_agent(arg)
			if a:
				focus_agent(a)
		"floor":
			follow = null
			set_view_floor(int(arg))
		"pixel":
			_pix_i = clampi(int(arg), 0, PIXEL_LINES.size() - 1)
			_apply_pixel_mode()
		"room":
			for wl in world_labels:
				if str(wl["name"]).to_lower() == ("ruang " + arg).to_lower():
					follow = null
					set_view_floor(wl["floor"])
					var p: Vector3 = wl["pos"]
					t_pivot = Vector3(p.x, wl["floor"] * FH, p.z)
					t_zoom = 13.0
					show_feedback("Ruang %s · %s" % [arg, str(wl["sub"]).get_slice("
", 1)])
		"run":
			feedback.text = run_command(arg)
	_push_web_state()


func _push_web_state() -> void:
	var list := []
	for a in agents:
		list.append({"name": a.agent_name, "title": a.title, "room": room_of(a), "status": a.status,
			"color": a.shirt_color.to_html(false)})
	var st := {"agents": list, "floor": view_floor, "pixel": _pix_i, "feedback": feedback.text,
		"selected": selected.agent_name if selected else "", "online": bridge_label.text}
	JavaScriptBridge.eval("window.ovUpdate && window.ovUpdate(%s)" % JSON.stringify(st), true)


func _on_submit(text: String) -> void:
	feedback.text = run_command(text)
	cmd_input.clear()
	cmd_input.release_focus()


func _place_label(l: Label, world: Vector3, show: bool) -> void:
	if not show or cam.is_position_behind(world):
		l.visible = false
		return
	var p := cam.unproject_position(world) * Vector2(1280.0 / svp.size.x, 720.0 / svp.size.y)
	l.visible = true
	l.reset_size()
	l.position = Vector2(p.x - l.size.x / 2.0, p.y - l.size.y)


## Kamera meluncur ke karakter, zoom mendekat, lalu terus mengikutinya sampai kamera digeser.
func focus_agent(a: Agent) -> void:
	select(a)
	a.poke()
	follow = a
	set_view_floor(a.floor_index())
	t_zoom = minf(t_zoom, 14.0)


## Lipat / buka panel TIM (tombol judul panel atau tombol H).
func toggle_roster() -> void:
	roster_rows.visible = not roster_rows.visible
	_update_roster_title()
	var panel: Control = roster_rows.get_parent().get_parent()
	panel.reset_size.call_deferred()


func _update_roster_title() -> void:
	roster_toggle.text = ("[–] TIM  (klik nama untuk lihat · H: sembunyikan)" if roster_rows.visible
		else "[+] TIM  (%d)  · H: tampilkan" % agents.size())


## Riak lingkaran di lantai, menandai titik tujuan klik.
func _ripple(p: Vector3) -> void:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.32
	t.outer_radius = 0.42
	t.rings = 16
	t.ring_segments = 4
	m.mesh = t
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.92, 0.4, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.position = p + Vector3(0, 0.08, 0)
	m.scale = Vector3(0.4, 0.3, 0.4)
	add_child(m)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3(2.2, 0.3, 2.2), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(m.queue_free)


## Nama ruangan terdekat dari posisi karakter (di lantai yang sama).
func room_of(a: Agent) -> String:
	var f := a.floor_index()
	var best := "-"
	var best_d := INF
	for r in rooms:
		if r["floor"] != f:
			continue
		var dd := Vector2(a.position.x - r["x"], a.position.z - r["z"]).length_squared()
		if dd < best_d:
			best_d = dd
			best = r["name"]
	return "Lt %d %s" % [f + 1, best]


func _process(d: float) -> void:
	var v := Vector2.ZERO
	if not cmd_input.has_focus():
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
			v.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
			v.x += 1
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
			v.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
			v.y += 1
		if Input.is_key_pressed(KEY_Q):
			t_yaw += 1.5 * d
		if Input.is_key_pressed(KEY_E):
			t_yaw -= 1.5 * d
	_update_cursor(d)
	if v != Vector2.ZERO:
		follow = null
		t_pivot += Vector3(v.x, 0, v.y).normalized().rotated(Vector3.UP, t_yaw) * t_zoom * 0.8 * d
	_update_camera(d)

	if follow:
		if follow.floor_index() != view_floor:
			set_view_floor(follow.floor_index())
		t_pivot = Vector3(follow.position.x, view_floor * FH, follow.position.z)
	for a in agents:
		a.visible = a.floor_index() <= view_floor
	for wl in world_labels:
		var bob: Node3D = wl["bob"]
		bob.visible = wl["floor"] == view_floor
		var base: Vector3 = wl["pos"] + Vector3(0, -0.4, 0)
		bob.position = base + Vector3(0, sin(Time.get_ticks_msec() / 400.0 + base.x) * 0.1, 0)
		bob.rotation.y += d * 1.2
		var sc := 1.35 if is_same(wl, _hover_room) else 1.0
		bob.scale = bob.scale.lerp(Vector3.ONE * sc, minf(1.0, 12.0 * d))
		wl["label"].visible = false
	_update_tooltip()

	_status_timer -= d
	if _status_timer <= 0.0:
		_status_timer = 0.3
		if OS.has_feature("web"):
			_push_web_state()
		for a in agents:
			var b: Button = roster_buttons[a]
			b.text = "    %s  ·  %s  ·  %s%s" % [a.agent_name, room_of(a), a.status, "  (nyata)" if a.showing_ext() else ""]
			var col := Color(1, 0.92, 0.45) if a == selected else (Color(0.6, 1.0, 0.55) if a.showing_ext() else Color(1, 0.97, 0.9))
			b.add_theme_color_override("font_color", col)
			b.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.45))


# ---------- tes: tangkap layar ----------
# argumen: shot <out.png> [perintah;perintah] [detik] [zoom] [x] [z] [lantai] [yaw] [pitch]

func _maybe_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[0] != "shot":
		return
	if args.size() > 4:
		t_zoom = float(args[4])
		zoom = t_zoom
	if args.size() > 6:
		t_pivot = Vector3(float(args[5]), 0, float(args[6]))
	if args.size() > 7:
		set_view_floor(int(args[7]))
	if args.size() > 8:
		t_yaw = float(args[8])
		yaw = t_yaw
	if args.size() > 9:
		t_pitch = float(args[9])
		pitch = t_pitch
	pivot.position = t_pivot
	if args.size() > 2:
		for c in args[2].split(";", false):
			print(run_command(c))
	await get_tree().create_timer(float(args[3]) if args.size() > 3 else 4.0).timeout
	get_viewport().get_texture().get_image().save_png(args[1])
	get_tree().quit()
