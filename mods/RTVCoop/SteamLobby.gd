extends Node

# Wraps Steam lobby creation, joining, invites, and the callback pump.
# Created by Main.gd only when GodotSteam loaded successfully.

const APP_ID = 1963610

const LOBBY_TYPE_PRIVATE = 0
const LOBBY_TYPE_FRIENDS_ONLY = 1
const LOBBY_TYPE_PUBLIC = 2
const LOBBY_TYPE_INVISIBLE = 3

var available: bool = false
var steam = null
var lobby_id: int = 0
var host_steam_id: int = 0

signal lobby_created_ok(id: int)
signal lobby_create_failed(reason: String)
signal lobby_joined_ok(id: int, host_id: int)
signal lobby_join_failed(reason: String)
signal lobby_left


func _ready():
    if !ClassDB.class_exists("Steam"):
        print("[SteamLobby] Steam class not registered — disabled")
        return
    steam = Engine.get_singleton("Steam")
    if !steam:
        print("[SteamLobby] Steam singleton missing — disabled")
        return

    OS.set_environment("SteamAppId", str(APP_ID))
    OS.set_environment("SteamGameId", str(APP_ID))

    var init_result = steam.steamInitEx(false, APP_ID)
    print("[SteamLobby] steamInitEx: " + str(init_result))

    if !steam.isSteamRunning():
        print("[SteamLobby] Steam client not running — disabled")
        return

    available = true

    steam.lobby_created.connect(_on_lobby_created)
    steam.lobby_joined.connect(_on_lobby_joined)
    steam.join_requested.connect(_on_join_requested)
    steam.lobby_chat_update.connect(_on_lobby_chat_update)

    print("[SteamLobby] Ready — " + steam.getPersonaName() + " (" + str(steam.getSteamID()) + ")")

    _check_cold_start_join()


func _check_cold_start_join():
    # Steam appends "+connect_lobby <id>" to argv when launching the game from
    # a friend's "Join Game" while we were offline. The join_requested signal
    # only fires for in-game invites, so cold-starts must be parsed manually.
    var args = OS.get_cmdline_args()
    for i in args.size():
        if args[i] == "+connect_lobby" and i + 1 < args.size():
            var id_str = args[i + 1]
            var target_id = id_str.to_int()
            if target_id > 0:
                print("[SteamLobby] Cold-start +connect_lobby detected: " + str(target_id))
                JoinLobby(target_id)
            return


func _process(_delta):
    if available && steam:
        steam.run_callbacks()


func MyId() -> int:
    if !available: return 0
    return steam.getSteamID()


func MyName() -> String:
    if !available: return ""
    return steam.getPersonaName()


func InLobby() -> bool:
    return lobby_id != 0


func CreateLobby(max_members: int = 4):
    if !available:
        lobby_create_failed.emit("Steam not available")
        return
    print("[SteamLobby] Creating lobby (FRIENDS_ONLY, max=" + str(max_members) + ")")
    steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, max_members)


func JoinLobby(target_lobby_id: int):
    if !available:
        lobby_join_failed.emit("Steam not available")
        return
    print("[SteamLobby] Joining lobby " + str(target_lobby_id))
    steam.joinLobby(target_lobby_id)


func LeaveLobby():
    if !available || lobby_id == 0:
        return
    print("[SteamLobby] Leaving lobby " + str(lobby_id))
    steam.leaveLobby(lobby_id)
    lobby_id = 0
    host_steam_id = 0
    _clear_rich_presence()
    lobby_left.emit()


func _set_rich_presence_for_lobby():
    if !available || lobby_id == 0:
        return
    steam.setRichPresence("status", "In a coop session")
    steam.setRichPresence("connect", "+connect_lobby " + str(lobby_id))


func _clear_rich_presence():
    if !available:
        return
    steam.clearRichPresence()


func OpenInviteOverlay():
    if !available:
        print("[SteamLobby] Steam not available — cannot open overlay")
        return
    if lobby_id == 0:
        print("[SteamLobby] No active lobby — cannot open overlay")
        return
    print("[SteamLobby] Opening invite overlay for lobby " + str(lobby_id))
    steam.activateGameOverlayInviteDialog(lobby_id)


func _on_lobby_created(connect_status: int, new_lobby_id: int):
    print("[SteamLobby] lobby_created: status=" + str(connect_status) + " id=" + str(new_lobby_id))
    if connect_status != 1:
        lobby_create_failed.emit("createLobby returned status " + str(connect_status))
        return
    lobby_id = new_lobby_id
    host_steam_id = steam.getSteamID()
    steam.setLobbyData(lobby_id, "host_steam_id", str(host_steam_id))
    steam.setLobbyData(lobby_id, "mod", "rtv-coop")
    steam.setLobbyJoinable(lobby_id, true)
    _set_rich_presence_for_lobby()
    lobby_created_ok.emit(lobby_id)


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int):
    print("[SteamLobby] lobby_joined: id=" + str(joined_lobby_id) + " response=" + str(response))
    if response != 1:
        lobby_join_failed.emit("joinLobby response " + str(response))
        return
    lobby_id = joined_lobby_id
    var owner_id = steam.getLobbyOwner(joined_lobby_id)
    host_steam_id = owner_id
    print("[SteamLobby] Lobby owner: " + str(owner_id))
    _set_rich_presence_for_lobby()
    if owner_id == steam.getSteamID():
        return
    lobby_joined_ok.emit(joined_lobby_id, owner_id)


func _on_join_requested(target_lobby_id: int, friend_id: int):
    print("[SteamLobby] join_requested from friend " + str(friend_id) + " for lobby " + str(target_lobby_id))
    JoinLobby(target_lobby_id)


func _on_lobby_chat_update(_lobby: int, _changed: int, _maker: int, _state: int):
    pass
