extends "res://Scripts/Menu.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


var fontMedium = load("res://Fonts/Lora-Medium.ttf")
var fontSemiBold = load("res://Fonts/Lora-SemiBold.ttf")

var coopPanel: Control
var coopButton: Button
var statusLabel: RichTextLabel
var ipInput: LineEdit
var hostBtn: Button
var joinBtn: Button
var dcBtn: Button

const ACCENT = Color(0.56, 0.79, 0.23, 1.0)


func _ready():
    super()
    _create_coop_button()
    _create_coop_panel()


func _create_coop_button():
    var buttonsContainer = get_node_or_null("Main/Buttons")
    if !buttonsContainer:
        print("[RTVCoop] Menu: Buttons container not found")
        return

    var templateBtn = buttonsContainer.get_child(0)
    if !templateBtn:
        return

    coopButton = templateBtn.duplicate()
    coopButton.text = "Co-op"

    for sig in coopButton.get_signal_list():
        for conn in coopButton.get_signal_connection_list(sig.name):
            coopButton.disconnect(sig.name, conn.callable)

    coopButton.pressed.connect(_on_coop_pressed)

    var quitIndex = buttonsContainer.get_child_count() - 1
    buttonsContainer.add_child(coopButton)
    buttonsContainer.move_child(coopButton, quitIndex)


func _create_coop_panel():
    coopPanel = Control.new()
    coopPanel.set_anchors_preset(Control.PRESET_FULL_RECT)
    coopPanel.hide()
    add_child(coopPanel)

    var center = VBoxContainer.new()
    center.set_anchors_preset(Control.PRESET_CENTER)
    center.anchor_left = 0.5
    center.anchor_right = 0.5
    center.anchor_top = 0.4
    center.anchor_bottom = 0.6
    center.offset_left = -160
    center.offset_right = 160
    center.offset_top = -120
    center.offset_bottom = 120
    center.grow_horizontal = Control.GROW_DIRECTION_BOTH
    center.grow_vertical = Control.GROW_DIRECTION_BOTH
    center.add_theme_constant_override("separation", 12)
    coopPanel.add_child(center)

    var title = Label.new()
    title.text = "CO-OP"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_override("font", fontSemiBold)
    title.add_theme_font_size_override("font_size", 24)
    title.add_theme_color_override("font_color", ACCENT)
    center.add_child(title)

    statusLabel = RichTextLabel.new()
    statusLabel.bbcode_enabled = true
    statusLabel.fit_content = true
    statusLabel.scroll_active = false
    statusLabel.add_theme_font_override("normal_font", fontMedium)
    statusLabel.add_theme_font_size_override("normal_font_size", 14)
    statusLabel.text = "[center]Disconnected[/center]"
    center.add_child(statusLabel)

    center.add_child(_spacer(4))

    var ipLabel = Label.new()
    ipLabel.text = "Server Address"
    ipLabel.add_theme_font_override("font", fontMedium)
    ipLabel.add_theme_font_size_override("font_size", 12)
    ipLabel.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
    ipLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    center.add_child(ipLabel)

    ipInput = LineEdit.new()
    ipInput.placeholder_text = "127.0.0.1"
    ipInput.text = "127.0.0.1"
    ipInput.alignment = HORIZONTAL_ALIGNMENT_CENTER
    ipInput.add_theme_font_override("font", fontMedium)
    ipInput.add_theme_font_size_override("font_size", 16)
    ipInput.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
    ipInput.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4))
    var ipStyle = StyleBoxFlat.new()
    ipStyle.bg_color = Color(0.1, 0.1, 0.1, 0.8)
    ipStyle.border_color = Color(0.3, 0.3, 0.3, 0.8)
    ipStyle.set_border_width_all(1)
    ipStyle.set_corner_radius_all(4)
    ipStyle.content_margin_left = 12
    ipStyle.content_margin_right = 12
    ipStyle.content_margin_top = 8
    ipStyle.content_margin_bottom = 8
    ipInput.add_theme_stylebox_override("normal", ipStyle)
    var ipFocus = ipStyle.duplicate()
    ipFocus.border_color = ACCENT
    ipInput.add_theme_stylebox_override("focus", ipFocus)
    center.add_child(ipInput)

    center.add_child(_spacer(4))

    var btnRow = HBoxContainer.new()
    btnRow.add_theme_constant_override("separation", 10)
    btnRow.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(btnRow)

    hostBtn = _make_btn("Host Game")
    hostBtn.pressed.connect(_on_host)
    btnRow.add_child(hostBtn)

    joinBtn = _make_btn("Join Game")
    joinBtn.pressed.connect(_on_join)
    btnRow.add_child(joinBtn)

    dcBtn = _make_btn("Disconnect")
    dcBtn.pressed.connect(_on_dc)
    center.add_child(dcBtn)

    center.add_child(_spacer(8))

    var returnBtn = _make_btn("Return")
    returnBtn.pressed.connect(_on_coop_return)
    center.add_child(returnBtn)


