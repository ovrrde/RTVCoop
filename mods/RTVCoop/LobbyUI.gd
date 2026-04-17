extends CanvasLayer


var fontMedium = load("res://Fonts/Lora-Medium.ttf")
var fontSemiBold = load("res://Fonts/Lora-SemiBold.ttf")

var coopButton: Button = null
var coopPanel: Control = null
var menuMain: Control = null

var steamLabel: RichTextLabel
var statusLabel: RichTextLabel
var playersLabel: RichTextLabel
var hostBtn: Button
var inviteBtn: Button
var dcBtn: Button

var continueBtn: Button
var newGameBtn: Button
var waitingLabel: RichTextLabel

var injected: bool = false
var steam_signals_hooked: bool = false

const ACCENT = Color(0.56, 0.79, 0.23, 1.0)


func _net():
    return get_tree().root.get_node_or_null("Network")


func _steam_lobby():
    return get_tree().root.get_node_or_null("SteamLobby")


func _pm():
    return get_tree().root.get_node_or_null("PlayerManager")


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
        if coopPanel and coopPanel.visible:
            _update_status()
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

    var buttons = scene.get_node_or_null("Main/Buttons")
    var templateBtn = buttons.get_child(0) if buttons and buttons.get_child_count() > 0 else null

    var buttonColumn = VBoxContainer.new()
    buttonColumn.anchor_left = 0.5
    buttonColumn.anchor_right = 0.5
    buttonColumn.anchor_top = 0.5
    buttonColumn.anchor_bottom = 0.5
    buttonColumn.offset_left = -160
    buttonColumn.offset_right = 160
    buttonColumn.offset_top = -150
    buttonColumn.offset_bottom = 150
    buttonColumn.grow_horizontal = Control.GROW_DIRECTION_BOTH
    buttonColumn.grow_vertical = Control.GROW_DIRECTION_BOTH
    buttonColumn.add_theme_constant_override("separation", 6)
    coopPanel.add_child(buttonColumn)

    hostBtn = _clone_menu_btn(templateBtn, "Host Game")
    hostBtn.pressed.connect(_on_host)
    buttonColumn.add_child(hostBtn)

    inviteBtn = _clone_menu_btn(templateBtn, "Invite Friend")
    inviteBtn.pressed.connect(_on_invite)
    buttonColumn.add_child(inviteBtn)

    dcBtn = _clone_menu_btn(templateBtn, "Disconnect")
    dcBtn.pressed.connect(_on_dc)
    buttonColumn.add_child(dcBtn)

    buttonColumn.add_child(_divider())

    continueBtn = _clone_menu_btn(templateBtn, "Continue")
    continueBtn.pressed.connect(_on_continue)
    buttonColumn.add_child(continueBtn)

    newGameBtn = _clone_menu_btn(templateBtn, "New Game")
    newGameBtn.pressed.connect(_on_new_game)
    buttonColumn.add_child(newGameBtn)

    waitingLabel = _make_label(13, "[center][color=#e0c850]Waiting for host to start the game...[/color][/center]")
    waitingLabel.visible = false
    buttonColumn.add_child(waitingLabel)

    buttonColumn.add_child(_divider())

    var returnBtn = _clone_menu_btn(templateBtn, "Return")
    returnBtn.pressed.connect(_on_return)
    buttonColumn.add_child(returnBtn)

    # Right-side info column (status + player list)
    var infoColumn = VBoxContainer.new()
    infoColumn.anchor_left = 1.0
    infoColumn.anchor_right = 1.0
    infoColumn.anchor_top = 0.5
    infoColumn.anchor_bottom = 0.5
    infoColumn.offset_left = -320
    infoColumn.offset_right = -40
    infoColumn.offset_top = -150
    infoColumn.offset_bottom = 150
    infoColumn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    infoColumn.grow_vertical = Control.GROW_DIRECTION_BOTH
    infoColumn.add_theme_constant_override("separation", 6)
    coopPanel.add_child(infoColumn)

    steamLabel = _make_label(13, "[right][color=gray]Steam: checking...[/color][/right]")
    steamLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    infoColumn.add_child(steamLabel)

    statusLabel = _make_label(16, "[right]Disconnected[/right]")
    statusLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    infoColumn.add_child(statusLabel)

    infoColumn.add_child(_divider())

    var playersHeader = _make_label(11, "[right][color=gray]PLAYERS[/color][/right]")
    playersHeader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    infoColumn.add_child(playersHeader)

    playersLabel = _make_label(13, "[right][color=gray]Not connected[/color][/right]")
    playersLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    infoColumn.add_child(playersLabel)


