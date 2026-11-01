extends Node3D
## Lingkungan kota di luar kantor: jalan raya, mobil & motor lalu lalang, pejalan kaki,
## pedagang kaki lima, lapangan basket, taman bermain, gang belakang, toko & rumah tetangga,
## gedung tinggi di kejauhan, awan dan burung. Semua gerak di _process.
## Benda diam digabung per tekstur (Look.batch) supaya draw call tetap sedikit.

# --- tata letak (koordinat dunia; kantor di tengah, pagar z=28, gerbang x=-16) ---
const ROAD_Z0 := 31.0
const ROAD_Z1 := 39.0
const LANES := [33.0, 37.0]  # lajur 0 ke +x, lajur 1 ke -x
const WALK_NEAR := 29.8  # trotoar sisi kantor
const WALK_FAR := 40.2  # trotoar seberang
const CROSS_X := -16.0  # zebra cross di depan gerbang kantor
const ROAD_HALF := 130.0  # panjang jalan ke kiri-kanan
const WRAP := 125.0  # kendaraan muncul lagi di sisi lain
const CART_XS := [-74.0, -40.0, 6.0, 44.0, 82.0]  # gerobak kaki lima di trotoar seberang

const ASPHALT := Color(0.36, 0.36, 0.39)
const CURB := Color(0.78, 0.76, 0.72)
const INK := Color(0.12, 0.10, 0.10)

var rng := RandomNumberGenerator.new()
var stat: Node3D  # semua benda diam (digabung jadi beberapa mesh)
var cars: Array = []  # {node, lane, speed, max, span}
var parked: Array = []  # node mobil/motor diam
var peds: Array = []  # Agent di trotoar (dipakai logika zebra cross)
var npcs: Array = []  # semua Agent kota
var clouds: Array = []  # [node, sudut, radius, kecepatan]
var buildings: Array = []  # [node, pusat XZ, jari-jari, tinggi]
var birds: Array = []  # [node, pusat, radius, sudut, kecepatan, tinggi]
var swings: Array = []  # [node, fase]
var seesaw: Node3D
var flag: Node3D
var ball: MeshInstance3D
var players: Array = []
var _ball_from: Agent
var _ball_to: Agent
var _ball_t := 1.0
var _ball_wait := 1.0
var _jet: MeshInstance3D
var _t := 0.0
var lite := false  # HP: separuh NPC, pejalan kaki lebih sedikit


func build(seed_: int = 7) -> void:
	rng.seed = seed_
	stat = Node3D.new()
	stat.name = "Statis"
	add_child(stat)
	_build_road()
	_build_street_furniture()
	_build_neighborhood()
	_build_skyline()
	_build_parking()
	_build_front_yard()
	_build_court()
	_build_playground()
	_build_alley()
	_build_carts()
	_spawn_cars()
	_spawn_peds()
	_spawn_sky()
	if lite:
		_thin_npcs()
	# gabungkan mesh: statis jadi satu kelompok, bangunan & kendaraan per node
	Look.batch(stat, true)
	for bd in buildings:
		Look.batch(bd[0], true)
	for c in cars:
		Look.batch(c["node"], true)
	for n in parked:
		Look.batch(n, true)
	for a in npcs:
		Look.batch(a)


# ---------- helper ----------

func _b(parent: Node, pos: Vector3, size: Vector3, color: Color, tex := "grain", scale := 0.5) -> MeshInstance3D:
	return Agent.make_box(parent, pos, size, color, tex, scale)


