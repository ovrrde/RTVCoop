extends CanvasLayer


var fontMedium = load("res://Fonts/Lora-Medium.ttf")
var fontSemiBold = load("res://Fonts/Lora-SemiBold.ttf")

var coopButton: Button = null
var coopPanel: Control = null
var menuMain: Control = null
var statusLabel: RichTextLabel
var steamLabel: RichTextLabel
var directIpLabel: RichTextLabel
var ipInput: LineEdit
var hostBtn: Button
var joinBtn: Button
var inviteBtn: Button
var dcBtn: Button
var injected: bool = false
var steam_signals_hooked: bool = false

const ACCENT = Color(0.56, 0.79, 0.23, 1.0)


func _net():
    return get_tree().root.get_node_or_null("Network")


func _steam_lobby():
    return get_tree().root.get_node_or_null("SteamLobby")


func _ready():
    layer = 50


func _process(_delta):
    _hook_steam_signals_once()

    var scene = get_tree().current_scene
    if scene == null:
        return

    if scene.name != "Map":
        if !injected:
            _try_inject(scene)
        if coopPanel:
            _update_status()
        if coopPanel:
            coopPanel.visible = coopPanel.visible  # keep as-is
    else:
        if coopPanel:
            coopPanel.hide()
        injected = false
        coopButton = null
        coopPanel = null
        menuMain = null


func _hook_steam_signals_once():
    if steam_signals_hooked:
        return
    var lobby = _steam_lobby()
    if !lobby:
        return
    lobby.lobby_created_ok.connect(_on_lobby_created_ok)
    lobby.lobby_create_failed.connect(_on_lobby_create_failed)
    lobby.lobby_joined_ok.connect(_on_lobby_joined_ok)
    lobby.lobby_join_failed.connect(_on_lobby_join_failed)
    steam_signals_hooked = true
    print("[CoopLobby] Hooked SteamLobby signals")


func _try_inject(scene: Node):
    var buttons = scene.get_node_or_null("Main/Buttons")
    if !buttons:
        return

    menuMain = scene.get_node_or_null("Main")

    for child in buttons.get_children():
        if child.name == "CoopBtn":
            injected = true
            return

    if buttons.get_child_count() == 0:
        return

    var templateBtn = buttons.get_child(0)
    coopButton = templateBtn.duplicate()
    coopButton.name = "CoopBtn"
    coopButton.text = "Co-op"

    for sig in coopButton.get_signal_list():
        for conn in coopButton.get_signal_connection_list(sig.name):
            if coopButton.is_connected(sig.name, conn.callable):
                coopButton.disconnect(sig.name, conn.callable)

    coopButton.pressed.connect(_on_coop_pressed)

    buttons.add_child(coopButton)
    buttons.move_child(coopButton, 2)

    _create_panel(scene)

    injected = true
    print("[RTVCoop] Co-op button injected into menu")


func _create_panel(scene: Node):
    coopPanel = Control.new()
    coopPanel.name = "CoopPanel"
    coopPanel.set_anchors_preset(Control.PRESET_FULL_RECT)
    coopPanel.hide()
    scene.add_child(coopPanel)

    var center = VBoxContainer.new()
    center.anchor_left = 0.5
    center.anchor_right = 0.5
    center.anchor_top = 0.35
    center.anchor_bottom = 0.7
    center.offset_left = -160
    center.offset_right = 160
    center.offset_top = -80
    center.offset_bottom = 80
    center.grow_horizontal = Control.GROW_DIRECTION_BOTH
    center.grow_vertical = Control.GROW_DIRECTION_BOTH
    center.add_theme_constant_override("separation", 8)
    coopPanel.add_child(center)

    var buttons = scene.get_node_or_null("Main/Buttons")
    var templateBtn = buttons.get_child(0) if buttons && buttons.get_child_count() > 0 else null

    steamLabel = RichTextLabel.new()
    steamLabel.bbcode_enabled = true
    steamLabel.fit_content = true
    steamLabel.scroll_active = false
    steamLabel.add_theme_font_override("normal_font", fontMedium)
    steamLabel.add_theme_font_size_override("normal_font_size", 13)
    steamLabel.text = "[center][color=gray]Steam: checking...[/color][/center]"
    center.add_child(steamLabel)

    statusLabel = RichTextLabel.new()
    statusLabel.bbcode_enabled = true
    statusLabel.fit_content = true
    statusLabel.scroll_active = false
    statusLabel.add_theme_font_override("normal_font", fontMedium)
    statusLabel.add_theme_font_size_override("normal_font_size", 16)
    statusLabel.text = "[center]Disconnected[/center]"
    center.add_child(statusLabel)

    center.add_child(_spacer(4))

    directIpLabel = RichTextLabel.new()
    directIpLabel.bbcode_enabled = true
    directIpLabel.fit_content = true
    directIpLabel.scroll_active = false
    directIpLabel.add_theme_font_override("normal_font", fontMedium)
    directIpLabel.add_theme_font_size_override("normal_font_size", 11)
    directIpLabel.text = "[center][color=gray]Direct IP[/color][/center]"
    center.add_child(directIpLabel)

    ipInput = LineEdit.new()
    ipInput.placeholder_text = "Enter IP Address"
    ipInput.text = "127.0.0.1"
    ipInput.alignment = HORIZONTAL_ALIGNMENT_CENTER
    ipInput.add_theme_font_override("font", fontMedium)
    ipInput.add_theme_font_size_override("font_size", 16)
    ipInput.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
    ipInput.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4))
    var ipStyle = StyleBoxFlat.new()
    ipStyle.bg_color = Color(0.06, 0.06, 0.06, 0.9)
    ipStyle.border_color = Color(0.2, 0.2, 0.2, 0.8)
    ipStyle.set_border_width_all(1)
    ipStyle.set_corner_radius_all(2)
    ipStyle.content_margin_left = 12
    ipStyle.content_margin_right = 12
    ipStyle.content_margin_top = 8
    ipStyle.content_margin_bottom = 8
    ipInput.add_theme_stylebox_override("normal", ipStyle)
    ipInput.add_theme_stylebox_override("focus", ipStyle)
    center.add_child(ipInput)

    center.add_child(_spacer(4))

    hostBtn = _clone_menu_btn(templateBtn, "Host Game")
    hostBtn.pressed.connect(_on_host)
    center.add_child(hostBtn)

    joinBtn = _clone_menu_btn(templateBtn, "Join Game")
    joinBtn.pressed.connect(_on_join)
    center.add_child(joinBtn)

    inviteBtn = _clone_menu_btn(templateBtn, "Invite Friend")
    inviteBtn.pressed.connect(_on_invite)
    center.add_child(inviteBtn)

    dcBtn = _clone_menu_btn(templateBtn, "Disconnect")
    dcBtn.pressed.connect(_on_dc)
    center.add_child(dcBtn)

    center.add_child(_spacer(2))

    var returnBtn = _clone_menu_btn(templateBtn, "Return")
    returnBtn.pressed.connect(_on_return)
    center.add_child(returnBtn)


