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
    print("[Pickup_Override] Interact called on: " + str(name))
    var net = _net()
    if net == null:
        print("[Pickup_Override] Network node is NULL — falling through to solo")
        super()
        return
    print("[Pickup_Override] Network active: " + str(net.IsActive()))
    if net.IsActive():
        var uuid = -1
        if has_meta("network_uuid"):
            uuid = get_meta("network_uuid")
        print("[Pickup_Override] UUID: " + str(uuid))
        if uuid < 0:
            print("[Pickup_Override] No UUID — playing error")
            interface.PlayError()
            return
        var pm = _pm()
        if pm == null:
            print("[Pickup_Override] PlayerManager is NULL")
            return
        print("[Pickup_Override] Requesting pickup UUID " + str(uuid))
        pm.RequestPickup(uuid)
        return

    super()
