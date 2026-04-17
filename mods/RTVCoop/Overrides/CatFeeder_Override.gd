extends "res://Scripts/CatFeeder.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func TryFeeding():
    var before = gameData.cat
    super()
    if _net() and _net().IsActive() and gameData.cat != before:
        var ws = _pm()._world_sync() if _pm() else null
        if ws:
            if multiplayer.is_server():
                ws.BroadcastCatState.rpc(gameData.catFound, gameData.catDead, gameData.cat)
            else:
                ws.RequestCatState.rpc_id(1, gameData.catFound, gameData.catDead, gameData.cat)
