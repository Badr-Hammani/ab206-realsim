extends RefCounted
## ISA atmosphere, wind and turbulence.
## Wind is given as "from" direction (degrees true) and speed in knots, like a METAR.

const KT := 0.514444
const RHO0 := 1.225

var temp_offset_c: float = 0.0       # ISA deviation
var wind_from_deg: float = 270.0
var wind_speed_kt: float = 5.0
var gust_intensity: float = 0.2      # 0 = calm air, 1 = strong turbulence (sigma ~ 2.5 m/s)

var _turb := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 2060203

func temperature_k(alt_m: float) -> float:
	return 288.15 + temp_offset_c - 0.0065 * clampf(alt_m, -500.0, 11000.0)

func pressure_pa(alt_m: float) -> float:
	# Pressure follows the standard lapse (temperature offset does not change pressure altitude)
	return 101325.0 * pow(1.0 - 0.0065 * clampf(alt_m, -500.0, 11000.0) / 288.15, 5.25588)

func density(alt_m: float) -> float:
	return pressure_pa(alt_m) / (287.053 * temperature_k(alt_m))

func density_altitude_ft(alt_m: float) -> float:
	var sigma := density(alt_m) / RHO0
	return (1.0 - pow(sigma, 0.234969)) * 145442.0

## Mean wind vector in Godot world space (X east, Y up, Z south), metres/second,
## reduced near the ground with a log profile (surface roughness 0.05 m, reference 10 m).
func mean_wind(height_agl: float) -> Vector3:
	var from_rad := deg_to_rad(wind_from_deg)
	# Direction the wind comes FROM, in world coordinates (north = -Z)
	var from_vec := Vector3(sin(from_rad), 0.0, -cos(from_rad))
	var h := maxf(height_agl, 0.3)
	var profile := clampf(log(h / 0.05) / log(10.0 / 0.05), 0.25, 1.35)
	return -from_vec * wind_speed_kt * KT * profile

## Advance the turbulence filter (first-order Gauss-Markov per axis, Dryden-like).
func step_turbulence(dt: float, airspeed: float, height_agl: float) -> void:
	var sigma := gust_intensity * 2.5 * clampf(0.4 + wind_speed_kt / 25.0, 0.4, 1.6)
	var length := clampf(30.0 + height_agl * 0.5, 30.0, 300.0)
	var tau := length / maxf(airspeed, 5.0)
	var a := exp(-dt / tau)
	var b := sigma * sqrt(1.0 - a * a)
	_turb.x = a * _turb.x + b * _rng.randfn()
	_turb.y = a * _turb.y + b * 0.6 * _rng.randfn()
	_turb.z = a * _turb.z + b * _rng.randfn()

func wind_at(height_agl: float) -> Vector3:
	return mean_wind(height_agl) + _turb
