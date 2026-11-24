class_name MapPanel
extends MapView
## One map drawn clipped to this control: the big map (BigMap) and the squad orders
## map (SquadMap) put one where their map goes, so a zoomed-in picture doesn't spill
## over the screen. The owner sets centre, scale_px and its size every draw.

## World point (x, z) at the panel's centre, and pixels per metre.
var centre: Vector2 = Vector2.ZERO
var scale_px: float = 1.0
## Called as overlay.call(panel, rect) after the map, for the owner's own marks.
var overlay: Callable


## A panel for `source`: same views, marks and look (its MapView exports).
static func make_for(source: MapView) -> MapPanel:
	var panel := MapPanel.new()
	for prop: Dictionary in source.get_property_list():
		var usage: int = prop["usage"]
		var prop_name: String = prop["name"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE \
				and prop_name in panel:
			panel.set(prop_name, source.get(prop_name))
	source.add_child(panel)
	return panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_map(rect, centre, scale_px)
	if overlay.is_valid():
		overlay.call(self, rect)
