extends "res://Scripts/UIManager.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func OpenContainer(container: LootContainer):
    var pm = _pm()
    if !pm or !_net() or !_net().IsActive() or pm._container_open_bypassed:
        super(container)
        return
    pm.TryOpenContainer(container)
