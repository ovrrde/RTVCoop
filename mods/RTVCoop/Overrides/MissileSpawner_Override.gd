@tool
extends "res://Scripts/MissileSpawner.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func ExecuteLaunchMissiles(value: bool) -> void:
    if Engine.is_editor_hint() or !_net() or !_net().IsActive():
        super(value)
        return
    if !multiplayer.is_server():
        launchMissiles = false
        return
    _coop_host_launch()


func _coop_host_launch() -> void:
    var pool = get_children().filter(func(n): return n.has_method("ExecuteLaunch"))
    var needs_prepare = pool.is_empty()
    if needs_prepare:
        ExecutePrepareMissiles(true)
        pool = get_children().filter(func(n): return n.has_method("ExecuteLaunch"))

    var ws = _pm()._world_sync() if _pm() else null
    if ws and needs_prepare:
        ws.BroadcastMissilePrepare.rpc(get_path())

    pool.shuffle()
    launched = true
    var total = pool.size()
    var fired = 0
    for element in pool:
        await get_tree().create_timer(randf_range(0.0, launchDelay)).timeout
        if !is_instance_valid(element):
            continue
        element.visible = true
        element.ExecuteLaunch(true)
        if ws:
            ws.BroadcastMissileLaunch.rpc(get_path(), element.get_index())
        fired += 1
        if fired == total:
            launched = false
    launchMissiles = false