func _node(pos: Vector3, yaw := 0.0, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	(parent if parent != null else self).add_child(n)
	return n


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _flat_box(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _bench(p: Vector3, yaw: float) -> void:
	var n := _node(p, yaw, stat)
	var wood := Color(0.72, 0.50, 0.32)
	var metal := Color(0.25, 0.27, 0.30)
	_b(n, Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.5), wood, "planks")
	_b(n, Vector3(0, 0.8, -0.24), Vector3(1.8, 0.4, 0.06), wood, "planks")
	for sx: float in [-0.75, 0.75]:
		_b(n, Vector3(sx, 0.22, 0), Vector3(0.08, 0.44, 0.45), metal, "metal")


## NPC chibi. `kind`: "stand" berdiri diam, "sit" duduk santai, "wander" jalan acak di `area`.
func _npc(pos: Vector3, yaw: float, kind: String, area := Rect2(), speed := 1.5, sc := 1.0) -> Agent:
	var a := Agent.new()
	a.setup("warga", PED_SHIRTS[rng.randi() % PED_SHIRTS.size()], PED_HAIR[rng.randi() % PED_HAIR.size()])
	a.position = pos
	a.scale = Vector3.ONE * sc
	a._speed = speed
	a.relaxed = true
	add_child(a)
	npcs.append(a)
	if kind == "wander":
		a.set_meta("area", area)
		a.need_task.connect(_wander)
		a.think = rng.randf_range(0.0, 3.0)
	else:
		a.begin_move([pos], kind, yaw, "")
		a.need_task.connect(_idle_turn)
	return a


func _wander(a: Agent) -> void:
	var r: Rect2 = a.get_meta("area")
	var p := Vector3(rng.randf_range(r.position.x, r.end.x), a.position.y, rng.randf_range(r.position.y, r.end.y))
	a.begin_move([p], "stand", rng.randf() * TAU, "")
	a.think = rng.randf_range(0.3, 4.0) if a.get_meta("busy", false) else rng.randf_range(1.0, 6.0)


## NPC diam sesekali menoleh sedikit supaya tidak kaku.
func _idle_turn(a: Agent) -> void:
	a._face_yaw = a._arrive_yaw + rng.randf_range(-0.6, 0.6)
	a.think = rng.randf_range(2.0, 6.0)


# ---------- jalan ----------

func _build_road() -> void:
	var cz := (ROAD_Z0 + ROAD_Z1) / 2.0
	var span := ROAD_HALF * 2.0
	_b(stat, Vector3(0, -0.06, cz), Vector3(span, 0.1, ROAD_Z1 - ROAD_Z0), ASPHALT, "stone", 0.35)
	# trotoar + kanstin
	for z: float in [WALK_NEAR, WALK_FAR]:
		_b(stat, Vector3(0, 0.0, z), Vector3(span, 0.2, 2.2), Color(0.80, 0.78, 0.74), "tiles", 0.5)
	for z: float in [ROAD_Z0 - 0.05, ROAD_Z1 + 0.05]:
		_b(stat, Vector3(0, 0.02, z), Vector3(span, 0.24, 0.25), CURB, "stone")
	# marka tengah putus-putus
	var x := -ROAD_HALF
	while x < ROAD_HALF:
		if absf(x - CROSS_X) > 4.0:
			_b(stat, Vector3(x + 1.0, 0.0, cz), Vector3(2.0, 0.03, 0.18), Color(0.95, 0.88, 0.45))
		x += 4.0
	# zebra cross
	for i in 7:
		var z := ROAD_Z0 + 0.6 + i * 1.15
		_b(stat, Vector3(CROSS_X, 0.0, z), Vector3(3.2, 0.03, 0.6), Color(0.95, 0.95, 0.93))
	# garis berhenti
	_b(stat, Vector3(CROSS_X - 2.4, 0.0, LANES[0]), Vector3(0.3, 0.03, 3.6), Color(0.95, 0.95, 0.93))
	_b(stat, Vector3(CROSS_X + 2.4, 0.0, LANES[1]), Vector3(0.3, 0.03, 3.6), Color(0.95, 0.95, 0.93))
	# jalan kecil dari gerbang kantor ke trotoar
	_b(stat, Vector3(CROSS_X, -0.07, 28.9), Vector3(2.4, 0.04, 1.4), Color(1, 1, 1), "dirt", 0.5)
	# jalan samping ke utara (sisi barat & timur)
	for sx: float in [-1.0, 1.0]:
		var rx := sx * 52.0
		_b(stat, Vector3(rx, -0.06, -24.0), Vector3(7.0, 0.1, 110.0), ASPHALT, "stone", 0.35)
		var z := -78.0
		while z < 28.0:
			_b(stat, Vector3(rx, 0.0, z + 1.0), Vector3(0.18, 0.03, 2.0), Color(0.95, 0.88, 0.45))
			z += 4.0
		# mobil parkir di tepi jalan samping
		z = -70.0
		while z < 20.0:
			if rng.randf() < 0.45:
				_add_car(["sedan", "hatch", "van", "motor"][rng.randi() % 4], -1, 0.0,
					Vector3(rx + sx * 2.4, 0, z), PI / 2.0 if sx > 0 else -PI / 2.0)
			z += rng.randf_range(5.0, 8.0)


func _build_street_furniture() -> void:
	# lampu jalan di kedua trotoar
	var x := -ROAD_HALF + 6.0
	var i := 0
	while x < ROAD_HALF:
		if absf(x - CROSS_X) > 5.0:
			_lamp_post(Vector3(x, 0.1, WALK_NEAR - 0.6 if i % 2 == 0 else WALK_FAR + 0.6), i % 2 == 1)
		x += 9.0
		i += 1
	# pohon peneduh di trotoar seberang
	x = -ROAD_HALF + 3.0
	while x < ROAD_HALF:
		var near_cart := false
		for cx: float in CART_XS:
			if absf(x - cx) < 3.5:
				near_cart = true
		if absf(x - CROSS_X) > 4.0 and not near_cart:
			_street_tree(Vector3(x + rng.randf_range(-1, 1), 0.1, WALK_FAR + 0.7))
		x += rng.randf_range(10.0, 16.0)
	# pohon peneduh di sisi kantor (antara pagar dan trotoar), kecuali dekat gerbang & halte
	x = -ROAD_HALF + 8.0
	while x < ROAD_HALF:
		if absf(x - CROSS_X) > 6.0 and absf(x - (CROSS_X + 9.0)) > 4.0:
			_street_tree(Vector3(x, 0.0, 28.4))
		x += rng.randf_range(12.0, 18.0)
	# halte bus di sisi kantor + orang menunggu
	var bs := Vector3(CROSS_X + 9.0, 0.1, WALK_NEAR - 0.3)
	_bus_stop(bs)
	_npc(bs + Vector3(-0.7, 0, -0.45), 0.0, "sit")
	_npc(bs + Vector3(0.6, 0, -0.45), 0.0, "sit")
	_npc(bs + Vector3(1.5, 0, 0.4), PI / 2.0, "stand")
	# hidran
	_b(stat, Vector3(CROSS_X - 5.0, 0.45, WALK_NEAR - 0.6), Vector3(0.3, 0.7, 0.3), Color(0.85, 0.2, 0.18), "metal")
	_b(stat, Vector3(CROSS_X - 5.0, 0.85, WALK_NEAR - 0.6), Vector3(0.38, 0.12, 0.38), Color(0.85, 0.2, 0.18), "metal")


func _lamp_post(p: Vector3, flip: bool) -> void:
	var n := _node(p, PI if flip else 0.0, stat)
	var metal := Color(0.25, 0.27, 0.30)
	_b(n, Vector3(0, 1.8, 0), Vector3(0.14, 3.6, 0.14), metal, "metal")
	_b(n, Vector3(0, 3.6, 0.45), Vector3(0.1, 0.1, 1.0), metal, "metal")
	_b(n, Vector3(0, 3.5, 0.9), Vector3(0.4, 0.15, 0.5), metal, "metal")
	_flat_box(n, Vector3(0, 3.41, 0.9), Vector3(0.3, 0.06, 0.4), _flat(Color(1.0, 0.95, 0.75)))


func _street_tree(p: Vector3) -> void:
	_b(stat, p + Vector3(0, 0.02, 0), Vector3(1.1, 0.08, 1.1), Color(0.40, 0.30, 0.22), "dirt")
	_b(stat, p + Vector3(0, 1.0, 0), Vector3(0.3, 2.0, 0.3), Color(0.50, 0.35, 0.22), "planks", 1.0)
	var leaf := Color(0.38, 0.62, 0.30).lightened(rng.randf_range(-0.08, 0.1))
	var c1 := _b(stat, p + Vector3(0, 2.6, 0), Vector3(2.0, 1.5, 2.0), leaf, "leaves")
	c1.rotation.y = rng.randf() * PI
	var c2 := _b(stat, p + Vector3(0.2, 3.4, 0.1), Vector3(1.3, 1.0, 1.3), leaf.lightened(0.08), "leaves")
	c2.rotation.y = rng.randf() * PI


func _bus_stop(p: Vector3) -> void:
	var n := _node(p, 0.0, stat)
	var metal := Color(0.30, 0.42, 0.55)
	for sx: float in [-1.6, 1.6]:
		_b(n, Vector3(sx, 1.2, -0.6), Vector3(0.1, 2.4, 0.1), metal, "metal")
	_b(n, Vector3(0, 2.45, -0.3), Vector3(3.6, 0.12, 1.3), metal, "metal")
	_b(n, Vector3(0, 1.3, -0.68), Vector3(3.3, 1.8, 0.05), Color(0.75, 0.88, 0.95, 0.35))
	_b(n, Vector3(0, 0.45, -0.45), Vector3(2.6, 0.08, 0.45), Color(0.78, 0.58, 0.38), "planks")
	for sx: float in [-1.1, 1.1]:
		_b(n, Vector3(sx, 0.22, -0.45), Vector3(0.08, 0.44, 0.4), metal, "metal")
	_b(n, Vector3(2.4, 1.3, 0.3), Vector3(0.08, 2.6, 0.08), metal, "metal")
	_b(n, Vector3(2.4, 2.4, 0.3), Vector3(0.6, 0.6, 0.06), Color(0.2, 0.55, 0.85))
	_b(n, Vector3(2.4, 2.4, 0.34), Vector3(0.35, 0.35, 0.02), Color(1, 1, 1))


## Area parkir di halaman timur kantor, dengan mobil-mobil terparkir.
func _build_parking() -> void:
	var px := 28.0
	_b(stat, Vector3(px, -0.07, 0), Vector3(8.0, 0.06, 26.0), ASPHALT.lightened(0.1), "stone", 0.35)
	for i in 9:
		var z := -12.0 + i * 3.0
		_b(stat, Vector3(px + 1.8, -0.03, z), Vector3(4.0, 0.03, 0.12), Color(0.95, 0.95, 0.93))
	var kinds := ["sedan", "hatch", "van", "sedan", "taxi", "hatch", "sedan"]
	var k := 0
	for i in 8:
		if rng.randf() < 0.2:
			continue
		var z := -10.5 + i * 3.0
		_add_car(kinds[k % kinds.size()], -1, 0.0, Vector3(px + 1.8, 0, z), PI if rng.randf() < 0.5 else 0.0)
		k += 1
	# deretan motor parkir di sisi barat area parkir
	for i in 10:
		_add_car("motor", -1, 0.0, Vector3(px - 2.6, 0, -11.0 + i * 1.1), PI)


# ---------- halaman depan kantor: bendera, pos satpam, parkir motor, bangku ----------

func _build_front_yard() -> void:
	# tiang bendera merah putih
	var fp := Vector3(0.0, 0.0, 21.5)
	_b(stat, fp + Vector3(0, 0.15, 0), Vector3(1.6, 0.3, 1.6), Color(0.85, 0.83, 0.78), "stone")
	_b(stat, fp + Vector3(0, 0.4, 0), Vector3(1.0, 0.2, 1.0), Color(0.85, 0.83, 0.78), "stone")
	Agent.make_cyl(stat, fp + Vector3(0, 4.0, 0), 0.06, 7.6, Color(0.9, 0.9, 0.92), "metal", 6)
	Agent.make_ball(stat, fp + Vector3(0, 7.85, 0), 0.12, Color(0.95, 0.8, 0.3), Vector3.ONE, "metal")
	flag = _node(fp + Vector3(0.06, 7.2, 0))
	_flat_box(flag, Vector3(0.9, 0.25, 0), Vector3(1.8, 0.5, 0.04), _flat(Color(0.85, 0.12, 0.12)))
	_flat_box(flag, Vector3(0.9, -0.25, 0), Vector3(1.8, 0.5, 0.04), _flat(Color(0.98, 0.98, 0.96)))
	# pos satpam di samping gerbang (dalam pagar)
	var gp := Vector3(-20.5, 0.0, 25.8)
	var n := _node(gp, 0.0, stat)
	_b(n, Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 2.2), Color(0.95, 0.93, 0.86), "wallpaper", 1.0)
	_b(n, Vector3(0, 2.75, 0), Vector3(2.9, 0.25, 2.7), Color(0.30, 0.42, 0.62), "metal")
	_b(n, Vector3(0, 1.6, 1.11), Vector3(1.6, 0.8, 0.06), Color(0.45, 0.62, 0.75))
	_b(n, Vector3(1.21, 1.6, 0), Vector3(0.06, 0.8, 1.2), Color(0.45, 0.62, 0.75))
	_b(n, Vector3(0, 2.25, 1.13), Vector3(1.4, 0.3, 0.05), Color(0.30, 0.42, 0.62))
	_npc(gp + Vector3(1.9, 0.0, 1.2), 0.0, "stand")
	# portal gerbang
	for sx: float in [-1.0, 1.0]:
		_b(stat, Vector3(CROSS_X + sx * 1.7, 1.4, 28.0), Vector3(0.35, 2.8, 0.35), Color(0.55, 0.32, 0.25), "brick", 1.0)
	_b(stat, Vector3(CROSS_X - 0.6, 1.05, 28.0), Vector3(2.4, 0.12, 0.12), Color(0.95, 0.85, 0.2), "metal")
	# deretan motor karyawan di balik pagar depan
	var x := -11.0
	while x < -3.0:
		_add_car("motor", -1, 0.0, Vector3(x, 0, 26.3), -PI / 2.0 + rng.randf_range(-0.15, 0.15))
		x += 1.05
	# bangku taman + orang duduk santai
	_bench(Vector3(4.5, 0.0, 25.2), PI)
	_npc(Vector3(4.0, 0.0, 25.15), PI, "sit")
	_npc(Vector3(5.0, 0.0, 25.15), PI, "sit")
	_bench(Vector3(14.0, 0.0, 18.5), PI)
	_npc(Vector3(14.4, 0.0, 18.45), PI, "sit")
	# kolam air mancur
	var fo := Vector3(9.0, 0.0, 19.5)
	Agent.make_cyl(stat, fo + Vector3(0, 0.25, 0), 1.9, 0.5, Color(0.85, 0.83, 0.78), "stone", 12)
	Agent.make_cyl(stat, fo + Vector3(0, 0.47, 0), 1.65, 0.1, Color(0.40, 0.65, 0.85), "grain", 12)
	Agent.make_cyl(stat, fo + Vector3(0, 0.9, 0), 0.25, 0.9, Color(0.85, 0.83, 0.78), "stone", 8)
	Agent.make_cyl(stat, fo + Vector3(0, 1.35, 0), 0.75, 0.15, Color(0.85, 0.83, 0.78), "stone", 10)
	var jet := Agent.make_cyl(self, fo + Vector3(0, 1.75, 0), 0.12, 0.8, Color(0.75, 0.9, 1.0), "grain", 6)
	jet.set_meta("jet", true)
	_jet = jet
	# bedeng bunga di sepanjang pagar depan & samping jalan setapak
	var fcols := [Color(0.95, 0.4, 0.45), Color(0.98, 0.85, 0.3), Color(0.75, 0.5, 0.95), Color(1, 1, 1), Color(1.0, 0.6, 0.3)]
	for seg: Vector2 in [Vector2(-31.0, -22.5), Vector2(0.0, 32.0)]:
		_b(stat, Vector3((seg.x + seg.y) / 2.0, 0.12, 27.3), Vector3(seg.y - seg.x, 0.25, 0.9), Color(0.45, 0.32, 0.22), "planks")
		var bx := seg.x + 0.4
		while bx < seg.y - 0.3:
			_b(stat, Vector3(bx, 0.32, 27.3 + rng.randf_range(-0.2, 0.2)), Vector3(0.22, 0.2, 0.22), Color(0.35, 0.6, 0.3), "leaves")
			_b(stat, Vector3(bx, 0.45, 27.3 + rng.randf_range(-0.2, 0.2)), Vector3(0.16, 0.12, 0.16), fcols[rng.randi() % fcols.size()])
			bx += 0.5
	# gazebo di halaman barat + orang istirahat
	var gz := Vector3(-27.5, 0.0, 13.0)
	_b(stat, gz + Vector3(0, 0.15, 0), Vector3(4.2, 0.3, 4.2), Color(0.70, 0.52, 0.34), "planks")
	for sx: float in [-1.8, 1.8]:
		for sz: float in [-1.8, 1.8]:
			_b(stat, gz + Vector3(sx, 1.5, sz), Vector3(0.2, 2.6, 0.2), Color(0.55, 0.38, 0.25), "planks")
	for i in 4:
		var rf := _b(stat, gz + Vector3(0, 3.0 + i * 0.3, 0), Vector3(5.0 - i * 1.2, 0.3, 5.0 - i * 1.2), Color(0.62, 0.30, 0.22), "planks", 1.0)
		rf.rotation.y = PI / 4.0 * (i % 2)
	_b(stat, gz + Vector3(0, 0.75, 0), Vector3(1.4, 0.08, 1.0), Color(0.80, 0.62, 0.42), "planks")
	_b(stat, gz + Vector3(0, 0.5, 0), Vector3(0.15, 0.5, 0.15), Color(0.55, 0.38, 0.25), "planks")
	_npc(gz + Vector3(-0.9, 0.3, 0.0), PI / 2.0, "sit")
	_npc(gz + Vector3(0.9, 0.3, 0.2), -PI / 2.0, "sit")
	_npc(gz + Vector3(0.0, 0.3, 1.0), PI, "stand")
	# karyawan jalan santai di halaman depan
	var yard := Rect2(-4.5, 16.5, 11.0, 3.0)
	for i in 3:
		_npc(Vector3(rng.randf_range(yard.position.x, yard.end.x), 0.0, rng.randf_range(yard.position.y, yard.end.y)),
			0.0, "wander", yard, rng.randf_range(1.0, 1.5))
	# karyawan ngobrol di halaman
	_npc(Vector3(-3.4, 0.0, 18.6), PI / 2.0, "stand")
	_npc(Vector3(-2.3, 0.0, 18.7), -PI / 2.0, "stand")
	_npc(Vector3(-2.8, 0.0, 17.8), 0.2, "stand")


