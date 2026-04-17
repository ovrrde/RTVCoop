extends CanvasLayer


var label: Label
var font = load("res://Fonts/Lora-Medium.ttf")


func _ready():
    layer = 90
    label = Label.new()
    label.add_theme_font_override("font", font)
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
    label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
    label.add_theme_constant_override("outline_size", 5)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.anchor_left = 0.0
    label.anchor_right = 1.0
    label.anchor_top = 0.0
    label.offset_top = 80
    label.offset_bottom = 130
    label.visible = false
    add_child(label)


func _process(_delta):
    var pm = get_tree().root.get_node_or_null("PlayerManager")
    if !pm:
        label.visible = false
        return
    var net = get_tree().root.get_node_or_null("Network")
    if !net or !net.IsActive():
        label.visible = false
        return
    var ready_ids: Array = pm.get_meta("coop_sleep_ready_ids") if pm.has_meta("coop_sleep_ready_ids") else []
    var total: int = pm.get_meta("coop_sleep_total") if pm.has_meta("coop_sleep_total") else 0
    if total <= 1 or ready_ids.is_empty():
        label.visible = false
        return
    label.visible = true
    label.text = "Sleeping: " + str(ready_ids.size()) + "/" + str(total) + " ready"
