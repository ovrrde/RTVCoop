extends Node


const DEFAULT_PORT = 27015
const DEFAULT_MAX_PEERS = 4
const DEFAULT_ADDRESS = "127.0.0.1"


enum Mode {NONE, HOST, CLIENT}
enum Transport {ENET, STEAM}


var mode: Mode = Mode.NONE
var transport: Transport = Transport.ENET
var peer = null


signal hosted
signal joined
signal disconnected
signal peer_joined(id: int)
signal peer_left(id: int)
signal connection_failed_signal


const PEER_TIMEOUT_MS = 90000  # 90 seconds — heavy scenes may take longer, depending on hardware


func _ready():
    print("[Network] Autoload Ready!")
    if ClassDB.class_exists("SteamMultiplayerPeer"):
        transport = Transport.STEAM
        print("[Network] Transport: SteamMultiplayerPeer (NAT-traversal via Steam Datagram Relay)")
    else:
        transport = Transport.ENET
        print("[Network] Transport: ENetMultiplayerPeer (direct IP)")
    print("[Network] F9=ENet host, F10=ENet join, F11=disconnect (hotkeys are loopback-test only — UI buttons use Steam when available)")
    print("[Network] Node path: " + str(get_path()))
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)


func HostGame(port: int = DEFAULT_PORT, maxPeers: int = DEFAULT_MAX_PEERS) -> bool:

    if mode != Mode.NONE:
        print("[Network] already active (" + str(mode) + ") — disconnect first")
        return false

    if transport == Transport.STEAM:
        return _host_steam(maxPeers)
    return _host_enet(port, maxPeers)


# Forces the ENet path — used by the F9 loopback hotkey since Steam can't
# loopback on one machine.
func HostGameEnet(port: int = DEFAULT_PORT, maxPeers: int = DEFAULT_MAX_PEERS) -> bool:

    if mode != Mode.NONE:
        print("[Network] already active (" + str(mode) + ") — disconnect first")
        return false

    return _host_enet(port, maxPeers)


func _host_steam(maxPeers: int) -> bool:
    var p = ClassDB.instantiate("SteamMultiplayerPeer")
    if !p:
        print("[Network] SteamMultiplayerPeer instantiate failed")
        return false

    var err = p.create_host(0)
    if err != OK:
        print("[Network] Steam host failed (err " + str(err) + ")")
        return false

    peer = p
    multiplayer.multiplayer_peer = peer
    mode = Mode.HOST

    print("[Network] HOSTING via Steam (max " + str(maxPeers) + " peers)")
    print("[Network] my id is " + str(multiplayer.get_unique_id()))
    hosted.emit()
    return true


func _host_enet(port: int, maxPeers: int) -> bool:
    var p = ENetMultiplayerPeer.new()
    var err = p.create_server(port, maxPeers)

    if err != OK:
        print("[Network] ENet host failed (err " + str(err) + ")")
        return false

    peer = p
    multiplayer.multiplayer_peer = peer
    mode = Mode.HOST

    SetPeerTimeouts()

    print("[Network] HOSTING on port " + str(port) + " (max " + str(maxPeers) + " peers)")
    print("[Network] my id is " + str(multiplayer.get_unique_id()))
    hosted.emit()
    return true


func JoinGame(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> bool:

    if mode != Mode.NONE:
        print("[Network] already active (" + str(mode) + ") — disconnect first")
        return false

    return _join_enet(address, port)


func JoinSteam(host_id: int) -> bool:

    if mode != Mode.NONE:
        print("[Network] already active (" + str(mode) + ") — disconnect first")
        return false

    if transport != Transport.STEAM:
        print("[Network] cannot JoinSteam — Steam transport unavailable")
        return false

    var p = ClassDB.instantiate("SteamMultiplayerPeer")
    if !p:
        print("[Network] SteamMultiplayerPeer instantiate failed")
        return false

    var err = p.create_client(host_id, 0)
    if err != OK:
        print("[Network] Steam join failed (err " + str(err) + ")")
        return false

    peer = p
    multiplayer.multiplayer_peer = peer
    mode = Mode.CLIENT

    print("[Network] JOINING Steam host " + str(host_id) + "...")
    return true


func _join_enet(address: String, port: int) -> bool:
    var p = ENetMultiplayerPeer.new()
    var err = p.create_client(address, port)

    if err != OK:
        print("[Network] ENet join failed (err " + str(err) + ")")
        return false

    peer = p
    multiplayer.multiplayer_peer = peer
    mode = Mode.CLIENT

    print("[Network] JOINING " + address + ":" + str(port) + "...")
    return true


func Disconnect():

    if mode == Mode.NONE:
        return


    if peer:
        peer.close()
        peer = null


    multiplayer.multiplayer_peer = null
    mode = Mode.NONE


    print("[Network] disconnected")
    disconnected.emit()


func SetPeerTimeouts():
    if !peer or !(peer is ENetMultiplayerPeer):
        return
    if !peer.host:
        return
    for p in peer.host.get_peers():
        p.set_timeout(0, 0, PEER_TIMEOUT_MS)


func IsHost() -> bool:
    return mode == Mode.HOST

func IsClient() -> bool:
    return mode == Mode.CLIENT

func IsActive() -> bool:
    return mode != Mode.NONE

func IsSteamTransport() -> bool:
    return transport == Transport.STEAM

func GetPeerIds() -> Array:
    if mode == Mode.NONE:
        return []
    return multiplayer.get_peers()


func _on_peer_connected(id: int):
    print("[Network] peer connected (" + str(id) + ")")
    SetPeerTimeouts()
    peer_joined.emit(id)

func _on_peer_disconnected(id: int):
    print("[Network] peer disconnected (" + str(id) + ")")
    peer_left.emit(id)

func _on_connected_to_server():
    print("[Network] connected to host (my id = " + str(multiplayer.get_unique_id()) + ")")
    SetPeerTimeouts()
    joined.emit()

func _on_connection_failed():
    print("[Network] connection failed")
    peer = null
    multiplayer.multiplayer_peer = null
    mode = Mode.NONE
    connection_failed_signal.emit()

func _on_server_disconnected():
    print("[Network] host disconnected")
    peer = null
    multiplayer.multiplayer_peer = null
    mode = Mode.NONE
    disconnected.emit()


func _input(event):

    if event is InputEventKey && event.pressed && !event.echo:

        if event.physical_keycode == KEY_F9:
            print("[Network] F9 pressed — ENet host (loopback test)")
            HostGameEnet()

        elif event.physical_keycode == KEY_F10:
            print("[Network] F10 pressed — ENet join " + DEFAULT_ADDRESS + " (loopback test)")
            JoinGame()

        elif event.physical_keycode == KEY_F11:
            print("[Network] F11 pressed — disconnecting")
            Disconnect()
