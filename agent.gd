class_name Agent
extends Node3D
## Karakter chibi (kepala besar, badan mungil) yang mewakili satu AI agent.

signal need_task(agent: Agent)
signal move_started(agent: Agent)  # dipakai multiplayer: kirim rute ke pemain lain

const FLOOR_H := 3.2
const RIG_SCALE := 0.8
const SIT_DROP := -0.12

static var _count := 0

var agent_name := ""
var status := "idle"
var sitting := false
var dest_cell := Vector2i.ZERO
var dest_floor := 0
var think := 3.0
var ext_status := ""  # status nyata dari bot (kosong = tidak ada)
var ext_until := 0.0
var shirt_color := Color.WHITE
var title := ""  # jabatan (tampil saat di-hover)
var hovered := false
var plumbob: Node3D
## Aktivitas saat diam di suatu tempat: "type" (mengetik), "relax" (santai di sofa),
## "read" (pegang buku), "coffee" (bikin / minum kopi), "" (berdiri biasa).
var activity := ""
var _arrive_act := ""
var relaxed := false  # NPC kota: kalau duduk selalu santai, bukan mengetik
var _book: Node3D
var _mug: Node3D

var _path: Array = []
var _arrive_kind := "stand"
var _arrive_yaw := 0.0
var _arrive_status := ""
var _face_yaw := 0.0
var _phase := 0.0
var _t := 0.0
var _speed := 3.0
var _manual := 0.0  # > 0 = sedang digerakkan keyboard (animasi jalan tanpa rute)

var _rig: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _ring: MeshInstance3D
var _marker: MeshInstance3D
var _flash := 0.0
var _poke := 0.0  # 1 = baru diklik, turun ke 0
var _sparks: Array = []  # [mesh, kecepatan, umur]
static var _spark_mats := {}


static func make_box(parent: Node, pos: Vector3, size: Vector3, color: Color, tex := "grain", scale := 0.5) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = Look.mat(color, tex, scale)
	m.position = pos
	parent.add_child(m)
	return m


static func make_cyl(parent: Node, pos: Vector3, radius: float, height: float, color: Color, tex := "grain", segs := 12) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	m.mesh = c
	m.material_override = Look.mat(color, tex)
	m.position = pos
	parent.add_child(m)
	return m


