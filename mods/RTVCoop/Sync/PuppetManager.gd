extends Node


const PASSTHROUGH_MAPS := ["Cabin"]

var REMOTE_PLAYER: PackedScene = null


func _pm():
    return get_parent()


func _ready():
    REMOTE_PLAYER = load("res://mods/RTVCoop/Scenes/RemotePlayer.tscn")
    if !REMOTE_PLAYER:
        print("[PuppetManager] ERROR: Could not load RemotePlayer.tscn")


func ReconcilePuppets():
    var pm = _pm()
    var map = pm.GetMap()
    if !map:
        for id in pm.remotePlayers.keys().duplicate():
            if !is_instance_valid(pm.remotePlayers[id]):
                pm.remotePlayers.erase(id)
        return

    var myId = multiplayer.get_unique_id()
    var knownPeers: Array = pm.peer_names.keys()

    for peerId in knownPeers:
        if peerId == myId:
            continue
        if !pm.remotePlayers.has(peerId) || !is_instance_valid(pm.remotePlayers[peerId]):
            if pm.remotePlayers.has(peerId):
                pm.remotePlayers.erase(peerId)
            SpawnPuppet(peerId)

    var toRemove = []
    for peerId in pm.remotePlayers.keys():
        if !(peerId in knownPeers):
            toRemove.append(peerId)
    for peerId in toRemove:
        DespawnPuppet(peerId)


func SpawnPuppet(peerId: int):
    var pm = _pm()
    var map = pm.GetMap()
    if !map or !REMOTE_PLAYER:
        return

    var puppet = REMOTE_PLAYER.instantiate()
    puppet.peer_id = peerId
    puppet.name = "RemotePlayer_" + str(peerId)

    var local_ctrl = pm.GetLocalController()
    if local_ctrl:
        puppet.global_position = local_ctrl.global_position
    elif map.has_method("get_global_position"):
        puppet.global_position = map.global_position

    map.add_child(puppet)
    pm.remotePlayers[peerId] = puppet

    var mapName: String = str(map.get("mapName")) if map.get("mapName") else ""
    if mapName in PASSTHROUGH_MAPS:
        if local_ctrl and puppet is PhysicsBody3D:
            local_ctrl.add_collision_exception_with(puppet)

    print("PuppetManager: spawned puppet for peer " + str(peerId))


func DespawnPuppet(peerId: int):
    var pm = _pm()
    if !pm.remotePlayers.has(peerId):
        return
    var puppet = pm.remotePlayers[peerId]
    if is_instance_valid(puppet):
        puppet.queue_free()
    pm.remotePlayers.erase(peerId)
    print("PuppetManager: despawned puppet for peer " + str(peerId))
