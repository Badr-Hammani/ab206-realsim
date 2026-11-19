extends Node
## Downloads web map tiles (JPEG/PNG) and hands them over as Images.
## - PC / desktop builds: a small pool of HTTPRequest nodes.
## - Web builds: the browser loads each tile as an <img> (crossOrigin anonymous) and decodes it on a
##   canvas; Godot reads the raw RGBA pixels back through JavaScriptBridge. This works even where a
##   page may load cross-origin images but not fetch() them, and the browser's JPEG decoder is much
##   faster than decoding in WebAssembly.
## Signals: tile_ready(key, image) or tile_failed(key). Nothing is written to disk.

signal tile_ready(key: String, img: Image)
signal tile_failed(key: String)

var max_req := 6
var web := false
var _free: Array[HTTPRequest] = []
var _busy := {}            # key -> true (web) or HTTPRequest (desktop)
var _js_ok := false
var ok_count := 0
var fail_count := 0

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

func _ready() -> void:
	web = OS.has_feature("web")
	if web:
		_js_ok = JavaScriptBridge.eval(JS, true) == true
		return
	for i in 8:
		var r := HTTPRequest.new()
		r.timeout = 12.0
		add_child(r)
		r.request_completed.connect(_done.bind(r))
		_free.append(r)

func busy() -> int:
	return _busy.size()

func can_request() -> bool:
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
	var r: HTTPRequest = _free.pop_back()
	r.set_meta("key", key)
	if r.request(url) != OK:
		_free.append(r)
		_fail(key)
		return false
	_busy[key] = r
	return true

func _process(_d: float) -> void:
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
		_fail(key)
		return
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body) if body[0] == 0xFF else img.load_png_from_buffer(body)
	if err != OK:
		_fail(key)
		return
	ok_count += 1
	tile_ready.emit(key, img)

func _fail(key: String) -> void:
	fail_count += 1
	tile_failed.emit(key)
