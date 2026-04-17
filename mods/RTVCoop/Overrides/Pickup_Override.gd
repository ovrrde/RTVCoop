extends "res://Scripts/Pickup.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Interact():
    var net = _net()
    if net == null:
        super()
        return
    if net.IsActive():
        var uuid = -1
        if has_meta("network_uuid"):
            uuid = get_meta("network_uuid")
        if uuid < 0:
            interface.PlayError()
            return
        var pm = _pm()
        if pm == null:
            return
        pm.RequestPickup(uuid)
        return
    super()
