extends Node
## Downloads web map tiles (JPEG/PNG) and hands them over as Images.
## - PC / desktop builds: a small pool of HTTPRequest nodes.
## - Web builds: the browser loads each tile as an <img> (crossOrigin anonymous) and decodes it on a
##   canvas; Godot reads the raw RGBA pixels back through JavaScriptBridge. This works even where a
##   page may load cross-origin images but not fetch() them, and the browser's JPEG decoder is much
##   faster than decoding in WebAssembly.
## Signals: tile_ready(key, image) or tile_failed(key).
## PC builds keep every downloaded tile on disk (user://hd_cache, see disk_path), so places you have
## seen once, and the areas fetched by hd_prefetch.gd, are sharp again next time, even offline.
## Web builds keep nothing on disk (the browser caches by itself).

signal tile_ready(key: String, img: Image)
signal tile_failed(key: String)

var max_req := 6
var web := false
var _free: Array[HTTPRequest] = []
var _busy := {}            # key -> true (web) or HTTPRequest (desktop)
var _js_ok := false
var ok_count := 0
var fail_count := 0
var host := ""             # web: the page's host name (HD photos are blocked inside some app pages)
const PLAY_URL := "badr-hammani.github.io/ab206-realsim"
static var cache_dir := "user://hd_cache"   # tests use their own folder
const DISK_LOADS_PER_FRAME := 3
var use_disk := true       # PC only (set false in tests that need a real download)
var disk_hits := 0
var last_error := ""       # why the last download failed (shown in the log)
var _disk_q: Array = []    # [key, path] waiting to be decoded from disk

const JS := """
(function(){
  if (window.ab206hd) return true;
  var cv = document.createElement('canvas'); cv.width = 256; cv.height = 256;
  var g = cv.getContext('2d', {willReadFrequently: true});
  var H = window.ab206hd = {q: {}, done: []};
  H.req = function(k, u){
    var im = new Image(); im.crossOrigin = 'anonymous'; im.decoding = 'async';
    im.onload = function(){
      try { g.clearRect(0, 0, 256, 256); g.drawImage(im, 0, 0, 256, 256);
        var d = g.getImageData(0, 0, 256, 256).data; H.q[k] = new Uint8Array(d.buffer); H.done.push(k + '|1');
      } catch (e) { H.done.push(k + '|0'); }
    };
    im.onerror = function(){ H.done.push(k + '|0'); };
    im.src = u;
  };
  H.poll = function(){ var s = H.done.join(','); H.done = []; return s; };
  H.take = function(k){ var v = H.q[k]; delete H.q[k]; return v || null; };
  return true;
})()
"""

## Disk file for a tile URL: user://hd_cache/<z>/<md5 of the url>.jpg (the zoom level is the folder so
## a whole level can be counted or removed).
static func disk_path(url: String) -> String:
	var z := "x"
	var m := url.rsplit("/", false, 3)
	if m.size() == 4 and m[1].is_valid_int():
		z = m[1]
	return "%s/%s/%s.img" % [cache_dir, z, url.md5_text()]

static func on_disk(url: String) -> bool:
	return FileAccess.file_exists(disk_path(url))

func _ready() -> void:
	web = OS.has_feature("web")
	if web:
		use_disk = false
	if web:
		JavaScriptBridge.eval(JS, true)
		_js_ok = JavaScriptBridge.get_interface("ab206hd") != null
		var h = JavaScriptBridge.eval("location.hostname", true)
		host = str(h) if h != null else ""
		print("HD tiles: browser image loader %s" % ("ready" if _js_ok else "NOT available"))
		return
	for i in 8:
		var r := HTTPRequest.new()
		r.timeout = 12.0
		add_child(r)
		r.request_completed.connect(_done.bind(r))
		_free.append(r)

## What to tell the player when no tile could be loaded.
func blocked_text() -> String:
	if web and not host.ends_with("github.io") and not host.begins_with("127.") and host != "localhost":
		return "HD photo is blocked on this page. For HD, open %s in Safari." % PLAY_URL
	return "HD photo needs internet (not reachable)."

func busy() -> int:
	return _busy.size()

func can_request() -> bool:
	if not web and use_disk:
		return _busy.size() < max_req + DISK_LOADS_PER_FRAME * 4
	return _busy.size() < max_req and (_js_ok if web else not _free.is_empty())

func is_busy(key: String) -> bool:
	return _busy.has(key)

func request(key: String, url: String) -> bool:
	if _busy.has(key) or not can_request():
		return false
	if web:
		JavaScriptBridge.eval("window.ab206hd.req(%s, %s)" % [JSON.stringify(key), JSON.stringify(url)], true)
		_busy[key] = true
		return true
	if use_disk:
		var path := disk_path(url)
		if FileAccess.file_exists(path):
			_busy[key] = true
			_disk_q.append([key, path])
			return true
		if _free.is_empty() or _busy.size() - _disk_q.size() >= max_req:
			return false
	var r: HTTPRequest = _free.pop_back()
	r.set_meta("key", key)
	r.set_meta("url", url)
	if r.request(url) != OK:
		_free.append(r)
		_fail(key)
		return false
	_busy[key] = r
	return true

func _process(_d: float) -> void:
	var n := 0
	while not _disk_q.is_empty() and n < DISK_LOADS_PER_FRAME:
		n += 1
		var item: Array = _disk_q.pop_front()
		var key: String = item[0]
		_busy.erase(key)
		var img := _decode(FileAccess.get_file_as_bytes(item[1]))
		if img == null:
			DirAccess.remove_absolute(item[1])   # broken file: download it again next time
			_fail(key)
			continue
		ok_count += 1
		disk_hits += 1
		tile_ready.emit(key, img)
	if not web or not _js_ok or _busy.is_empty():
		return
	var s = JavaScriptBridge.eval("window.ab206hd.poll()", true)
	if typeof(s) != TYPE_STRING or s == "":
		return
	for item in (s as String).split(","):
		var p := item.split("|")
		if p.size() < 2:
			continue
		var key := p[0]
		_busy.erase(key)
		if p[1] != "1":
			_fail(key)
			continue
		var px = JavaScriptBridge.eval("window.ab206hd.take(%s)" % JSON.stringify(key), true)
		if typeof(px) != TYPE_PACKED_BYTE_ARRAY or (px as PackedByteArray).size() != 256 * 256 * 4:
			_fail(key)
			continue
		var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, px)
		ok_count += 1
		tile_ready.emit(key, img)

func _done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, r: HTTPRequest) -> void:
	var key := str(r.get_meta("key", ""))
	_busy.erase(key)
	_free.append(r)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 100:
		last_error = "result %d, HTTP %d, %d bytes" % [result, code, body.size()]
		_fail(key)
		return
	var img := _decode(body)
	if img == null:
		_fail(key)
		return
	if use_disk:
		save_to_disk(str(r.get_meta("url", "")), body)
	ok_count += 1
	tile_ready.emit(key, img)

static func _decode(body: PackedByteArray) -> Image:
	if body.size() < 100:
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body) if body[0] == 0xFF else img.load_png_from_buffer(body)
	return img if err == OK else null

static func save_to_disk(url: String, body: PackedByteArray) -> void:
	if url == "":
		return
	var path := disk_path(url)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()

func _fail(key: String) -> void:
	fail_count += 1
	tile_failed.emit(key)