# ---------- lapangan basket (barat) ----------

func _build_court() -> void:
	var c := Vector3(-41.5, 0.0, 6.0)
	var w := 10.0
	var d := 17.0
	_b(stat, c + Vector3(0, -0.05, 0), Vector3(w + 1.0, 0.06, d + 1.0), Color(0.80, 0.42, 0.30), "stone", 0.35)
	_b(stat, c + Vector3(0, -0.02, 0), Vector3(w - 0.6, 0.02, d - 0.6), Color(0.30, 0.52, 0.45), "stone", 0.35)
	var line := Color(0.95, 0.95, 0.92)
	_b(stat, c + Vector3(0, 0.0, 0), Vector3(w - 0.6, 0.02, 0.1), line)
	for sz: float in [-1.0, 1.0]:
		_b(stat, c + Vector3(0, 0.0, sz * (d / 2.0 - 2.2)), Vector3(3.6, 0.02, 0.1), line)
		for sx: float in [-1.8, 1.8]:
			_b(stat, c + Vector3(sx, 0.0, sz * (d / 2.0 - 1.25)), Vector3(0.1, 0.02, 1.9), line)
		# ring basket
		var hp := c + Vector3(0, 0, sz * (d / 2.0 + 0.2))
		_b(stat, hp + Vector3(0, 1.6, 0), Vector3(0.15, 3.2, 0.15), Color(0.25, 0.27, 0.30), "metal")
		_b(stat, hp + Vector3(0, 3.2, -sz * 0.3), Vector3(1.6, 1.0, 0.08), Color(0.95, 0.95, 0.95))
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.2
		tm.outer_radius = 0.26
		tm.rings = 10
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = Look.mat(Color(0.95, 0.45, 0.15), "metal")
		ring.position = hp + Vector3(0, 2.95, -sz * 0.6)
		stat.add_child(ring)
	# pagar kawat rendah di sekeliling
	for sx: float in [-1.0, 1.0]:
		_b(stat, c + Vector3(sx * (w / 2.0 + 0.5), 0.6, 0), Vector3(0.06, 1.2, d + 1.0), Color(0.6, 0.65, 0.6, 0.5))
	_bench(c + Vector3(w / 2.0 + 1.6, 0, -3.0), -PI / 2.0)
	_npc(c + Vector3(w / 2.0 + 1.6, 0, -3.4), -PI / 2.0, "sit")
	_npc(c + Vector3(w / 2.0 + 1.6, 0, -2.4), -PI / 2.0, "sit")
	# pemain
	var area := Rect2(c.x - w / 2.0 + 1.0, c.z - d / 2.0 + 1.0, w - 2.0, d - 2.0)
	for i in 6:
		var a := _npc(Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y)),
			0.0, "wander", area, rng.randf_range(2.6, 3.6))
		a.set_meta("busy", true)
		players.append(a)
	ball = Agent.make_ball(self, players[0].position + Vector3(0, 0.8, 0), 0.16, Color(0.92, 0.45, 0.15), Vector3.ONE, "grain")
	_ball_from = players[0]
	_ball_to = players[0]


