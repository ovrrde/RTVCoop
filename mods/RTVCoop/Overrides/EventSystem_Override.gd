extends "res://Scripts/EventSystem.gd"

var _net_c: Node
var _pm_c: Node
var _coop_event_id: int = 0
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _next_coop_name(base: String) -> String:
    _coop_event_id += 1
    return base + "_coop_" + str(_coop_event_id)


func _ready() -> void:
    add_to_group("EventSystem")
    await get_tree().create_timer(5.0, false).timeout
    map = get_tree().current_scene.get_node("/root/Map")

    GetAvailableEvents()

    if !_net().IsActive() or multiplayer.is_server():
        ActivateDynamicEvent()
        ActivateSpecialEvent()

    ActivateTraderEvent()


func FighterJet():
    if _net().IsActive() and !multiplayer.is_server():
        return
    var instance = jet.instantiate()
    add_child(instance)
    if _net().IsActive() and multiplayer.is_server():
        var cname = _next_coop_name("FighterJet")
        instance.name = cname
        _pm()._event_sync().BroadcastEvent.rpc("FighterJet", {
            "pos": instance.global_position,
            "rot": instance.global_rotation,
            "_cname": cname,
        })


func Airdrop():
    if _net().IsActive() and !multiplayer.is_server():
        return
    var instance = casa.instantiate()
    add_child(instance)
    if _net().IsActive() and multiplayer.is_server():
        var cname = _next_coop_name("CASA")
        instance.name = cname
        _pm()._event_sync().BroadcastEvent.rpc("Airdrop", {
            "pos": instance.global_position,
            "rot": instance.global_rotation,
            "dropThreshold": instance.dropThreshold,
            "_cname": cname,
        })


func Helicopter():
    if _net().IsActive() and !multiplayer.is_server():
        return
    var instance = helicopter.instantiate()
    add_child(instance)
    if _net().IsActive() and multiplayer.is_server():
        var cname = _next_coop_name("Helicopter")
        instance.name = cname
        _pm()._event_sync().BroadcastEvent.rpc("Helicopter", {
            "pos": instance.global_position,
            "rot": instance.global_rotation,
            "_cname": cname,
        })


func Police():
    if _net().IsActive() and !multiplayer.is_server():
        return

    var randomPath = paths.get_child(randi_range(0, paths.get_child_count() - 1))
    var pathDirection = randi_range(1, 2)
    var inversePath = pathDirection != 1
    var initialWaypoint = randomPath.get_child(randomPath.get_child_count() - 1) if inversePath else randomPath.get_child(0)

    var instance = police.instantiate()
    add_child(instance)
    instance.selectedPath = randomPath
    instance.inversePath = inversePath
    instance.global_transform = initialWaypoint.global_transform

    if _net().IsActive() and multiplayer.is_server():
        var cname = _next_coop_name("Police")
        instance.name = cname
        var pathIndex = randomPath.get_index()
        _pm()._event_sync().BroadcastEvent.rpc("Police", {
            "pathIndex": pathIndex,
            "inverse": inversePath,
            "_cname": cname,
        })


func BTR():
    if _net().IsActive() and !multiplayer.is_server():
        return

    var randomPath = paths.get_child(randi_range(0, paths.get_child_count() - 1))
    var pathDirection = randi_range(1, 2)
    var inversePath = pathDirection != 1
    var initialWaypoint = randomPath.get_child(randomPath.get_child_count() - 1) if inversePath else randomPath.get_child(0)

    var instance = btr.instantiate()
    add_child(instance)
    instance.selectedPath = randomPath
    instance.inversePath = inversePath
    instance.global_transform = initialWaypoint.global_transform

    if _net().IsActive() and multiplayer.is_server():
        var cname = _next_coop_name("BTR")
        instance.name = cname
        var pathIndex = randomPath.get_index()
        _pm()._event_sync().BroadcastEvent.rpc("BTR", {
            "pathIndex": pathIndex,
            "inverse": inversePath,
            "_cname": cname,
        })


func CrashSite():
    if _net().IsActive() and !multiplayer.is_server():
        return

    var crashIndex = randi_range(0, crashes.get_child_count() - 1)
    var randomCrash = crashes.get_child(crashIndex)
    var crashSite = crash.instantiate()
    randomCrash.add_child(crashSite)
    crashSite.global_transform = randomCrash.global_transform

    if _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastEvent.rpc("CrashSite", {"crashIndex": crashIndex})


func Cat():
    if _net().IsActive() and !multiplayer.is_server():
        return
    if gameData.catFound or gameData.catDead:
        return

    var wells = get_tree().get_nodes_in_group("Well")
    if wells.size() == 0:
        return

    var wellIndex = randi_range(0, wells.size() - 1)
    var randomWell: Node3D = wells[wellIndex]
    var wellBottom = randomWell.get_node_or_null("Bottom")
    if !wellBottom:
        return

    var catInstance = cat.instantiate()
    wellBottom.add_child(catInstance)
    catInstance.global_transform = wellBottom.global_transform
    var catSystem = catInstance.get_child(0)
    catSystem.currentState = catSystem.State.Rescue

    var rescueInstance = rescue.instantiate()
    wellBottom.add_child(rescueInstance)
    rescueInstance.global_transform = wellBottom.global_transform
    rescueInstance.cat = catInstance
    rescueInstance.position.y = 3.0

    if _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastEvent.rpc("Cat", {"wellIndex": wellIndex})


func Transmission():
    if _net().IsActive() and !multiplayer.is_server():
        return
    super()
    if _net().IsActive() and multiplayer.is_server():
        _pm()._event_sync().BroadcastEvent.rpc("Transmission", {})


func ActivateTrader():
    super()

func DeactivateTrader():
    super()