func _clone_menu_btn(templateBtn, text: String) -> Button:
    if templateBtn:
        var btn = templateBtn.duplicate()
        btn.text = text
        for sig in btn.get_signal_list():
            for conn in btn.get_signal_connection_list(sig.name):
                if btn.is_connected(sig.name, conn.callable):
                    btn.disconnect(sig.name, conn.callable)
        return btn
    else:
        return _make_btn(text)


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


func _spacer(h: float) -> Control:
    var s = Control.new()
    s.custom_minimum_size = Vector2(0, h)
    return s


func _update_status():
    var net = _net()
    var lobby = _steam_lobby()

    # Steam header
    if lobby and lobby.available:
        steamLabel.text = "[center][color=#8fc93a]Steam:[/color] " + lobby.MyName() + "[/center]"
    elif lobby:
        steamLabel.text = "[center][color=gray]Steam: not available — direct IP only[/color][/center]"
    else:
        steamLabel.text = "[center][color=gray]Steam: not loaded[/color][/center]"

    var steam_ok: bool = lobby != null and lobby.available

    # Direct IP label reflects whether it's the primary path or a fallback
    if directIpLabel:
        if steam_ok:
            directIpLabel.text = "[center][color=#606060]Direct IP (fallback)[/color][/center]"
        else:
            directIpLabel.text = "[center][color=gray]Direct IP[/color][/center]"

    if net == null:
        statusLabel.text = "[center][color=gray]Network not loaded[/color][/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        inviteBtn.disabled = true
        dcBtn.disabled = true
    elif !net.IsActive():
        statusLabel.text = "[center][color=gray]Disconnected[/color][/center]"
        hostBtn.disabled = false
        joinBtn.disabled = false
        inviteBtn.disabled = true
        dcBtn.disabled = true
        ipInput.editable = true
    elif net.IsHost():
        var peers = multiplayer.get_peers().size()
        var transport_tag = "Steam" if net.IsSteamTransport() else "ENet"
        statusLabel.text = "[center][color=#8fc93a]Hosting[/color] (" + transport_tag + ") — " + str(peers) + " player(s)[/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        inviteBtn.disabled = !(steam_ok and lobby.InLobby())
        dcBtn.disabled = false
        ipInput.editable = false
    else:
        var transport_tag2 = "Steam" if net.IsSteamTransport() else "ENet"
        statusLabel.text = "[center][color=#8fc93a]Connected[/color] (" + transport_tag2 + ")[/center]"
        hostBtn.disabled = true
        joinBtn.disabled = true
        inviteBtn.disabled = true
        dcBtn.disabled = false
        ipInput.editable = false


func _on_coop_pressed():
    if coopPanel && menuMain:
        coopPanel.show()
        menuMain.hide()


func _on_return():
    if coopPanel && menuMain:
        coopPanel.hide()
        menuMain.show()


func _on_host():
    var net = _net()
    if !net:
        return
    if !net.HostGame():
        return
    var lobby = _steam_lobby()
    if lobby and lobby.available:
        lobby.CreateLobby()


func _on_join():
    var net = _net()
    if net:
        net.JoinGame(ipInput.text)


func _on_invite():
    var lobby = _steam_lobby()
    if lobby:
        lobby.OpenInviteOverlay()


func _on_dc():
    var net = _net()
    if net:
        net.Disconnect()
    var lobby = _steam_lobby()
    if lobby:
        lobby.LeaveLobby()


func _on_lobby_created_ok(id: int):
    print("[CoopLobby] Steam lobby created: " + str(id))


func _on_lobby_create_failed(reason: String):
    print("[CoopLobby] Steam lobby create FAILED: " + reason)


func _on_lobby_joined_ok(_id: int, host_id: int):
    print("[CoopLobby] Steam lobby joined; host=" + str(host_id) + " — connecting peer")
    var net = _net()
    if net:
        net.JoinSteam(host_id)


func _on_lobby_join_failed(reason: String):
    print("[CoopLobby] Steam lobby join FAILED: " + reason)
