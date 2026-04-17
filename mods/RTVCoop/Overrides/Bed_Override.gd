extends "res://Scripts/Bed.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Interact():
    if !canSleep:
        return
    if !_net() or !_net().IsActive():
        super()
        return
    var es = _pm()._event_sync()
    if !es:
        return
    if multiplayer.is_server():
        es.HostToggleSleepReady(multiplayer.get_unique_id(), randomSleep)
    else:
        es.RequestSleepReady.rpc_id(1, randomSleep)


func UpdateTooltip():
    if !_net() or !_net().IsActive():
        super()
        return
    if !canSleep:
        gameData.tooltip = ""
        return
    var es = _pm()._event_sync()
    var my_id = multiplayer.get_unique_id()
    if es and es._sleep_ready.has(my_id):
        gameData.tooltip = "Sleep [Cancel]"
    else:
        gameData.tooltip = "Sleep (Random: 6-12h) [Ready]"