func _update_ball(d: float) -> void:
	if ball == null:
		return
	if _ball_t < 1.0:
		_ball_t = minf(1.0, _ball_t + d * 1.6)
		var a := _ball_from.position + Vector3(0, 1.0, 0)
		var b := _ball_to.position + Vector3(0, 1.0, 0)
		ball.position = a.lerp(b, _ball_t) + Vector3(0, sin(_ball_t * PI) * 1.8, 0)
	else:
		# menggiring bola
		var fwd := Vector3(sin(_ball_to.rotation.y), 0, cos(_ball_to.rotation.y)) * 0.45
		ball.position = _ball_to.position + fwd + Vector3(0.25, 0.18 + absf(sin(_t * 7.0)) * 0.7, 0)
		_ball_wait -= d
		if _ball_wait <= 0.0:
			_ball_from = _ball_to
			while _ball_to == _ball_from:
				_ball_to = players[rng.randi() % players.size()]
			_ball_t = 0.0
			_ball_wait = rng.randf_range(1.0, 3.0)


# ---------- taman bermain (timur) ----------

func _build_playground() -> void:
	var c := Vector3(42.0, 0.0, 2.0)
	_b(stat, c + Vector3(0, -0.06, 0), Vector3(12.0, 0.06, 18.0), Color(0.86, 0.76, 0.55), "dirt", 0.5)
	# perosotan
	var s := _node(c + Vector3(-3.0, 0, -5.0), 0.0, stat)
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			_b(s, Vector3(sx, 1.0, sz - 1.0), Vector3(0.12, 2.0, 0.12), Color(0.25, 0.45, 0.80), "metal")
	_b(s, Vector3(0, 2.0, -1.0), Vector3(1.2, 0.12, 1.2), Color(0.95, 0.75, 0.2), "planks")
	var sl := _b(s, Vector3(0, 1.0, 1.0), Vector3(0.9, 0.08, 3.2), Color(0.90, 0.30, 0.25), "metal")
	sl.rotation.x = 0.68
	for i in 5:
		_b(s, Vector3(0, 0.35 + i * 0.38, -1.7 - i * 0.05), Vector3(0.8, 0.06, 0.12), Color(0.25, 0.45, 0.80), "metal")
	# ayunan (bergerak)
	var sp := c + Vector3(2.5, 0, -4.5)
	for sx: float in [-1.6, 1.6]:
		for sz: float in [-0.7, 0.7]:
			var leg := _b(stat, sp + Vector3(sx, 1.25, sz * 0.8), Vector3(0.12, 2.6, 0.12), Color(0.85, 0.30, 0.30), "metal")
			leg.rotation.x = sz * 0.3
	_b(stat, sp + Vector3(0, 2.5, 0), Vector3(3.4, 0.14, 0.14), Color(0.85, 0.30, 0.30), "metal")
	for sx: float in [-0.75, 0.75]:
		var sw := _node(sp + Vector3(sx, 2.5, 0))
		sw.set_meta("no_batch", true)
		_b(sw, Vector3(-0.25, -1.0, 0), Vector3(0.03, 2.0, 0.03), Color(0.4, 0.4, 0.42), "metal")
		_b(sw, Vector3(0.25, -1.0, 0), Vector3(0.03, 2.0, 0.03), Color(0.4, 0.4, 0.42), "metal")
		_b(sw, Vector3(0, -2.0, 0), Vector3(0.6, 0.06, 0.3), Color(0.95, 0.75, 0.2), "planks")
		Look.batch(sw)
		swings.append([sw, rng.randf() * TAU])
	# jungkat-jungkit
	var ss := c + Vector3(2.5, 0, 3.0)
	_b(stat, ss + Vector3(0, 0.25, 0), Vector3(0.3, 0.5, 0.3), Color(0.3, 0.3, 0.32), "metal")
	seesaw = _node(ss + Vector3(0, 0.5, 0))
	_b(seesaw, Vector3.ZERO, Vector3(0.25, 0.08, 3.6), Color(0.30, 0.65, 0.40), "planks")
	for sz: float in [-1.6, 1.6]:
		_b(seesaw, Vector3(0, 0.25, sz), Vector3(0.5, 0.06, 0.06), Color(0.3, 0.3, 0.32), "metal")
	Look.batch(seesaw)
	# kotak pasir
	var sb := c + Vector3(-3.0, 0, 4.0)
	_b(stat, sb + Vector3(0, 0.1, 0), Vector3(3.2, 0.2, 3.2), Color(0.55, 0.40, 0.25), "planks")
	_b(stat, sb + Vector3(0, 0.12, 0), Vector3(2.8, 0.2, 2.8), Color(0.95, 0.88, 0.62), "dirt")
	_b(stat, sb + Vector3(0.5, 0.3, 0.3), Vector3(0.6, 0.25, 0.6), Color(0.95, 0.88, 0.62), "dirt")
	# pohon & bangku orang tua
	for p: Vector2 in [Vector2(37.0, -8.0), Vector2(47.5, -7.0), Vector2(37.0, 11.0), Vector2(47.5, 10.5)]:
		_street_tree(Vector3(p.x, 0.0, p.y))
	_bench(c + Vector3(5.3, 0, 0), -PI / 2.0)
	_npc(c + Vector3(5.3, 0, -0.4), -PI / 2.0, "sit")
	_npc(c + Vector3(5.3, 0, 0.5), -PI / 2.0, "sit")
	# anak-anak bermain
	var area := Rect2(c.x - 5.0, c.z - 8.0, 10.0, 16.0)
	for i in 7:
		var k := _npc(Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y)),
			0.0, "wander", area, rng.randf_range(1.8, 2.8), 0.68)
		k.set_meta("busy", true)


# ---------- gang belakang kantor ----------

func _build_alley() -> void:
	_b(stat, Vector3(0, -0.07, -27.6), Vector3(97.0, 0.06, 4.0), Color(0.62, 0.60, 0.58), "stone", 0.35)
	var area := Rect2(-46.0, -28.6, 92.0, 2.0)
	for i in 6:
		_npc(Vector3(rng.randf_range(-44, 44), 0.0, -27.6), 0.0, "wander", area, rng.randf_range(1.2, 1.8))
	# motor parkir di depan rumah + ibu-ibu ngobrol
	for i in 6:
		_add_car("motor", -1, 0.0, Vector3(rng.randf_range(-42, 40), 0, -29.9), rng.randf_range(-0.2, 0.2) + PI / 2.0)
	for gx: float in [-20.0, 18.0]:
		_npc(Vector3(gx, 0.0, -29.4), PI / 2.0, "stand")
		_npc(Vector3(gx + 1.0, 0.0, -29.5), -PI / 2.0, "stand")
	# orang jalan di tepi jalan samping
	for sx: float in [-1.0, 1.0]:
		var ra := Rect2(sx * 56.2 - 0.4, -70.0, 0.8, 92.0)
		for i in 4:
			_npc(Vector3(sx * 56.2, 0.0, rng.randf_range(-65, 18)), 0.0, "wander", ra, rng.randf_range(1.2, 1.8))


# ---------- pedagang kaki lima ----------

