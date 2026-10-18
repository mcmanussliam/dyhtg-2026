class_name CrumblingEdge
extends RefCounted
## Physics-clock fracture progression. Every consumer shares this exact chipped outline.
## Revisions drive floor, collider and carpet rebuilds; pending polygons warn before loss.

const SAMPLES := 512

var outline := PackedVector2Array()
var warning: Array[PackedVector2Array] = []
var fallen: Array[PackedVector2Array] = []
var revision := 0
var warning_revision := 0
var elapsed := 0.0
var grace_seconds := 15.0
var _initial := 0.0
var _final := 0.0
var _expanding := false
var _next_at := 16.2
var _step := 0
var _pending := PackedVector2Array()
var _limits := PackedFloat32Array()
var _sent_revision := 0
var _sent_warning := 0


func configure(radius: float, final_radius: float, expanding: bool) -> void:
	_initial = radius
	_final = final_radius
	_expanding = expanding
	outline = ColumnGeometry.outline(radius)
	_rebuild_limits()


func advance(delta: float) -> bool:
	elapsed += maxf(delta, 0)
	fallen.clear()
	if _pending.is_empty() and elapsed >= _next_at - 1.1:
		_pending = _next_outline()
		warning = _removed(outline, _pending)
		warning_revision += 1
	if elapsed < _next_at or _pending.is_empty():
		return false
	fallen = warning.duplicate()
	outline = _pending
	_pending = PackedVector2Array()
	warning.clear()
	warning_revision += 1
	revision += 1
	_step += 1
	_next_at = elapsed + lerpf(2.0, 1.5, clampf((elapsed - grace_seconds) / 65, 0, 1))
	_rebuild_limits()
	return true


## Host: the latest unsent change as a plain payload for clients, else null.
## A step carries the whole outline, so a client never depends on missed warnings.
func take_net_event() -> Variant:
	if revision != _sent_revision:
		_sent_revision = revision
		_sent_warning = warning_revision
		return {"k": "crack", "r": revision, "o": outline, "f": Array(fallen)}
	if warning_revision != _sent_warning:
		_sent_warning = warning_revision
		return {"k": "crack_warn", "r": revision, "w": Array(warning)}
	return null


## Client: replay one host payload. Returns true when the outline itself changed.
## Stale or repeated payloads are ignored; `fallen` holds the new departures until cleared.
func apply_net_event(payload: Dictionary) -> bool:
	var at: int = payload.get("r") if payload.get("r") is int else -1
	if payload.get("k") == "crack_warn" and at == revision:
		warning.clear()
		for polygon: PackedVector2Array in payload.get("w", []):
			warning.append(polygon)
		warning_revision += 1
		return false
	if payload.get("k") != "crack" or at <= revision or not payload.get("o") is PackedVector2Array:
		return false
	fallen.clear()
	for polygon: PackedVector2Array in payload.get("f", []):
		fallen.append(polygon)
	outline = payload.o
	warning.clear()
	warning_revision += 1
	revision = at
	_rebuild_limits()
	return true


func radius_at(direction: Vector2) -> float:
	var sample := fposmod(direction.angle(), TAU) * SAMPLES / TAU
	var index := int(sample) % SAMPLES
	# Adjacent maxima conservatively cover sharp fracture corners for AI steering.
	return maxf(_limits[index], _limits[(index + 1) % SAMPLES]) + 1.0


func _next_outline() -> PackedVector2Array:
	var result := outline.duplicate()
	# Broad sections advance the least-eroded parts of the rim first. Bounding the
	# normalized radius spread preserves the authored rough-circle silhouette.
	for piece in 4:
		var selected := 0
		var extreme := -INF if not _expanding else INF
		var offset := (_step * 17 + piece * 29 + 7) % outline.size()
		for sample in result.size():
			var index := (offset + sample) % result.size()
			var normalized: float = result[index].length() / ColumnGeometry.RIM[index].length()
			if normalized > extreme if not _expanding else normalized < extreme:
				extreme = normalized
				selected = index
		for local in 4:
			var index := (selected + local) % result.size()
			var unit: Vector2 = ColumnGeometry.RIM[index]
			var current := result[index].length() / unit.length()
			var chip := lerpf(36, 48, fposmod(index * 0.618 + _step * 0.381, 1))
			var next := (
				maxf(current - chip, extreme - 55)
				if not _expanding
				else minf(current + chip, extreme + 55)
			)
			next = maxf(next, _final) if not _expanding else minf(next, _final)
			result[index] = unit * next
	return result


func _removed(before: PackedVector2Array, after: PackedVector2Array) -> Array[PackedVector2Array]:
	# Adjacent chips fall as one connected section, including their full foundation.
	return (
		Geometry2D.clip_polygons(after, before)
		if _expanding
		else Geometry2D.clip_polygons(before, after)
	)


func _rebuild_limits() -> void:
	_limits.resize(SAMPLES)
	var edge := 0
	for index in SAMPLES:
		var angle := index * TAU / SAMPLES
		while edge + 1 < outline.size() and fposmod(outline[edge + 1].angle(), TAU) < angle:
			edge += 1
		var first := outline[edge]
		var segment := outline[(edge + 1) % outline.size()] - first
		var direction := Vector2.from_angle(angle)
		_limits[index] = first.cross(segment) / direction.cross(segment)
