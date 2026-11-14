class_name ScrollEdgeArrows
extends Node3D

## Visual hints only: no collision shapes or mouse interception.
## Desktop anchors follow window resizing; XR meshes ride the camera.
const COLOR: Color = Color(1.0, 0.72, 0.30, 0.9)
const DESKTOP_HEIGHT: float = 48.0
const XR_DEPTH: float = 1.8
const XR_HEIGHT: float = 0.16

var _xr: bool = false
var _left_2d: Control
var _right_2d: Control
var _left_3d: MeshInstance3D
var _right_3d: MeshInstance3D


func setup(xr: bool) -> void:
	_xr = xr
	if xr:
		_left_3d = _mesh_arrow(-1)
		_right_3d = _mesh_arrow(1)
	else:
		var layer: CanvasLayer = CanvasLayer.new()
		add_child(layer)
		var overlay: Control = Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_left_2d = _window_arrow(overlay, -1)
		_right_2d = _window_arrow(overlay, 1)
	set_available(false, false)


func set_available(left: bool, right: bool) -> void:
	if _xr:
		_left_3d.visible = left
		_right_3d.visible = right
	else:
		_left_2d.visible = left
		_right_2d.visible = right


static func _chevron(direction: int, height: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-0.32, -0.5), Vector2(-0.08, -0.5), Vector2(0.38, 0),
		Vector2(-0.08, 0.5), Vector2(-0.32, 0.5), Vector2(0.14, 0)])
	for i: int in range(points.size()):
		points[i] *= Vector2(direction * height, height)
	return points


func _window_arrow(overlay: Control, direction: int) -> Control:
	var anchor: Control = Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(anchor)
	var edge: float = PointerEdgeScroll.MOUSE_EDGE_FRACTION * 0.5
	anchor.anchor_left = edge if direction < 0 else 1.0 - edge
	anchor.anchor_right = anchor.anchor_left
	anchor.anchor_top = 0.5
	anchor.anchor_bottom = 0.5
	var shadow: Polygon2D = Polygon2D.new()
	shadow.polygon = _chevron(direction, DESKTOP_HEIGHT)
	shadow.color = Color(0, 0, 0, 0.65)
	shadow.position = Vector2(0, 2)
	anchor.add_child(shadow)
	var arrow: Polygon2D = Polygon2D.new()
	arrow.polygon = shadow.polygon
	arrow.color = COLOR
	anchor.add_child(arrow)
	return anchor


func _mesh_arrow(direction: int) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = COLOR
	var points: PackedVector2Array = _chevron(direction, XR_HEIGHT)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index: int in triangles:
		mesh.surface_add_vertex(Vector3(points[index].x, -points[index].y, 0))
	mesh.surface_end()
	var arrow: MeshInstance3D = MeshInstance3D.new()
	arrow.mesh = mesh
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.position = Vector3(direction * tan(PointerEdgeScroll.VR_EDGE_ANGLE_RAD) * XR_DEPTH, 0, -XR_DEPTH)
	add_child(arrow)
	return arrow