func _build_carts() -> void:
	var foods := [["BAKSO", Color(0.85, 0.2, 0.18)], ["SATE", Color(0.95, 0.6, 0.15)], ["ES TEH", Color(0.2, 0.55, 0.85)],
		["NASGOR", Color(0.3, 0.6, 0.3)], ["MARTABAK", Color(0.62, 0.35, 0.70)]]
	for i in CART_XS.size():
		var x: float = CART_XS[i]
		var info: Array = foods[i % foods.size()]
		var n := _node(Vector3(x, 0.1, WALK_FAR + 0.75), PI, stat)
		var col: Color = info[1]
		# gerobak
		_b(n, Vector3(0, 0.75, 0), Vector3(2.0, 0.9, 0.8), Color(0.92, 0.88, 0.80), "planks")
		_b(n, Vector3(0, 0.75, 0.41), Vector3(1.8, 0.35, 0.02), col)
		_b(n, Vector3(0, 1.45, 0), Vector3(1.9, 0.5, 0.7), Color(0.75, 0.88, 0.95, 0.4))
		_b(n, Vector3(0, 1.72, 0), Vector3(2.0, 0.05, 0.8), Color(0.92, 0.88, 0.80), "planks")
		for sx: float in [-0.6, 0.6]:
			var wh := Agent.make_cyl(n, Vector3(sx, 0.28, 0.0), 0.28, 0.9, Color(0.2, 0.2, 0.2), "grain", 8)
			wh.rotation.x = PI / 2.0
		# payung
		_b(n, Vector3(1.1, 1.4, -0.2), Vector3(0.06, 2.8, 0.06), Color(0.4, 0.4, 0.42), "metal")
		var um := Agent.make_cyl(n, Vector3(1.1, 2.8, -0.2), 1.3, 0.12, col.lightened(0.15), "cloth", 8)
		um.scale = Vector3(1, 1, 1)
		Agent.make_cyl(n, Vector3(1.1, 2.9, -0.2), 0.7, 0.12, Color(0.98, 0.96, 0.9), "cloth", 8)
		# kursi plastik
		for sx: float in [-1.6, 1.8]:
			_b(n, Vector3(sx, 0.22, 0.9), Vector3(0.35, 0.44, 0.35), Color(0.2, 0.45, 0.85), "metal")
		var lbl := Label3D.new()
		lbl.text = info[0]
		lbl.font_size = 48
		lbl.pixel_size = 0.006
		lbl.modulate = Color(1, 1, 1)
		lbl.outline_size = 8
		lbl.outline_modulate = col.darkened(0.4)
		lbl.position = Vector3(0, 1.45, 0.4)
		lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		n.add_child(lbl)
		# penjual di belakang gerobak, pembeli di depan
		_npc(Vector3(x - 0.3, 0.1, WALK_FAR + 1.35), PI, "stand")
		_npc(Vector3(x + 1.6, 0.1, WALK_FAR - 0.1), 0.0, "sit")
		if i % 2 == 0:
			_npc(Vector3(x + 0.3, 0.1, WALK_FAR - 0.05), 0.0, "stand")


# ---------- bangunan tetangga ----------

const WALLS := [Color(0.95, 0.86, 0.70), Color(0.86, 0.70, 0.60), Color(0.80, 0.86, 0.78), Color(0.93, 0.80, 0.82),
	Color(0.78, 0.82, 0.92), Color(0.97, 0.93, 0.82), Color(0.82, 0.62, 0.48)]
const ACCENTS := [Color(0.85, 0.25, 0.22), Color(0.22, 0.55, 0.40), Color(0.25, 0.42, 0.75), Color(0.95, 0.65, 0.20),
	Color(0.62, 0.35, 0.70), Color(0.15, 0.62, 0.65)]
const GLASS := Color(0.45, 0.62, 0.75)
const SIGNS := ["KOPI", "ROTI", "TOKO", "APOTEK", "WARUNG", "BUKU", "SALON", "BANK", "MINIMARKET", "BENGKEL", "LAUNDRY", "BAKSO"]


func _build_neighborhood() -> void:
	# deretan toko di seberang jalan (menghadap kantor)
	var x := -ROAD_HALF + 4.0
	var k := 0
	while x < ROAD_HALF - 6.0:
		var w := rng.randf_range(7.0, 11.0)
		var p := Vector3(x + w / 2.0, 0, WALK_FAR + 1.6)
		if rng.randf() < 0.75:
			_shop(p, w, rng.randf_range(7.0, 9.0), rng.randi_range(1, 3), SIGNS[k % SIGNS.size()])
		else:
			_house(p, w - 1.0, 8.0)
		k += 1
		x += w + rng.randf_range(0.6, 2.0)
	# rumah di belakang (utara) kantor, dua lapis
	for row: float in [-31.0, -47.0]:
		x = -46.0
		while true:
			var w := rng.randf_range(7.0, 10.0)
			if x + w > 47.0:
				break
			_house(Vector3(x + w / 2.0, 0, row), w, 8.0, 0.0)
			x += w + rng.randf_range(1.5, 3.5)
	# rumah & toko di sisi barat dan timur, di seberang jalan samping
	for sx: float in [-1.0, 1.0]:
		var z := -76.0
		while z < 24.0:
			var w := rng.randf_range(7.0, 10.0)
			var p := Vector3(sx * 60.0, 0, z + w / 2.0)
			var yaw := -PI / 2.0 if sx > 0 else PI / 2.0
			if rng.randf() < 0.5:
				_house(p, w, 8.0, yaw)
			else:
				_shop(p, w, 8.0, rng.randi_range(1, 2), SIGNS[rng.randi() % SIGNS.size()], yaw)
			z += w + rng.randf_range(1.0, 3.0)
	# jalan lingkungan di antara dua lapis rumah utara
	_b(stat, Vector3(0, -0.07, -43.0), Vector3(97.0, 0.06, 4.0), Color(0.62, 0.60, 0.58), "stone", 0.35)
	# blok rumah di belakang (utara) lebih jauh agar tidak ada lahan kosong
	for row: float in [-58.0, -71.0]:
		x = -46.0
		while true:
			var w := rng.randf_range(8.0, 12.0)
			if x + w > 47.0:
				break
			if rng.randf() < 0.6:
				_house(Vector3(x + w / 2.0, 0, row), w, 9.0, 0.0)
			else:
				_tower(Vector3(x + w / 2.0, 0, row - 4.0), w, 9.0, rng.randi_range(3, 6))
			x += w + rng.randf_range(1.5, 3.0)


## Gedung tinggi di kejauhan (selatan, utara, timur, barat) supaya kota terasa padat.
func _build_skyline() -> void:
	# selatan, di belakang deretan toko
	var x := -ROAD_HALF
	while x < ROAD_HALF:
		var w := rng.randf_range(9.0, 16.0)
		_tower(Vector3(x + w / 2.0, 0, rng.randf_range(58.0, 66.0)), w, rng.randf_range(9.0, 13.0), rng.randi_range(3, 10))
		x += w + rng.randf_range(1.0, 4.0)
	# barat & timur, di belakang rumah sisi jalan samping
	for sx: float in [-1.0, 1.0]:
		var z := -95.0
		while z < 18.0:
			var w := rng.randf_range(9.0, 15.0)
			_tower(Vector3(sx * rng.randf_range(76.0, 84.0), 0, z + w / 2.0), w, rng.randf_range(9.0, 12.0), rng.randi_range(3, 12))
			z += w + rng.randf_range(1.0, 4.0)
	# utara jauh
	x = -ROAD_HALF
	while x < ROAD_HALF:
		var w := rng.randf_range(10.0, 18.0)
		_tower(Vector3(x + w / 2.0, 0, rng.randf_range(-92.0, -86.0)), w, 10.0, rng.randi_range(4, 12))
		x += w + rng.randf_range(1.0, 4.0)


## Gedung bertingkat sederhana: blok + pita jendela tiap lantai + atap.
func _tower(p: Vector3, w: float, d: float, floors: int) -> void:
	var n := _node(p)
	var fh := 3.0
	var h := floors * fh + 1.0
	_register_box(n, w, d, h)
	var wall: Color = WALLS[rng.randi() % WALLS.size()].darkened(rng.randf_range(0.0, 0.15))
	_b(n, Vector3(0, h / 2.0, 0), Vector3(w, h, d), wall, "wallpaper", 1.0)
	var glass := GLASS.darkened(rng.randf_range(0.0, 0.2))
	for f in floors:
		var y := 1.0 + f * fh + 1.5
		_b(n, Vector3(0, y, 0), Vector3(w + 0.06, 1.2, d + 0.06), glass, "metal", 1.0)
	_b(n, Vector3(0, h + 0.2, 0), Vector3(w + 0.3, 0.4, d + 0.3), wall.darkened(0.3), "stone")
	if rng.randf() < 0.5:
		_b(n, Vector3(rng.randf_range(-w / 4.0, w / 4.0), h + 1.0, 0), Vector3(2.0, 1.6, 2.0), Color(0.75, 0.77, 0.8), "metal")
	if floors >= 8 and rng.randf() < 0.5:
		_b(n, Vector3(0, h + 3.0, 0), Vector3(0.12, 5.0, 0.12), Color(0.85, 0.2, 0.18), "metal")


