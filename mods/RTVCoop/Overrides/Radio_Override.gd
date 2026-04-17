extends "res://Scripts/Radio.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Interact():
    var ws = _pm()._world_sync() if _pm() else null
    if ws and ws.CoopRouteInteractToggle(get_path()):
        return
    super()


func _coop_remote_interact():
    super.Interact()