## Bola low-poly (gaya PS1). `squash` mengubah skala per sumbu, `hemi` = setengah bola atas.
static func make_ball(parent: Node, pos: Vector3, radius: float, color: Color, squash := Vector3.ONE, tex := "grain", hemi := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 12
	s.rings = 4 if hemi else 7
	m.mesh = s
	m.material_override = Look.mat(color, tex, 2.0)
	m.position = pos
	m.scale = squash
	parent.add_child(m)
	return m


static func make_capsule(parent: Node, pos: Vector3, radius: float, height: float, color: Color, tex := "cloth") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 2
	m.mesh = c
	m.material_override = Look.mat(color, tex, 2.0)
	m.position = pos
	parent.add_child(m)
	return m


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Gaya rambut per gender: cowok = jabrik, topi jerami, bandana, pendek rapi;
## cewek = kuncir kuda, sanggul, kuncir dua, panjang terurai.
const STYLES_M := [6, 1, 5, 3]
const STYLES_F := [7, 0, 2, 4]


## Pilih gaya rambut untuk gender "m" / "f" (n = angka acak/urutan); selain itu -1 (bebas).
static func style_for(gender: String, n: int) -> int:
	if gender == "m":
		return STYLES_M[absi(n) % STYLES_M.size()]
	if gender == "f":
		return STYLES_F[absi(n) % STYLES_F.size()]
	return -1


func setup(p_name: String, shirt: Color, hair: Color, look := -1) -> void:
	agent_name = p_name
	shirt_color = shirt
	var style := look if look >= 0 else _count % 6
	_count += 1
	Look.snap = true
	_rig = Node3D.new()
	_rig.scale = Vector3.ONE * RIG_SCALE
	add_child(_rig)

	var skin := Color(1.0, 0.84, 0.70)
	var pants: Color = [Color(0.32, 0.42, 0.62), Color(0.45, 0.32, 0.22), Color(0.30, 0.45, 0.32),
		Color(0.55, 0.40, 0.30), Color(0.28, 0.36, 0.55), Color(0.50, 0.30, 0.38)][style % 6]
	var boots := Color(0.42, 0.26, 0.16)

	# badan: kaos + celana/overall pendek
	make_capsule(_rig, Vector3(0, 1.06, 0), 0.30, 0.78, shirt)
	make_cyl(_rig, Vector3(0, 0.82, 0), 0.32, 0.26, pants, "cloth", 12)
	if style % 2 == 0:
		# tali overall
		make_box(_rig, Vector3(-0.14, 1.12, 0.27), Vector3(0.07, 0.42, 0.06), pants, "cloth", 2.0)
		make_box(_rig, Vector3(0.14, 1.12, 0.27), Vector3(0.07, 0.42, 0.06), pants, "cloth", 2.0)
		make_box(_rig, Vector3(0, 0.98, 0.28), Vector3(0.3, 0.16, 0.06), pants, "cloth", 2.0)

	# kepala besar
	_head = Node3D.new()
	_head.position = Vector3(0, 1.86, 0)
	_rig.add_child(_head)
	make_ball(_head, Vector3.ZERO, 0.45, skin)
	# mata besar berkilau
	for sx in [-1.0, 1.0]:
		make_ball(_head, Vector3(0.15 * sx, -0.03, 0.405), 0.075, Color(0.16, 0.10, 0.08), Vector3(0.85, 1.3, 0.5))
		make_ball(_head, Vector3(0.15 * sx + 0.025, 0.02, 0.44), 0.026, Color(1, 1, 1))
		make_ball(_head, Vector3(0.26 * sx, -0.13, 0.35), 0.06, Color(1.0, 0.58, 0.55), Vector3(1.0, 0.6, 0.4))
	make_box(_head, Vector3(0, -0.19, 0.405), Vector3(0.08, 0.025, 0.03), Color(0.62, 0.28, 0.24))
	_build_hair(style, hair)

	# kaki pendek + sepatu bot
	_leg_l = _limb(Vector3(-0.15, 0.72, 0), 0.12, 0.46, pants)
	_leg_r = _limb(Vector3(0.15, 0.72, 0), 0.12, 0.46, pants)
	for leg in [_leg_l, _leg_r]:
		make_ball(leg, Vector3(0, -0.6, 0.05), 0.15, boots, Vector3(1.0, 0.7, 1.3))
	# lengan + tangan bulat
	_arm_l = _limb(Vector3(-0.36, 1.32, 0), 0.1, 0.42, shirt)
	_arm_r = _limb(Vector3(0.36, 1.32, 0), 0.1, 0.42, shirt)
	for arm in [_arm_l, _arm_r]:
		make_ball(arm, Vector3(0, -0.46, 0), 0.11, skin)
	# properti aktivitas (disembunyikan sampai dipakai)
	_book = Node3D.new()
	_book.position = Vector3(0, 1.2, 0.47)
	_book.rotation.x = -0.75
	_rig.add_child(_book)
	var cover: Color = [Color(0.75, 0.25, 0.22), Color(0.22, 0.42, 0.70), Color(0.30, 0.55, 0.32)][_count % 3]
	for sx in [-1.0, 1.0]:
		var half := make_box(_book, Vector3(0.15 * sx, 0, 0), Vector3(0.3, 0.38, 0.03), cover, "cloth", 2.0)
		half.rotation.y = -0.25 * sx
		var pg := make_box(_book, Vector3(0.14 * sx, 0, 0.025), Vector3(0.26, 0.34, 0.025), Color(0.97, 0.95, 0.88), "grain")
		pg.rotation.y = -0.25 * sx
	_book.visible = false
	_mug = Node3D.new()
	_mug.position = Vector3(0, -0.52, 0.1)
	_arm_r.add_child(_mug)
	make_cyl(_mug, Vector3.ZERO, 0.08, 0.16, Color(0.97, 0.97, 0.96), "grain", 10)
	make_cyl(_mug, Vector3(0, 0.075, 0), 0.065, 0.02, Color(0.35, 0.20, 0.12), "grain", 10)
	var handle := make_box(_mug, Vector3(0.1, 0, 0), Vector3(0.04, 0.09, 0.03), Color(0.97, 0.97, 0.96))
	handle.rotation.z = 0.2
	_mug.visible = false

	_ring = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 0.02
	_ring.mesh = cyl
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1, 0.9, 0.2)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rmat
	_ring.position.y = 0.06
	_ring.visible = false
	add_child(_ring)

	# panah penanda di atas kepala saat dipilih
	_marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.0
	cone.height = 0.32
	cone.radial_segments = 4
	cone.rings = 1
	_marker.mesh = cone
	_marker.material_override = rmat
	_marker.visible = false
	add_child(_marker)
	Look.snap = false

	set_status("idle")


