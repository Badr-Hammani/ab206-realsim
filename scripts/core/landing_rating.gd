extends RefCounted
## Touchdown rating from vertical sink rate at first skid contact.
## Thresholds are simulator estimates, not Bell inspection criteria.

static func rate(sink_mps: float) -> String:
	if sink_mps < 0.5:
		return "SMOOTH"
	if sink_mps < 1.5:
		return "NORMAL"
	if sink_mps < 2.5:
		return "FIRM"
	if sink_mps < 4.0:
		return "HARD"
	return "DAMAGE"