## Toko: lantai dasar kaca + kanopi garis + papan nama, lantai atas jendela.
## Bagian depan menghadap -z dunia secara default (ke arah jalan / kantor).
func _shop(p: Vector3, w: float, d: float, floors: int, sign_text: String, yaw := PI) -> void:
	var n := _node(p, yaw)
	_register(n, w, d, 3.0 * (floors + 1) + 1.5)
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var acc: Color = ACCENTS[rng.randi() % ACCENTS.size()]
	var fh := 3.0
	var h := fh * (floors + 1)
	var tex := "brick" if rng.randf() < 0.4 else "wallpaper"
	_b(n, Vector3(0, h / 2.0, -d / 2.0), Vector3(w, h, d), wall, tex, 1.0)
	# etalase kaca + pintu
	_b(n, Vector3(0, 1.3, 0.04), Vector3(w - 1.2, 2.0, 0.12), GLASS)
	_b(n, Vector3(0, 0.15, 0.06), Vector3(w - 1.0, 0.3, 0.16), acc.darkened(0.3), "planks")
	_b(n, Vector3(w * 0.25, 1.15, 0.1), Vector3(1.1, 2.2, 0.08), acc.darkened(0.2), "planks")
	# kanopi bergaris
	var stripes := int(w / 0.8)
	for i in stripes:
		var col := acc if i % 2 == 0 else Color(0.97, 0.95, 0.9)
		var aw := _b(n, Vector3(-w / 2.0 + (i + 0.5) * w / stripes, 2.75, 0.55), Vector3(w / stripes + 0.01, 0.08, 1.3), col, "cloth", 2.0)
		aw.rotation.x = 0.35
	# papan nama
	_b(n, Vector3(0, 3.45, 0.08), Vector3(minf(w - 1.0, 0.5 * sign_text.length() + 1.2), 0.7, 0.14), Color(0.98, 0.96, 0.9))
	var lbl := Label3D.new()
	lbl.text = sign_text
	lbl.font_size = 64
	lbl.pixel_size = 0.006
	lbl.modulate = acc.darkened(0.25)
	lbl.outline_size = 0
	lbl.position = Vector3(0, 3.45, 0.16)
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	n.add_child(lbl)
	# jendela lantai atas
	for f in range(1, floors + 1):
		var y := f * fh + 1.6
		var nw := maxi(2, int(w / 2.2))
		for i in nw:
			var wx := -w / 2.0 + (i + 0.5) * w / nw
			_b(n, Vector3(wx, y, 0.03), Vector3(1.1, 1.3, 0.1), GLASS)
			_b(n, Vector3(wx, y - 0.72, 0.09), Vector3(1.3, 0.12, 0.2), wall.darkened(0.25))
	# atap datar + tepi + barang di atap
	_b(n, Vector3(0, h + 0.15, -d / 2.0), Vector3(w + 0.3, 0.3, d + 0.3), wall.darkened(0.3), "stone")
	if rng.randf() < 0.6:
		_b(n, Vector3(rng.randf_range(-w / 4.0, w / 4.0), h + 0.7, -d * 0.6), Vector3(1.2, 0.8, 1.0), Color(0.75, 0.77, 0.8), "metal")
	if rng.randf() < 0.4:
		_b(n, Vector3(-w / 3.0, h + 1.0, -d * 0.4), Vector3(0.9, 1.4, 0.9), Color(0.35, 0.5, 0.75), "metal")


## Rumah: dinding + atap pelana, pintu, jendela, pagar kecil.
func _house(p: Vector3, w: float, d: float, yaw := PI) -> void:
	var n := _node(p, yaw)
	_register(n, w, d, 6.0)
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var roof: Color = [Color(0.72, 0.30, 0.22), Color(0.35, 0.42, 0.55), Color(0.45, 0.32, 0.25), Color(0.30, 0.50, 0.40)][rng.randi() % 4]
	var bw := w - 1.0
	var h := 3.2
	var hd := d - 2.0
	_b(n, Vector3(0, h / 2.0, -hd / 2.0 - 1.0), Vector3(bw, h, hd), wall, "wallpaper", 1.0)
	# atap pelana dari dua papan miring
	var slope := 0.55
	var half := hd / 2.0 + 0.5
	var rl := half / cos(slope)
	for s: float in [-1.0, 1.0]:
		var r := _b(n, Vector3(0, h + sin(slope) * rl / 2.0, -hd / 2.0 - 1.0 + s * half / 2.0), Vector3(bw + 0.6, 0.2, rl), roof, "planks", 1.0)
		r.rotation.x = slope * s
	# segitiga tembok depan-belakang (tumpukan balok mengecil)
	for i in 5:
		var tw := bw * (1.0 - (i + 0.5) / 5.0)
		_b(n, Vector3(0, h + (i + 0.5) * sin(slope) * rl / 5.0, -hd / 2.0 - 1.0), Vector3(tw, sin(slope) * rl / 5.0, hd - 0.1), wall, "wallpaper", 1.0)
	# pintu & jendela
	_b(n, Vector3(-bw * 0.2, 1.05, -1.0 + 0.05), Vector3(1.0, 2.1, 0.12), roof.darkened(0.2), "planks")
	for wx: float in [bw * 0.12, bw * 0.34]:
		_b(n, Vector3(wx, 1.7, -1.0 + 0.04), Vector3(1.0, 1.0, 0.1), GLASS)
		_b(n, Vector3(wx, 1.13, -1.0 + 0.08), Vector3(1.2, 0.12, 0.18), Color(0.95, 0.95, 0.92))
	# halaman depan: pagar rendah + semak
	var fence := Color(0.95, 0.93, 0.88)
	_b(n, Vector3(0, 0.4, 0.2), Vector3(w, 0.08, 0.08), fence, "planks")
	var fx := -w / 2.0
	while fx <= w / 2.0:
		if absf(fx + bw * 0.2) > 0.7:
			_b(n, Vector3(fx, 0.35, 0.2), Vector3(0.1, 0.7, 0.1), fence, "planks")
		fx += 0.6
	for bx: float in [bw * 0.2, bw * 0.4]:
		_b(n, Vector3(bx, 0.35, -0.5), Vector3(0.9, 0.7, 0.7), Color(0.35, 0.6, 0.3).lightened(rng.randf() * 0.1), "leaves")


func _register(n: Node3D, w: float, d: float, h: float) -> void:
	var ctr := n.position + Vector3(0, 0, -d / 2.0).rotated(Vector3.UP, n.rotation.y)
	buildings.append([n, Vector2(ctr.x, ctr.z), maxf(w, d) / 2.0, h])


func _register_box(n: Node3D, w: float, d: float, h: float) -> void:
	buildings.append([n, Vector2(n.position.x, n.position.z), maxf(w, d) / 2.0, h])


## Sembunyikan bangunan yang berdiri di antara kamera dan titik yang sedang dilihat.
func update_occlusion(cam_pos: Vector3, look_at: Vector3) -> void:
	var a := Vector2(look_at.x, look_at.z)
	var b := Vector2(cam_pos.x, cam_pos.z)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.001)
	for bd in buildings:
		var ctr: Vector2 = bd[1]
		var t := clampf((ctr - a).dot(ab) / l2, 0.0, 1.0)
		var dist := ctr.distance_to(a + ab * t)
		var n: Node3D = bd[0]
		# tinggi garis pandang di atas bangunan ini
		var sight_y := look_at.y + (cam_pos.y - look_at.y) * maxf(0.0, t - bd[2] / maxf(sqrt(l2), 0.001))
		n.visible = not (t > 0.0 and dist < bd[2] + 3.0 and sight_y < bd[3] and ctr.distance_to(a) > 3.0)


# ---------- kendaraan ----------

const CAR_COLS := [Color(0.85, 0.22, 0.20), Color(0.20, 0.40, 0.80), Color(0.95, 0.95, 0.95), Color(0.20, 0.22, 0.25),
	Color(0.30, 0.65, 0.40), Color(0.95, 0.75, 0.20), Color(0.60, 0.62, 0.66), Color(0.55, 0.30, 0.65)]


func _spawn_cars() -> void:
	var kinds := ["sedan", "motor", "taxi", "motor", "van", "sedan", "motor", "bus", "motor", "hatch", "sedan", "motor",
		"van", "motor", "hatch", "motor"]
	for lane in 2:
		var x := -WRAP + rng.randf_range(0, 6)
		var j := lane * 5
		while x < WRAP - 8:
			var kind: String = kinds[j % kinds.size()]
			j += 1
			_add_car(kind, lane, x)
			x += rng.randf_range(7.0, 15.0) if kind == "motor" else rng.randf_range(11.0, 20.0)