func _make_btn(text: String) -> Button:
    var btn = Button.new()
    btn.text = text
    btn.add_theme_font_override("font", fontMedium)
    btn.add_theme_font_size_override("font_size", 14)
    btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.12, 0.12, 0.12, 0.9)
    style.border_color = Color(0.25, 0.25, 0.25, 0.9)
    style.set_border_width_all(1)
    style.set_corner_radius_all(4)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 6
    style.content_margin_bottom = 6
    btn.add_theme_stylebox_override("normal", style)
    var hover = style.duplicate()
    hover.border_color = ACCENT
    hover.bg_color = Color(0.16, 0.16, 0.16, 0.9)
    btn.add_theme_stylebox_override("hover", hover)
    var pressed = style.duplicate()
    pressed.bg_color = Color(0.08, 0.08, 0.08, 0.9)
    btn.add_theme_stylebox_override("pressed", pressed)
    var disabled = style.duplicate()
    disabled.bg_color = Color(0.08, 0.08, 0.08, 0.5)
    disabled.border_color = Color(0.15, 0.15, 0.15, 0.5)
    btn.add_theme_stylebox_override("disabled", disabled)
    btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.3))
    return btn


func _spacer(height: float) -> Control:
    var s = Control.new()
    s.custom_minimum_size = Vector2(0, height)
    return s


func _process(_delta):
    if !coopPanel || !coopPanel.visible:
        return
    _update_coop_status()


func _update_coop_status():
    var net = _net()

    if net == null:
        statusLabel.text = "[center][color=gray]Network not loaded[/color][/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        dcBtn.disabled = true
        ipInput.editable = true
    elif !net.IsActive():
        statusLabel.text = "[center][color=gray]Disconnected[/color][/center]"
        hostBtn.disabled = false
        joinBtn.disabled = false
        dcBtn.disabled = true
        ipInput.editable = true
    elif net.IsHost():
        var peers = multiplayer.get_peers().size()
        statusLabel.text = "[center][color=#8fc93a]Hosting[/color] — " + str(peers) + " player(s) connected[/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        dcBtn.disabled = false
        ipInput.editable = false
    else:
        statusLabel.text = "[center][color=#8fc93a]Connected[/color] to host[/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        dcBtn.disabled = false
        ipInput.editable = false


func _on_coop_pressed():
    coopPanel.show()
    main.hide()
    PlayClick()


func _on_coop_return():
    main.show()
    coopPanel.hide()
    PlayClick()


func _on_host():
    var net = _net()
    if net:
        net.HostGame()
    PlayClick()


func _on_join():
    var net = _net()
    if net:
        net.JoinGame(ipInput.text)
    PlayClick()


func _on_dc():
    var net = _net()
    if net:
        net.Disconnect()
    PlayClick()
