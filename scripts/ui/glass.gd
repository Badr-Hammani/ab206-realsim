extends RefCounted
## Shared "glass" look for the setup screens (phone F10, joystick F8), same style as the pause menu.

const Menu = preload("res://scripts/ui/menu.gd")
const ACCENT := Color(0.24, 0.56, 1.0)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT2 := Color(0.97, 0.98, 1.0, 0.62)
const TEXT3 := Color(0.97, 0.98, 1.0, 0.42)
const GOOD := Color(0.35, 0.86, 0.47)
const WARN := Color(1.0, 0.78, 0.35)
const DANGER := Color(1.0, 0.38, 0.35)

static func box(bg: Color, radius: int, border_alpha: float, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	if border_alpha > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, border_alpha)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb

## Blurred, darkened copy of the sim behind a panel.
static func backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = Menu.BLUR_SHADER
	sm.shader = sh
	r.material = sm
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r

## Main frosted card.
static func card() -> StyleBoxFlat:
	return box(Color(0.11, 0.13, 0.17, 0.78), 26, 0.16, 26)

## Inner section card.
static func section() -> StyleBoxFlat:
	return box(Color(1, 1, 1, 0.06), 16, 0.07, 14)

static func label(text: String, size := 15, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Rounded meter: centred (-1..1) or from the left (0..1).
static func meter(ci: CanvasItem, rect: Rect2, val: float, centred: bool) -> void:
	ci.draw_style_box(box(Color(1, 1, 1, 0.12), int(rect.size.y * 0.5), 0.0, 0), rect)
	var r := rect
	if centred:
		var mid := rect.position.x + rect.size.x * 0.5
		var w := absf(clampf(val, -1.0, 1.0)) * rect.size.x * 0.5
		r = Rect2(Vector2(mid - (w if val < 0.0 else 0.0), rect.position.y), Vector2(w, rect.size.y))
		ci.draw_rect(Rect2(Vector2(mid - 1, rect.position.y - 2), Vector2(2, rect.size.y + 4)), Color(1, 1, 1, 0.35))
	else:
		r.size.x = clampf(val, 0.0, 1.0) * rect.size.x
	if r.size.x > 0.5:
		ci.draw_style_box(box(ACCENT, int(rect.size.y * 0.5), 0.0, 0), r)