## lane = -1 berarti kendaraan parkir di `park_pos` (tidak bergerak).
func _add_car(kind: String, lane: int, x: float, park_pos := Vector3.ZERO, park_yaw := 0.0) -> void:
	var dir := 1.0 if lane == 0 else -1.0
	var n: Node3D
	if lane >= 0:
		var off := rng.randf_range(-0.7, 0.7) if kind == "motor" else 0.0
		n = _node(Vector3(x, 0, LANES[lane] + off), 0.0 if dir > 0 else PI)
	else:
		n = _node(park_pos, park_yaw)
		parked.append(n)
	if kind == "motor":
		_build_motor(n, lane >= 0)
		if lane >= 0:
			var vm := rng.randf_range(7.0, 11.0)
			cars.append({"node": n, "lane": lane, "speed": vm, "max": vm, "span": 1.9})
		return
	var body: Color = CAR_COLS[rng.randi() % CAR_COLS.size()]
	var span := 3.8
	var glass := Color(0.25, 0.32, 0.42)
	match kind:
		"bus":
			span = 9.5
			body = [Color(0.15, 0.55, 0.65), Color(0.95, 0.70, 0.15)][rng.randi() % 2]
			_b(n, Vector3(0, 1.55, 0), Vector3(span, 2.5, 2.3), body, "metal")
			_b(n, Vector3(-0.3, 1.9, 0), Vector3(span - 1.6, 0.9, 2.34), glass)
			_b(n, Vector3(span / 2.0 - 0.02, 1.9, 0), Vector3(0.06, 1.0, 2.0), glass)
			_b(n, Vector3(0, 2.85, 0), Vector3(span - 0.2, 0.12, 2.1), Color(0.92, 0.92, 0.92), "metal")
			_b(n, Vector3(0, 0.75, 0), Vector3(span + 0.02, 0.18, 2.32), Color(0.95, 0.95, 0.95))
		"van":
			span = 4.6
			_b(n, Vector3(-0.2, 1.15, 0), Vector3(span - 0.4, 1.7, 1.9), body, "metal")
			_b(n, Vector3(span / 2.0 - 0.45, 0.75, 0), Vector3(0.9, 0.9, 1.9), body, "metal")
			_b(n, Vector3(span / 2.0 - 0.62, 1.55, 0), Vector3(0.1, 0.65, 1.7), glass)
			_b(n, Vector3(0.6, 1.55, 0), Vector3(1.6, 0.55, 1.94), glass)
		_:
			if kind == "taxi":
				body = Color(0.98, 0.80, 0.15)
			span = 3.4 if kind == "hatch" else 4.0
			_b(n, Vector3(0, 0.62, 0), Vector3(span, 0.62, 1.75), body, "metal")
			var cab_len := span * (0.62 if kind == "hatch" else 0.5)
			var cab_x := -span * (0.12 if kind == "hatch" else 0.05)
			_b(n, Vector3(cab_x, 1.17, 0), Vector3(cab_len, 0.5, 1.55), body, "metal")
			_b(n, Vector3(cab_x, 1.15, 0), Vector3(cab_len + 0.06, 0.38, 1.59), glass)
			if kind == "taxi":
				_b(n, Vector3(cab_x, 1.5, 0), Vector3(0.6, 0.2, 0.35), Color(1, 1, 1))
	# roda
	var wz := 0.95 if kind != "bus" else 1.12
	var wr := 0.36 if kind != "bus" else 0.5
	for wx: float in [span * 0.32, -span * 0.32]:
		for sz: float in [-1.0, 1.0]:
			var wheel := Agent.make_cyl(n, Vector3(wx, wr, sz * wz), wr, 0.3, Color(0.12, 0.12, 0.13), "grain", 10)
			wheel.rotation.x = PI / 2.0
			var hub := Agent.make_cyl(n, Vector3(wx, wr, sz * (wz + 0.13)), wr * 0.45, 0.06, Color(0.75, 0.76, 0.78), "metal", 8)
			hub.rotation.x = PI / 2.0
	# lampu depan & belakang (tidak terkena bayangan, selalu terang)
	var head_y := 0.7 if kind != "bus" else 0.9
	for sz: float in [-0.6, 0.6]:
		_flat_box(n, Vector3(span / 2.0 + 0.02, head_y, sz), Vector3(0.08, 0.18, 0.35), _HEAD_MAT)
		_flat_box(n, Vector3(-span / 2.0 - 0.02, head_y, sz), Vector3(0.08, 0.18, 0.35), _TAIL_MAT)
	if lane < 0:
		return
	var vmax := rng.randf_range(6.0, 10.0) if kind != "bus" else 5.5
	cars.append({"node": n, "lane": lane, "speed": vmax, "max": vmax, "span": span})


var _HEAD_MAT := _flat(Color(1.0, 0.97, 0.8))
var _TAIL_MAT := _flat(Color(0.95, 0.15, 0.12))


## Sepeda motor (bebek/matic) + pengendara berhelm bila sedang melaju.
func _build_motor(n: Node3D, rider: bool) -> void:
	var body: Color = CAR_COLS[rng.randi() % CAR_COLS.size()]
	for wx: float in [0.62, -0.62]:
		var wh := Agent.make_cyl(n, Vector3(wx, 0.3, 0), 0.3, 0.12, Color(0.12, 0.12, 0.13), "grain", 10)
		wh.rotation.x = PI / 2.0
	_b(n, Vector3(0.05, 0.5, 0), Vector3(1.0, 0.3, 0.32), body, "metal")
	_b(n, Vector3(-0.25, 0.72, 0), Vector3(0.75, 0.14, 0.34), Color(0.15, 0.15, 0.16), "cloth", 2.0)
	_b(n, Vector3(0.55, 0.85, 0), Vector3(0.22, 0.6, 0.3), body, "metal")
	_b(n, Vector3(0.6, 1.15, 0), Vector3(0.08, 0.06, 0.75), Color(0.2, 0.2, 0.22), "metal")
	_flat_box(n, Vector3(0.68, 0.95, 0), Vector3(0.06, 0.14, 0.18), _HEAD_MAT)
	_flat_box(n, Vector3(-0.66, 0.6, 0), Vector3(0.06, 0.1, 0.2), _TAIL_MAT)
	if not rider:
		return
	# pengendara: badan, kaki, lengan ke setang, helm
	var shirt: Color = PED_SHIRTS[rng.randi() % PED_SHIRTS.size()]
	if rng.randf() < 0.35:
		shirt = Color(0.15, 0.62, 0.30)  # jaket ojek hijau
	_b(n, Vector3(-0.2, 1.2, 0), Vector3(0.36, 0.62, 0.48), shirt, "cloth", 2.0)
	_b(n, Vector3(0.05, 0.85, 0.16), Vector3(0.55, 0.16, 0.14), Color(0.25, 0.3, 0.45), "cloth", 2.0)
	_b(n, Vector3(0.05, 0.85, -0.16), Vector3(0.55, 0.16, 0.14), Color(0.25, 0.3, 0.45), "cloth", 2.0)
	_b(n, Vector3(0.2, 1.3, 0.24), Vector3(0.65, 0.11, 0.11), shirt, "cloth", 2.0)
	_b(n, Vector3(0.2, 1.3, -0.24), Vector3(0.65, 0.11, 0.11), shirt, "cloth", 2.0)
	Agent.make_ball(n, Vector3(-0.15, 1.7, 0), 0.24, Color(1.0, 0.84, 0.70))
	var helm := Agent.make_ball(n, Vector3(-0.17, 1.76, 0), 0.27, [Color(0.15, 0.62, 0.30), Color(0.9, 0.9, 0.9),
		Color(0.2, 0.2, 0.22), Color(0.85, 0.2, 0.2)][rng.randi() % 4], Vector3.ONE, "metal", true)
	helm.rotation.z = 0.25
	if rng.randf() < 0.3:
		# penumpang ojek
		_b(n, Vector3(-0.6, 1.15, 0), Vector3(0.34, 0.58, 0.46), PED_SHIRTS[rng.randi() % PED_SHIRTS.size()], "cloth", 2.0)
		Agent.make_ball(n, Vector3(-0.6, 1.62, 0), 0.23, Color(1.0, 0.84, 0.70))
		Agent.make_ball(n, Vector3(-0.62, 1.68, 0), 0.26, Color(0.15, 0.62, 0.30), Vector3.ONE, "metal", true)