func _build_hair(style: int, hair: Color) -> void:
	# tutup kepala (setengah bola, sedikit miring ke belakang agar dahi terlihat)
	var cap := make_ball(_head, Vector3(0, 0.04, -0.02), 0.485, hair, Vector3.ONE, "carpet", true)
	cap.rotation.x = -0.28
	make_ball(_head, Vector3(0, -0.06, -0.1), 0.44, hair, Vector3(1.05, 1.0, 1.0), "carpet")
	# poni
	for bx in [-0.17, 0.0, 0.17]:
		make_ball(_head, Vector3(bx, 0.21, 0.35), 0.13, hair, Vector3(1.0, 0.8, 0.7), "carpet")
	match style:
		0:  # kuncir kuda
			make_ball(_head, Vector3(0, 0.05, -0.5), 0.13, hair, Vector3.ONE, "carpet")
			make_ball(_head, Vector3(0, -0.22, -0.56), 0.15, hair, Vector3(0.9, 1.5, 0.9), "carpet")
		1:  # rambut jabrik
			for i in 5:
				var a := -0.9 + i * 0.45
				var sp := make_ball(_head, Vector3(sin(a) * 0.3, 0.42, cos(a) * 0.12 - 0.08), 0.12, hair, Vector3(0.8, 1.6, 0.8), "carpet")
				sp.rotation.z = -a * 0.6
		2:  # sanggul atas
			make_ball(_head, Vector3(0, 0.52, -0.1), 0.17, hair, Vector3.ONE, "carpet")
		3:  # topi jerami
			var straw := Color(0.95, 0.82, 0.48)
			var brim := make_cyl(_head, Vector3(0, 0.3, 0), 0.72, 0.05, straw, "planks", 14)
			brim.rotation.x = -0.12
			make_cyl(_head, Vector3(0, 0.44, -0.03), 0.4, 0.26, straw, "planks", 12)
			make_cyl(_head, Vector3(0, 0.36, -0.03), 0.41, 0.08, Color(0.85, 0.25, 0.22), "cloth", 12)
		4:  # kuncir dua
			for sx in [-1.0, 1.0]:
				make_ball(_head, Vector3(0.48 * sx, -0.05, -0.12), 0.15, hair, Vector3(0.9, 1.3, 0.9), "carpet")
		5:  # bandana
			var band := make_cyl(_head, Vector3(0, 0.2, -0.02), 0.47, 0.12, Color(0.95, 0.85, 0.30), "cloth", 12)
			band.rotation.x = -0.28
		6:  # pendek rapi, belah samping (cowok)
			var sw := make_ball(_head, Vector3(0.12, 0.36, 0.2), 0.2, hair, Vector3(1.5, 0.6, 1.0), "carpet")
			sw.rotation.z = -0.35
			make_ball(_head, Vector3(-0.2, 0.33, 0.12), 0.15, hair, Vector3(1.2, 0.7, 1.2), "carpet")
		7:  # panjang terurai sampai bahu (cewek)
			make_ball(_head, Vector3(0, -0.3, -0.2), 0.4, hair, Vector3(1.12, 1.25, 0.75), "carpet")
			for sx in [-1.0, 1.0]:
				make_ball(_head, Vector3(0.4 * sx, -0.3, 0.02), 0.13, hair, Vector3(0.8, 2.2, 0.9), "carpet")


