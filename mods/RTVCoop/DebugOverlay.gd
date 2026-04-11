extends CanvasLayer


var label: RichTextLabel
var font = load("res://Fonts/Lora-Medium.ttf")

const WHITE = "white"
const GREEN = "#8fc93a"
const RED = "#e05050"
const YELLOW = "#e0c850"
const BLUE = "#50a0e0"


func _ready():
    layer = 100

    label = RichTextLabel.new()
    label.bbcode_enabled = true
    label.fit_content = true
    label.scroll_active = false
    label.add_theme_font_override("normal_font", font)
    label.add_theme_font_size_override("normal_font_size", 14)
    label.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))

    label.anchor_left = 1.0
    label.anchor_right = 1.0
    label.anchor_top = 0.0
    label.anchor_bottom = 0.0
    label.offset_left = -260
    label.offset_right = -10
    label.offset_top = 10
    label.offset_bottom = 300
    label.grow_horizontal = Control.GROW_DIRECTION_BEGIN

    add_child(label)


func _val(color: String, value: String) -> String:
    return "[color=" + color + "]" + value + "[/color]"


func _process(_delta):
    var net = get_tree().root.get_node_or_null("Network")
    var pm = get_tree().root.get_node_or_null("PlayerManager")

    var lines: PackedStringArray = PackedStringArray()

    lines.append("[right]" + _val(YELLOW, "RTV COOP") + "[/right]")

    if net == null:
        lines.append("[right]Network: " + _val(RED, "NOT LOADED") + "[/right]")
    elif !net.IsActive():
        lines.append("[right]Network: " + _val(RED, "Disconnected") + "[/right]")
        lines.append("[right]" + _val(BLUE, "F9 Host | F10 Join") + "[/right]")
    elif net.IsHost():
        lines.append("[right]Network: " + _val(GREEN, "Host") + " (" + _val(BLUE, str(multiplayer.get_unique_id())) + ")[/right]")
        lines.append("[right]Peers: " + _val(GREEN, str(multiplayer.get_peers().size())) + "[/right]")
    else:
        lines.append("[right]Network: " + _val(GREEN, "Client") + " (" + _val(BLUE, str(multiplayer.get_unique_id())) + ")[/right]")

    if pm:
        if net and net.IsActive():
            lines.append("[right]You: " + _val(YELLOW, pm.GetMyDisplayName()) + "[/right]")
            if pm.peer_names.size() > 0:
                var ids = pm.peer_names.keys()
                ids.sort()
                for id in ids:
                    if id == multiplayer.get_unique_id():
                        continue
                    lines.append("[right]· " + _val(BLUE, str(pm.peer_names[id])) + "[/right]")
        lines.append("[right]Puppets: " + _val(BLUE, str(pm.remotePlayers.size())) + "[/right]")
        lines.append("[right]Items: " + _val(BLUE, str(pm.worldItems.size())) + "[/right]")
        lines.append("[right]AI: " + _val(BLUE, str(pm.worldAI.size())) + "[/right]")

    var scene = get_tree().current_scene
    if scene:
        var mapName = scene.get("mapName") if scene.get("mapName") else scene.name
        lines.append("[right]Scene: " + _val(YELLOW, str(mapName)) + "[/right]")

    var gameData = load("res://Resources/GameData.tres")
    if gameData:
        var wpos = str(gameData.get("weaponPosition")) if gameData.get("weaponPosition") != null else "?"
        var moving = str(gameData.get("isMoving")) if gameData.get("isMoving") != null else "?"
        var running = str(gameData.get("isRunning")) if gameData.get("isRunning") != null else "?"
        var aiming = str(gameData.get("isAiming")) if gameData.get("isAiming") != null else "?"
        var crouching = str(gameData.get("isCrouching")) if gameData.get("isCrouching") != null else "?"
        lines.append("[right]WpnPos: " + _val(YELLOW, wpos) + " Move: " + _val(BLUE, moving) + " Run: " + _val(BLUE, running) + "[/right]")
        lines.append("[right]Aim: " + _val(BLUE, aiming) + " Crouch: " + _val(BLUE, crouching) + "[/right]")

    lines.append("[right]FPS: " + _val(GREEN, str(Engine.get_frames_per_second())) + "[/right]")

    label.text = "\n".join(lines)