func _make_label(size: int, text: String) -> RichTextLabel:
    var lbl = RichTextLabel.new()
    lbl.bbcode_enabled = true
    lbl.fit_content = true
    lbl.scroll_active = false
    lbl.add_theme_font_override("normal_font", fontMedium)
    lbl.add_theme_font_size_override("normal_font_size", size)
    lbl.text = text
    return lbl


func _divider() -> Control:
    var s = Control.new()
    s.custom_minimum_size = Vector2(0, 6)
    return s


func _clone_menu_btn(templateBtn, text: String) -> Button:
    if templateBtn:
        var btn = templateBtn.duplicate()
        btn.text = text
        for sig in btn.get_signal_list():
            for conn in btn.get_signal_connection_list(sig.name):
                if btn.is_connected(sig.name, conn.callable):
                    btn.disconnect(sig.name, conn.callable)
        return btn
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


func _update_status():
    var net = _net()
    var lobby = _steam_lobby()

    if lobby and lobby.available:
        steamLabel.text = "[right][color=#8fc93a]Steam:[/color] " + lobby.MyName() + "[/right]"
    elif lobby:
        steamLabel.text = "[right][color=gray]Steam: not available[/color][/right]"
    else:
        steamLabel.text = "[right][color=gray]Steam: not loaded[/color][/right]"

    var steam_ok: bool = lobby != null and lobby.available

    var is_host: bool = net != null and net.IsActive() and net.IsHost()
    var is_client: bool = net != null and net.IsActive() and !net.IsHost()
    var is_connected: bool = is_host or is_client

    if net == null:
        statusLabel.text = "[right][color=gray]Network not loaded[/color][/right]"
    elif !net.IsActive():
        statusLabel.text = "[right][color=gray]Disconnected[/color][/right]"
    elif is_host:
        var peers = multiplayer.get_peers().size()
        var transport_tag = "Steam" if net.IsSteamTransport() else "ENet"
        statusLabel.text = "[right][color=#8fc93a]Hosting[/color] (" + transport_tag + ") — " + str(peers + 1) + " player(s)[/right]"
    else:
        var transport_tag2 = "Steam" if net.IsSteamTransport() else "ENet"
        statusLabel.text = "[right][color=#8fc93a]Connected[/color] (" + transport_tag2 + ")[/right]"

    hostBtn.disabled = is_connected
    inviteBtn.disabled = !(is_host and steam_ok and lobby.InLobby())
    dcBtn.disabled = !is_connected

    _update_player_list(is_connected)
    _update_start_buttons(is_host, is_client)


func _update_player_list(is_connected: bool):
    if !is_connected:
        playersLabel.text = "[right][color=gray]Not connected[/color][/right]"
        return
    var pm = _pm()
    var names: Array = []
    var my_id: int = multiplayer.get_unique_id()
    if pm and pm.peer_names:
        var ids: Array = pm.peer_names.keys()
        ids.sort()
        for id in ids:
            var name_str: String = str(pm.peer_names[id])
            var tag: String = " (you)" if id == my_id else ""
            var role: String = " [color=#8fc93a][host][/color]" if id == 1 else ""
            names.append(name_str + role + tag)
    if names.is_empty():
        playersLabel.text = "[right][color=gray]Waiting for players...[/color][/right]"
    else:
        playersLabel.text = "[right]" + "\n".join(names) + "[/right]"


func _update_start_buttons(is_host: bool, is_client: bool):
    continueBtn.visible = is_host
    newGameBtn.visible = is_host
    waitingLabel.visible = is_client

    if is_host:
        var has_save: bool = Loader.ValidateShelter() != ""
        continueBtn.disabled = !has_save


func _on_coop_pressed():
    if coopPanel and menuMain:
        coopPanel.show()
        menuMain.hide()


func _on_return():
    if coopPanel and menuMain:
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


func _on_continue():
    var net = _net()
    if !net or !net.IsActive() or !net.IsHost():
        return
    var target: String = Loader.ValidateShelter()
    if target == "":
        return
    if coopPanel:
        coopPanel.hide()
    Loader.LoadScene(target)


func _on_new_game():
    var net = _net()
    if !net or !net.IsActive() or !net.IsHost():
        return
    var scene = get_tree().current_scene
    if scene == null:
        return
    var modes = scene.get_node_or_null("Modes")
    if coopPanel:
        coopPanel.hide()
    if modes:
        modes.show()


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
