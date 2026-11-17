extends RefCounted
## Minimal QR Code encoder (ISO/IEC 18004): byte mode, error correction level M,
## versions 1-6 (up to 106 bytes), automatic mask selection.
## Used to show the phone-controller address so the phone camera can open it.
## Algorithm follows the public-domain reference design by Project Nayuki.

const ECC_PER_BLOCK_M := [-1, 10, 16, 26, 18, 24, 16]
const BLOCKS_M := [-1, 1, 1, 1, 2, 2, 4]
const FORMAT_BITS_M := 0

## Returns an Array of Array[bool] (rows), true = dark. Empty array if the text is too long.
static func encode(text: String) -> Array:
	var data := text.to_utf8_buffer()
	var ver := 0
	for v in range(1, 7):
		var cap_bits := _data_codewords(v) * 8
		if 4 + 8 + data.size() * 8 <= cap_bits:
			ver = v
			break
	if ver == 0:
		return []
	# ---- bit stream
	var bits: Array[int] = []
	_append_bits(bits, 0x4, 4)
	_append_bits(bits, data.size(), 8)
	for b in data:
		_append_bits(bits, b, 8)
	var cap := _data_codewords(ver) * 8
	_append_bits(bits, 0, mini(4, cap - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < cap:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var codewords: Array[int] = []
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | bits[i + j]
		codewords.append(v)
	var all := _add_ecc_and_interleave(codewords, ver)
	# ---- matrix
	var size := ver * 4 + 17
	var mods := []
	var func_m := []
	for y in size:
		var r1 := []
		var r2 := []
		r1.resize(size)
		r2.resize(size)
		r1.fill(false)
		r2.fill(false)
		mods.append(r1)
		func_m.append(r2)
	_draw_function_patterns(mods, func_m, ver, size)
	_draw_codewords(mods, func_m, all, size)
	var best := -1
	var best_pen := 1 << 30
	for m in 8:
		_apply_mask(mods, func_m, m, size)
		_draw_format(mods, func_m, m, size)
		var pen := _penalty(mods, size)
		if pen < best_pen:
			best_pen = pen
			best = m
		_apply_mask(mods, func_m, m, size)    # undo (xor)
	_apply_mask(mods, func_m, best, size)
	_draw_format(mods, func_m, best, size)
	return mods

static func _append_bits(bits: Array[int], val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)

static func _raw_modules(ver: int) -> int:
	var r := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var na := ver / 7 + 2
		r -= (25 * na - 10) * na - 55
		if ver >= 7:
			r -= 36
	return r

static func _data_codewords(ver: int) -> int:
	return _raw_modules(ver) / 8 - ECC_PER_BLOCK_M[ver] * BLOCKS_M[ver]

static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF

static func _rs_divisor(degree: int) -> Array[int]:
	var res: Array[int] = []
	res.resize(degree)
	res.fill(0)
	res[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			res[j] = _gf_mul(res[j], root)
			if j + 1 < degree:
				res[j] ^= res[j + 1]
		root = _gf_mul(root, 0x02)
	return res

static func _rs_remainder(data: Array[int], div: Array[int]) -> Array[int]:
	var res: Array[int] = []
	res.resize(div.size())
	res.fill(0)
	for b in data:
		var factor: int = b ^ res[0]
		res.remove_at(0)
		res.append(0)
		for i in div.size():
			res[i] ^= _gf_mul(div[i], factor)
	return res

static func _add_ecc_and_interleave(data: Array[int], ver: int) -> Array[int]:
	var nblocks: int = BLOCKS_M[ver]
	var ecc_len: int = ECC_PER_BLOCK_M[ver]
	var raw := _raw_modules(ver) / 8
	var n_short := nblocks - raw % nblocks
	var short_len := raw / nblocks
	var div := _rs_divisor(ecc_len)
	var blocks := []
	var k := 0
	for i in nblocks:
		var n := short_len - ecc_len + (0 if i < n_short else 1)
		var dat: Array[int] = []
		for j in n:
			dat.append(data[k + j])
		k += n
		var ecc := _rs_remainder(dat, div)
		if i < n_short:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var out: Array[int] = []
	for i in (blocks[0] as Array).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= n_short:
				out.append(blocks[j][i])
	return out

static func _set_f(mods: Array, fm: Array, x: int, y: int, dark: bool) -> void:
	mods[y][x] = dark
	fm[y][x] = true

static func _draw_function_patterns(mods: Array, fm: Array, ver: int, size: int) -> void:
	for i in size:
		_set_f(mods, fm, 6, i, i % 2 == 0)
		_set_f(mods, fm, i, 6, i % 2 == 0)
	for c in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c.x + dx
				var y: int = c.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var dist := maxi(absi(dx), absi(dy))
					_set_f(mods, fm, x, y, dist != 2 and dist != 4)
	var pos := _align_positions(ver, size)
	var n := pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_f(mods, fm, pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format(mods, fm, 0, size)    # reserve the format areas

static func _align_positions(ver: int, size: int) -> Array[int]:
	var res: Array[int] = []
	if ver == 1:
		return res
	var na := ver / 7 + 2
	var step := (ver * 4 + na * 2 + 1) / (na * 2 - 2) * 2
	res.resize(na)
	res[0] = 6
	var p := size - 7
	for i in range(na - 1, 0, -1):
		res[i] = p
		p -= step
	return res

static func _draw_format(mods: Array, fm: Array, mask: int, size: int) -> void:
	var data := (FORMAT_BITS_M << 3) | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_f(mods, fm, 8, i, ((bits >> i) & 1) != 0)
	_set_f(mods, fm, 8, 7, ((bits >> 6) & 1) != 0)
	_set_f(mods, fm, 8, 8, ((bits >> 7) & 1) != 0)
	_set_f(mods, fm, 7, 8, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_f(mods, fm, 14 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(0, 8):
		_set_f(mods, fm, size - 1 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_f(mods, fm, 8, size - 15 + i, ((bits >> i) & 1) != 0)
	_set_f(mods, fm, 8, size - 8, true)

static func _draw_codewords(mods: Array, fm: Array, data: Array[int], size: int) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not fm[y][x] and i < data.size() * 8:
					mods[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0
					i += 1
		right -= 2

static func _apply_mask(mods: Array, fm: Array, m: int, size: int) -> void:
	for y in size:
		for x in size:
			if fm[y][x]:
				continue
			var inv := false
			match m:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				mods[y][x] = not mods[y][x]

## Penalty rules 1 (runs), 2 (2x2 blocks) and 4 (balance); rule 3 omitted (scanners cope).
static func _penalty(mods: Array, size: int) -> int:
	var pen := 0
	for y in size:
		var run := 1
		for x in range(1, size):
			if mods[y][x] == mods[y][x - 1]:
				run += 1
				if run == 5:
					pen += 3
				elif run > 5:
					pen += 1
			else:
				run = 1
	for x in size:
		var run2 := 1
		for y in range(1, size):
			if mods[y][x] == mods[y - 1][x]:
				run2 += 1
				if run2 == 5:
					pen += 3
				elif run2 > 5:
					pen += 1
			else:
				run2 = 1
	var dark := 0
	for y in size:
		for x in size:
			if mods[y][x]:
				dark += 1
			if x < size - 1 and y < size - 1:
				var c: bool = mods[y][x]
				if c == mods[y][x + 1] and c == mods[y + 1][x] and c == mods[y + 1][x + 1]:
					pen += 3
	var total := size * size
	var k := int(ceil(absf(dark * 20.0 - total * 10.0) / total)) - 1
	pen += maxi(k, 0) * 10
	return pen