func _limb(pivot_pos: Vector3, radius: float, length: float, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	_rig.add_child(pivot)
	make_capsule(pivot, Vector3(0, -length / 2.0, 0), radius, length, color)
	return pivot


func floor_index() -> int:
	return clampi(roundi(position.y / FLOOR_H), 0, 2)


func set_status(s: String) -> void:
	status = s


func has_ext() -> bool:
	return not ext_status.is_empty() and now() < ext_until


func showing_ext() -> bool:
	return has_ext() and status == ext_status


## Berlian hijau melayang di atas kepala (penanda karakter yang bisa di-hover/klik).
static func make_plumbob(parent: Node, size: float, color: Color) -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.55
	mat.roughness = 0.3
	for s: float in [1.0, -1.0]:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0 if s > 0 else size * 0.5
		c.bottom_radius = size * 0.5 if s > 0 else 0.0
		c.height = size * (0.75 if s > 0 else 1.15)
		c.radial_segments = 6
		c.rings = 1
		m.mesh = c
		m.material_override = mat
		m.position.y = c.height / 2.0 * s
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(m)
	n.set_meta("no_batch", true)
	parent.add_child(n)
	return n


func add_plumbob() -> void:
	plumbob = make_plumbob(self, 0.42, Color(0.25, 0.95, 0.35))


func set_selected(on: bool) -> void:
	_ring.visible = on
	if on:
		_flash = 1.0


## Reaksi saat diklik: memantul gepeng-melar, lompat kecil, percikan bintang dari kepala.
func poke() -> void:
	_poke = 1.0
	var cols := [Color(1, 0.92, 0.35), Color(1, 1, 1), Color(1, 0.6, 0.7), Color(0.6, 0.9, 1)]
	var top := Vector3(0, 2.0, 0)
	for i in 10:
		var c: Color = cols[i % cols.size()]
		if not _spark_mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_spark_mats[c] = m
		var s := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * 0.12
		s.mesh = b
		s.material_override = _spark_mats[c]
		s.rotation = Vector3(0.785, 0, 0.785)
		s.position = top
		add_child(s)
		var a := TAU * i / 10.0 + randf() * 0.4
		var v := Vector3(cos(a) * 2.2, randf_range(2.0, 3.5), sin(a) * 2.2)
		_sparks.append([s, v, 0.0])


func _update_poke(d: float) -> void:
	var sc := Vector3.ONE
	var hop := 0.0
	if _poke > 0.0:
		_poke = maxf(0.0, _poke - d * 1.4)
		var t := 1.0 - _poke
		var w := sin(t * PI * 5.0) * exp(-t * 4.0) * 0.35
		sc = Vector3(1.0 + w * 0.6, 1.0 - w, 1.0 + w * 0.6)
		hop = maxf(0.0, sin(t * PI * 2.5)) * 0.3 * exp(-t * 3.0)
	_rig.scale = sc * RIG_SCALE
	_rig.position.y += hop
	for i in range(_sparks.size() - 1, -1, -1):
		var sp: Array = _sparks[i]
		var m: MeshInstance3D = sp[0]
		sp[2] += d
		sp[1].y -= 7.0 * d
		m.position += sp[1] * d
		m.rotate_y(8.0 * d)
		m.scale = Vector3.ONE * maxf(0.0, 1.0 - sp[2] / 0.7)
		if sp[2] >= 0.7:
			m.queue_free()
			_sparks.remove_at(i)


func is_moving() -> bool:
	return not _path.is_empty()


func begin_move(points: Array, kind: String, yaw: float, arrive_status: String, act := "") -> void:
	stand_up()
	activity = ""
	_arrive_act = act
	_path = points
	_arrive_kind = kind
	_arrive_yaw = yaw
	_arrive_status = arrive_status
	set_status("berjalan...")
	move_started.emit(self)


## Keadaan ringkas untuk multiplayer: posisi, sisa rute, cara tiba, duduk/berdiri.
func net_state() -> Dictionary:
	var r := func(v: float) -> float: return snappedf(v, 0.01)
	var path := []
	for p in _path:
		path.append([r.call(p.x), r.call(p.y), r.call(p.z)])
	return {"p": [r.call(position.x), r.call(position.y), r.call(position.z)], "path": path,
		"kind": _arrive_kind, "ayaw": r.call(_arrive_yaw), "ast": _arrive_status,
		"yaw": r.call(_face_yaw), "sit": sitting, "st": status, "act": activity, "aact": _arrive_act}


## Terapkan keadaan dari pemain lain. Selisih kecil diperhalus (jalan), selisih besar langsung lompat.
func apply_net_state(s: Dictionary) -> void:
	var p: Array = s.get("p", [])
	if p.size() != 3:
		return
	var at := Vector3(p[0], p[1], p[2])
	var path := []
	for q in s.get("path", []):
		path.append(Vector3(q[0], q[1], q[2]))
	if position.distance_to(at) > 2.5:
		position = at
	elif path.is_empty() and position.distance_to(at) > 0.15:
		path.append(at)  # diam di tempat lain: jalan pelan ke sana
	think = 1e9
	if not path.is_empty():
		_path = path
		_arrive_kind = str(s.get("kind", "stand"))
		_arrive_yaw = float(s.get("ayaw", 0.0))
		_arrive_status = str(s.get("ast", ""))
		_arrive_act = str(s.get("aact", ""))
		activity = ""
		stand_up()
		set_status("berjalan...")
		return
	_path.clear()
	_face_yaw = float(s.get("yaw", _face_yaw))
	if bool(s.get("sit", false)) != sitting:
		if s.get("sit", false):
			_sit_down()
		else:
			stand_up()
	activity = str(s.get("act", ""))
	set_status(str(s.get("st", status)))


## Dipanggil tiap frame saat pemain menggerakkan karakter dengan WASD (posisi diatur main).
func step_manual(dir: Vector3) -> void:
	if not _path.is_empty():
		_path.clear()
	if sitting:
		stand_up()
	if _manual <= 0.0:
		set_status("berjalan...")
	_manual = 0.12
	activity = ""
	_arrive_act = ""
	_arrive_kind = "stand"  # pemain lain: jangan duduk saat tiba di posisi ini
	_arrive_status = "diam"
	_face_yaw = atan2(dir.x, dir.z)


func stop() -> void:
	_path.clear()
	set_status("diam")
	think = 10.0


func stand_up() -> void:
	sitting = false
	activity = ""
	_rig.position.y = 0.0


func _sit_down() -> void:
	sitting = true
	_rig.position.y = SIT_DROP


func _arrive() -> void:
	_face_yaw = _arrive_yaw
	if _arrive_kind == "sit":
		_sit_down()
	activity = _arrive_act if _arrive_act != "" else (("relax" if relaxed else "type") if _arrive_kind == "sit" else "")
	set_status(_arrive_status)
	think = randf_range(6.0, 10.0)


func _process(d: float) -> void:
	_t += d
	var moving := not _path.is_empty()
	var walking := moving or _manual > 0.0
	if moving:
		var target: Vector3 = _path[0]
		var to := target - position
		if to.length() < 0.08:
			position = target
			_path.pop_front()
			if _path.is_empty():
				_arrive()
		else:
			var step := minf(_speed * d, to.length())
			position += to.normalized() * step
			var flat := Vector2(to.x, to.z)
			if flat.length() > 0.01:
				_face_yaw = atan2(flat.x, flat.y)
		_phase += d * _speed * 3.5
	elif _manual > 0.0:
		_manual -= d
		_phase += d * _speed * 3.5
		if _manual <= 0.0:
			set_status("diam")
	else:
		think -= d
		if think <= 0.0:
			think = 5.0
			need_task.emit(self)
	rotation.y = lerp_angle(rotation.y, _face_yaw, minf(1.0, 10.0 * d))

	var leg_l := 0.0
	var leg_r := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var bob := 0.0
	var head_x := 0.0
	var act := "" if walking else activity
	if walking:
		var s := sin(_phase) * 0.7
		leg_l = s
		leg_r = -s
		arm_l = -s
		arm_r = s
		bob = absf(cos(_phase)) * 0.06
	elif sitting:
		leg_l = -PI / 2
		leg_r = -PI / 2
		if act == "relax":
			arm_l = -0.5 + sin(_t * 1.3) * 0.05
			arm_r = -0.5 + sin(_t * 1.1 + 1.0) * 0.05
			bob = sin(_t * 1.6) * 0.01
		elif act == "read" or act == "coffee":
			pass  # diatur di bawah
		else:
			arm_l = -1.0 + sin(_t * 14.0) * 0.1
			arm_r = -1.0 + sin(_t * 14.0 + 1.5) * 0.1
	else:
		bob = sin(_t * 2.2) * 0.012  # bernapas
	if act == "read":
		# pegang buku di depan dada, kepala menunduk, sesekali membalik halaman
		var flip := maxf(0.0, sin(_t * 0.8)) ** 12
		arm_l = -1.2 + sin(_t * 0.9) * 0.03
		arm_r = -1.2 - flip * 0.5
		head_x = 0.28
	elif act == "coffee":
		# tangan kiri di meja, kanan mengaduk lalu sesekali menyeruput
		var cyc := fmod(_t, 7.0)
		arm_l = -0.75
		if cyc < 5.0:
			arm_r = -0.95 + sin(_t * 9.0) * 0.08
		else:
			arm_r = -2.3 + sin((cyc - 5.0) * PI / 2.0) * 0.15
			head_x = -0.12
	_book.visible = act == "read"
	_mug.visible = act == "coffee"
	var k := minf(1.0, 15.0 * d)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, leg_l, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, leg_r, k)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm_l, k)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_r, k)
	_rig.position.y = (SIT_DROP if sitting else 0.0) + bob
	_head.rotation.z = sin(_phase * 0.5) * 0.06 if walking else 0.0
	_head.rotation.x = lerpf(_head.rotation.x, head_x, k)
	_update_poke(d)

	if plumbob:
		_flash = maxf(0.0, _flash - d * 1.5)
		plumbob.position.y = 2.45 + sin(_t * 2.5) * 0.08
		plumbob.rotation.y = _t * 1.6
		var ps := 1.0 + _flash * 0.9 + (0.3 if hovered else 0.0)
		plumbob.scale = plumbob.scale.lerp(Vector3.ONE * ps, minf(1.0, 12.0 * d))
		_ring.scale = Vector3(1.0 + _flash, 1.0, 1.0 + _flash)
	if _marker.visible:
		_marker.position.y = 2.35 + sin(_t * 5.0) * 0.1
		_marker.rotation.y = _t * 2.0
		# denyut membesar sesaat setelah dipilih
		_flash = maxf(0.0, _flash - d * 1.5)
		var sc := 1.0 + _flash * 1.5
		_marker.scale = Vector3.ONE * sc
		_ring.scale = Vector3(1.0 + _flash, 1.0, 1.0 + _flash)
