extends Control
signal focus_requested(point: Vector3)
var state: Dictionary = {}

func _ready() -> void:
    custom_minimum_size = Vector2(146, 104)
    mouse_filter = Control.MOUSE_FILTER_STOP
    tooltip_text = "Click to move the camera. The whole battlefield remains visible."

func map_point(x: float, z: float) -> Vector2:
    return Vector2((x + 26.0) / 52.0 * size.x, (z + 19.0) / 38.0 * size.y)

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#233e3a"))
    draw_rect(Rect2(Vector2.ZERO, size), Color("#b89c65"), false, 1.0)
    for territory in state.get("territories", []):
        var color: Color = Color("#54aa8d") if territory.get("secured", false) else Color("#899478")
        draw_circle(map_point(territory.x, territory.z), 5.0, color)
    for building in state.get("buildings", []):
        var color: Color = Color("#50b7c3") if building.team == "ally" else Color("#d47579")
        draw_rect(Rect2(map_point(building.x, building.z) - Vector2(3,3), Vector2(6,6)), color)
    for unit in state.get("units", []):
        draw_circle(map_point(unit.x, unit.z), 2.1, Color("#a4f0e7") if unit.team == "ally" else Color("#ff9595"))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        focus_requested.emit(Vector3(event.position.x / size.x * 52.0 - 26.0, 0, event.position.y / size.y * 38.0 - 19.0))
        accept_event()
