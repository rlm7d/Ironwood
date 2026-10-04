extends Control
var camera: Camera3D
var state: Dictionary = {}
var selected: Array[String] = []
var selected_building: String = ""

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
    if camera == null:
        return
    var font: Font = ThemeDB.fallback_font
    for entity in state.get("units",[]) + state.get("buildings",[]):
        if float(entity.hp) <= 0:
            continue
        var position: Vector3 = Vector3(float(entity.x),2.1 if entity.has("count") else 4.5,float(entity.z))
        if camera.is_position_behind(position):
            continue
        var point: Vector2 = camera.unproject_position(position)
        var chosen: bool = str(entity.id) in selected or str(entity.id) == selected_building
        var width: float = 34.0 if entity.has("count") else 45.0
        var start: Vector2 = point - Vector2(width * 0.5,0)
        draw_rect(Rect2(start - Vector2(1,1),Vector2(width + 2,5)),Color("#152222"))
        var color: Color = Color("#7bd3b1") if entity.team == "ally" else Color("#dc8077")
        draw_rect(Rect2(start,Vector2(width * clampf(float(entity.hp) / maxf(1.0,float(entity.max_hp)),0,1),3)),color)
        if chosen:
            draw_string(font,point + Vector2(-width * 0.5,-7),str(entity.kind).capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#fff1bb"))
    for worker in state.get("workers",[]):
        if int(worker.get("carry",0)) > 0:
            var point: Vector2 = camera.unproject_position(Vector3(float(worker.x),1.8,float(worker.z)))
            draw_circle(point,3.2,Color("#f2cc62"))
