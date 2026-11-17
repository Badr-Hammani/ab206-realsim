extends RefCounted
## Trim solver: finds collective, cyclic, pedal, pitch and roll that give zero
## linear and angular acceleration for a requested steady flight condition.
## Newton-Raphson with a finite-difference Jacobian (6 x 6).
## Used for the "reset to hover / cruise / autorotation entry" states and by the tests.

static func _eval(fdm, x: Array, heading: float, target_vel: Vector3) -> Array:
	fdm.collective = x[0]
	fdm.cyclic_lon = x[1]
	fdm.cyclic_lat = x[2]
	fdm.pedal = x[3]
	fdm.set_attitude(heading, rad_to_deg(x[4]), rad_to_deg(x[5]))
	fdm.vel = target_vel
	fdm.omega = Vector3.ZERO
	fdm.nr = fdm.omega100
	fdm.n2 = fdm.omega100
	var out = {}
	for i in 5:
		fdm.compute_aero(out)
		fdm.a1 = fdm.a1_ss
		fdm.b1 = fdm.b1_ss
		fdm.q_clutch = out["q_load"]
	var Fw: Vector3 = fdm.aero_to_world(out["F"]) + Vector3(0.0, -fdm.mass * fdm.G, 0.0)
	var M: Vector3 = out["M"]
	var acc = Fw / fdm.mass
	return [acc.x, acc.y, acc.z, M.x / fdm.inertia.x * 10.0, M.y / fdm.inertia.y * 10.0, M.z / fdm.inertia.z * 10.0]

static func _solve(Jm: Array, b: Array) -> Array:
	var n = b.size()
	var m = []
	for i in n:
		var row: Array = Jm[i].duplicate()
		row.append(b[i])
		m.append(row)
	for col in n:
		var piv = col
		for r in range(col + 1, n):
			if absf(m[r][col]) > absf(m[piv][col]):
				piv = r
		var tmp = m[col]
		m[col] = m[piv]
		m[piv] = tmp
		if absf(m[col][col]) < 1e-12:
			continue
		for r in range(col + 1, n):
			var f: float = m[r][col] / m[col][col]
			for c in range(col, n + 1):
				m[r][c] -= f * m[col][c]
	var xs = []
	xs.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = m[i][n]
		for c in range(i + 1, n):
			s -= m[i][c] * xs[c]
		xs[i] = s / m[i][i] if absf(m[i][i]) > 1e-12 else 0.0
	return xs

## Trims the fdm in place. Returns the final residual norm (small = trimmed).
static func trim(fdm, heading: float, target_vel: Vector3) -> float:
	var x = [0.5, 0.0, 0.0, -0.2, 0.0, 0.0]
	var lo = [0.0, -1.0, -1.0, -1.0, -0.6, -0.6]
	var hi = [1.0, 1.0, 1.0, 1.0, 0.6, 0.6]
	var res = _eval(fdm, x, heading, target_vel)
	var norm = 1e9
	for it in 40:
		norm = 0.0
		for v in res:
			norm += v * v
		norm = sqrt(norm)
		if norm < 1e-4:
			break
		var J = []
		for i in 6:
			J.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for j in 6:
			var xp = x.duplicate()
			var h = 1e-4
			xp[j] += h
			var rp = _eval(fdm, xp, heading, target_vel)
			for i in 6:
				J[i][j] = (rp[i] - res[i]) / h
		var neg = []
		for v in res:
			neg.append(-v)
		var dx = _solve(J, neg)
		var step = 1.0
		var best = res
		var best_x = x
		for k in 6:
			var xn = x.duplicate()
			for j in 6:
				xn[j] = clampf(x[j] + dx[j] * step, lo[j], hi[j])
			var rn = _eval(fdm, xn, heading, target_vel)
			var nn = 0.0
			for v in rn:
				nn += v * v
			if sqrt(nn) < norm:
				best = rn
				best_x = xn
				break
			step *= 0.5
		x = best_x
		res = best
	_eval(fdm, x, heading, target_vel)
	# put the engine where it needs to be for this load
	var out = {}
	fdm.compute_aero(out)
	var dens_ratio: float = (fdm.atmo.pressure_pa(fdm.pos.y) / 101325.0) / sqrt(fdm.atmo.temperature_k(fdm.pos.y) / 288.15)
	var p_need: float = out["q_load"] * fdm.omega100
	# torque at 100% speed: P/w * (2 - 1) - 150 => solve gas power
	var p_gas = p_need + 150.0 * fdm.omega100
	fdm.n1 = fdm.n1_for_power(p_gas, dens_ratio)
	var p_ff = lerpf(30000.0, 230000.0, pow(clampf(fdm.collective, 0.0, 1.0), 1.3))
	fdm.gov_int = fdm.n1 - fdm.n1_for_power(p_ff, dens_ratio)
	fdm.q_clutch = out["q_load"]
	fdm.engaged = true
	fdm.throttle = 1.0
	fdm.torque_pct = fdm.q_clutch / fdm.q100 * 100.0
	return norm
