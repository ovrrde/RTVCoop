extends "res://Scripts/Layouts.gd"

var _net_c: Node
var _pm_c: Node
func _net():
    if !_net_c: _net_c = get_tree().root.get_node_or_null("Network")
    return _net_c
func _pm():
    if !_pm_c: _pm_c = get_tree().root.get_node_or_null("PlayerManager")
    return _pm_c


func _ready():
    if _net() and _net().IsActive():
        var s = await _pm().CoopSeedForNode(self)
        if s != 0:
            seed(s)
    super()
