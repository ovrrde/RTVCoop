extends "res://Scripts/Switch.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Interact():
    if _net().IsActive() && !multiplayer.is_server():
        _pm()._interactable_sync().RequestSwitchToggle.rpc_id(1, get_path())
        return

    var newActive = !active
    ApplySwitchState(newActive)

    if _net().IsActive() && multiplayer.is_server():
        _pm()._interactable_sync().BroadcastSwitchState.rpc(get_path(), newActive)


func ApplySwitchState(newActive: bool):
    active = newActive
    if active:
        Activate()
    else:
        Deactivate()
    PlaySwitch()
