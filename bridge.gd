class_name Bridge
extends Node
## Klien WebSocket ke relay (bridge/relay.py). Menerima perintah & status nyata dari bot,
## mengirim balasan dan keadaan agent. Konfigurasi: bridge.cfg (lihat bridge.cfg.example)
## atau variabel lingkungan OFFICE_BRIDGE_URL / OFFICE_TOKEN.

signal state_changed(text: String)

var main: Node
var url := ""
var token := ""
var ws := WebSocketPeer.new()
var _connected := false
var _retry := 0.0
var _backoff := 1.0
var _state_timer := 0.0
var _last_state := ""


func _ready() -> void:
	_load_config()
	if url.is_empty():
		state_changed.emit("Bridge: mati (bridge.cfg belum diisi)")
		set_process(false)
		return
	_connect()


func _load_config() -> void:
	url = OS.get_environment("OFFICE_BRIDGE_URL")
	token = OS.get_environment("OFFICE_TOKEN")
	for path in ["res://bridge.cfg", "user://bridge.cfg"]:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			if url.is_empty():
				url = cfg.get_value("bridge", "url", "")
			if token.is_empty():
				token = cfg.get_value("bridge", "token", "")


func _connect() -> void:
	ws = WebSocketPeer.new()
	if not token.is_empty():
		ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + token])
	var err := ws.connect_to_url(url)
	if err != OK:
		_schedule_retry()
	else:
		state_changed.emit("Bridge: menghubungkan...")


func _schedule_retry() -> void:
	_retry = _backoff
	_backoff = minf(_backoff * 2.0, 30.0)
	state_changed.emit("Bridge: offline, coba lagi %ds" % int(_retry))


func _process(d: float) -> void:
	if _retry > 0.0:
		_retry -= d
		if _retry <= 0.0:
			_connect()
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_backoff = 1.0
				_last_state = ""
				state_changed.emit("Bridge: online")
			while ws.get_available_packet_count() > 0:
				_handle(ws.get_packet().get_string_from_utf8())
			_state_timer -= d
			if _state_timer <= 0.0:
				_state_timer = 2.0
				_push_state()
		WebSocketPeer.STATE_CLOSED:
			_connected = false
			_schedule_retry()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _handle(raw: String) -> void:
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	match data.get("type", ""):
		"command":
			var reply: String = main.run_command(str(data.get("text", "")))
			main.show_feedback("[remote] %s" % reply)
			_send({"type": "reply", "id": data.get("id"), "text": reply})
		"status":
			main.set_real_status(str(data.get("agent", "")), str(data.get("text", "")), float(data.get("ttl", 300)))


func _push_state() -> void:
	var list := []
	for a in main.agents:
		list.append({"name": a.agent_name, "status": a.status, "real": a.ext_status})
	var s := JSON.stringify(list)
	if s != _last_state:
		_last_state = s
		_send({"type": "state", "agents": list})