## Zebra cross "sibuk" bila ada orang di atasnya, atau orang yang mau menyeberang sudah dekat
## (supaya kendaraan sempat mengerem sebelum orangnya turun ke jalan).
func _crossing_busy() -> bool:
	for p in peds:
		var a: Agent = p
		var dx := absf(a.position.x - CROSS_X)
		var on_road := a.position.z > ROAD_Z0 - 0.8 and a.position.z < ROAD_Z1 + 0.8
		if dx < 2.2 and on_road:
			return true
		var to_z: float = a.get_meta("cross_to", INF)
		if to_z != INF and dx < 4.5 and absf(a.position.z - to_z) > 1.2 and a.position.z > WALK_NEAR - 1.5 and a.position.z < WALK_FAR + 1.5:
			return true
	return false


func _update_cars(d: float) -> void:
	var busy := _crossing_busy()
	for c in cars:
		var n: Node3D = c["node"]
		var dir := 1.0 if c["lane"] == 0 else -1.0
		var x := n.position.x
		# jarak ke kendaraan di depan pada lajur yang sama (dengan putaran)
		var gap := INF
		for o in cars:
			if o == c or o["lane"] != c["lane"]:
				continue
			var dx: float = (o["node"].position.x - x) * dir
			if dx < 0.0:
				dx += WRAP * 2.0
			dx -= (o["span"] + c["span"]) / 2.0
			gap = minf(gap, dx)
		var target: float = c["max"]
		if gap < 9.0:
			target = minf(target, maxf(0.0, (gap - 1.5) * 1.2))
		# berhenti di garis zebra cross bila ada yang menyeberang
		var front: float = x + dir * c["span"] / 2.0
		var to_stop := (CROSS_X - 2.6 - front) if dir > 0 else (front - (CROSS_X + 2.6))
		if busy and to_stop > -0.5 and to_stop < 12.0:
			target = minf(target, maxf(0.0, to_stop * 0.9))
		var acc := 6.0 if target > c["speed"] else 14.0
		c["speed"] = move_toward(c["speed"], target, acc * d)
		x += dir * c["speed"] * d
		if x > WRAP:
			x -= WRAP * 2.0
		elif x < -WRAP:
			x += WRAP * 2.0
		n.position.x = x


# ---------- pejalan kaki ----------

const PED_SHIRTS := [Color(0.9, 0.5, 0.3), Color(0.4, 0.6, 0.9), Color(0.95, 0.85, 0.4), Color(0.6, 0.8, 0.5),
	Color(0.85, 0.45, 0.65), Color(0.95, 0.95, 0.92), Color(0.45, 0.45, 0.55), Color(0.3, 0.7, 0.7),
	Color(0.8, 0.3, 0.3), Color(0.55, 0.4, 0.7)]
const PED_HAIR := [Color(0.15, 0.1, 0.08), Color(0.35, 0.22, 0.12), Color(0.55, 0.38, 0.2), Color(0.9, 0.8, 0.55), Color(0.6, 0.6, 0.6)]


## Lajur jalan kaki: sisi kantor di tengah trotoar, sisi seberang dekat kanstin (belakangnya gerobak).
func _walk_z(near: bool) -> float:
	return WALK_NEAR + 0.3 + rng.randf_range(-0.4, 0.4) if near else WALK_FAR - 0.6 + rng.randf_range(-0.25, 0.25)


func _spawn_peds() -> void:
	for i in (14 if lite else 34):
		var a := Agent.new()
		a.setup("warga", PED_SHIRTS[i % PED_SHIRTS.size()], PED_HAIR[rng.randi() % PED_HAIR.size()])
		a.position = Vector3(rng.randf_range(-110, 110), 0.1, _walk_z(i % 2 == 0))
		a._speed = rng.randf_range(1.3, 2.0)
		a.need_task.connect(_ped_next)
		add_child(a)
		peds.append(a)
		npcs.append(a)
		a.think = rng.randf_range(0.0, 2.0)


## Rute baru: jalan menyusuri trotoar, kadang menyeberang lewat zebra cross.
func _ped_next(a: Agent) -> void:
	var near_side := absf(a.position.z - WALK_NEAR) < absf(a.position.z - WALK_FAR)
	var lane_z := _walk_z(near_side)
	var pts: Array = []
	var cross := rng.randf() < 0.15 and absf(a.position.x - CROSS_X) < 45.0
	a.set_meta("cross_to", INF)
	if cross:
		var other := WALK_FAR if near_side else WALK_NEAR
		a.set_meta("cross_to", other)
		pts.append(Vector3(CROSS_X + rng.randf_range(-0.6, 0.6), 0.1, lane_z))
		lane_z = _walk_z(not near_side)
		pts.append(Vector3(CROSS_X + rng.randf_range(-0.6, 0.6), 0.1, lane_z))
		pts.append(Vector3(CROSS_X + rng.randf_range(-12, 12), 0.1, lane_z))
	else:
		var tx := clampf(a.position.x + rng.randf_range(-40, 40), -ROAD_HALF + 5, ROAD_HALF - 5)
		pts.append(Vector3(a.position.x, 0.1, lane_z))
		pts.append(Vector3(tx, 0.1, lane_z))
	a.begin_move(pts, "stand", rng.randf() * TAU, "jalan-jalan")
	a.think = rng.randf_range(0.5, 4.0)


## Mode ringan: buang separuh NPC kota (pemain basket tetap ada).
func _thin_npcs() -> void:
	var keep: Array = []
	for i in npcs.size():
		var a: Agent = npcs[i]
		if i % 2 == 0 or a in players or a in peds:
			keep.append(a)
		else:
			a.queue_free()
	npcs = keep


# ---------- langit: awan & burung ----------

func _spawn_sky() -> void:
	# awan hanya di kejauhan (cincin jauh dari kantor) supaya tidak menutupi pandangan
	var white := _flat(Color(1, 1, 1))
	for i in 18:
		var n := _node(Vector3.ZERO)
		for j in rng.randi_range(3, 5):
			var m := _flat_box(n, Vector3(rng.randf_range(-6, 6), rng.randf_range(-0.8, 1.0), rng.randf_range(-3, 3)),
				Vector3(rng.randf_range(6, 12), rng.randf_range(2.0, 3.5), rng.randf_range(5, 8)), white)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Look.batch(n, true)
		clouds.append([n, rng.randf() * TAU, rng.randf_range(150.0, 200.0), rng.randf_range(0.004, 0.008), rng.randf_range(38.0, 55.0)])
	var dark := _flat(Color(0.18, 0.16, 0.18))
	for i in 9:
		var n := Node3D.new()
		add_child(n)
		for s: float in [-1.0, 1.0]:
			var w := _flat_box(n, Vector3(s * 0.22, 0, 0), Vector3(0.5, 0.05, 0.16), dark)
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		birds.append([n, Vector2(rng.randf_range(-30, 30), rng.randf_range(-20, 30)), rng.randf_range(10, 25),
			rng.randf() * TAU, rng.randf_range(0.25, 0.45) * (1.0 if i % 2 == 0 else -1.0), rng.randf_range(9, 14)])


func _update_sky(d: float) -> void:
	for c in clouds:
		var n: Node3D = c[0]
		c[1] += c[3] * d
		n.position = Vector3(cos(c[1]) * c[2], c[4], sin(c[1]) * c[2])
		n.rotation.y = -c[1]
	for b in birds:
		var n: Node3D = b[0]
		b[3] += b[4] * d
		var ctr: Vector2 = b[1]
		var r: float = b[2]
		n.position = Vector3(ctr.x + cos(b[3]) * r, b[5] + sin(_t * 0.7 + r) * 0.8, ctr.y + sin(b[3]) * r)
		n.rotation.y = -b[3] + (PI if b[4] > 0 else 0.0)
		var flap := sin(_t * 12.0 + r) * 0.5
		n.get_child(0).rotation.z = flap
		n.get_child(1).rotation.z = -flap


func _update_props(_d: float) -> void:
	for s in swings:
		var n: Node3D = s[0]
		n.rotation.x = sin(_t * 1.8 + s[1]) * 0.55
	if seesaw:
		seesaw.rotation.x = sin(_t * 1.4) * 0.22
	if _jet:
		_jet.scale.y = 1.0 + sin(_t * 9.0) * 0.12
	if flag:
		flag.rotation.y = sin(_t * 1.7) * 0.25
		flag.scale.x = 0.92 + sin(_t * 3.1) * 0.08


func _process(d: float) -> void:
	_t += d
	_update_cars(d)
	_update_sky(d)
	_update_props(d)
	_update_ball(d)
