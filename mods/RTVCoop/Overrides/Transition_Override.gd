extends "res://Scripts/Transition.gd"


var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func Interact():
    super()
    if _net() and _net().IsActive() and multiplayer.is_server() and !locked and !tutorialExit:
        var isync = _pm()._interactable_sync() if _pm() else null
        if isync:
            isync.BroadcastTransitionDrain.rpc(energy, hydration)
